#!/usr/bin/env python3
"""Preprocesses ROS 2's shipped .idl files so Cyclone DDS's idlc can
compile them, without needing to hand-patch each affected file.

Two independent idlc bugs (both confirmed via targeted repro, not
guessed) motivate this:

1. None of ROS 2's shipped .idl files have include guards. Any message
   with a "diamond" dependency (two different paths reaching the same
   common type, e.g. Header -> Time and Pose -> ... -> Time) makes
   idlc process that file's declarations twice and crash with
   "Declaration 'X' collides with earlier a declaration of 'X'".
   Fix: wrap every file in a standard #ifndef/#define/#endif guard —
   verified idlc's preprocessor honors these correctly.

2. A struct whose name matches an IDL keyword case-insensitively
   (Int16 ~ int16, String ~ string, ...) crashes idlc's parser when a
   @verbatim annotation precedes it (which ROS 2's generated IDL
   always has, for the doc comment). Fix: rename the struct. The
   rename is purely a local compile-time detail — the actual DDS wire
   type name is patched back to the real ROS 2 convention separately,
   by dds_manager's existing MANGLE_ROS_TYPENAME step, which needs to
   know the *original* name. This script writes that mapping to
   _rename_manifest.tsv (original_name<TAB>renamed_name per line) so
   CMake can look it up instead of hard-coding it.
"""
import argparse
import os
import re
import sys

# Full OMG IDL4 reserved-word list (case-insensitive per the spec) —
# any struct/field/const whose name happens to match one of these
# crashes idlc when a @verbatim annotation precedes it (which ROS 2's
# generated IDL always has). Confirmed for the primitive-wrapper names
# and "fixed"; kept the full list rather than just the ones seen
# failing so far, since a partial list just means finding the rest one
# crash at a time.
_RESERVED_COLLISION_NAMES = {
    "abstract", "any", "alias", "attribute", "bitfield", "bitmask", "bitset",
    "boolean", "bool", "byte", "case", "char", "component", "connector",
    "const", "consumes", "context", "custom", "default", "double", "exception",
    "emits", "enum", "eventtype", "factory", "false", "finder", "fixed",
    "float", "float32", "float64", "getraises", "home", "import", "in",
    "inout", "interface", "local", "long", "manages", "map", "mirrorport",
    "module", "multiple", "native", "object", "octet", "oneway", "out",
    "primarykey", "private", "port", "porttype", "provides", "public",
    "publishes", "raises", "readonly", "setraises", "sequence", "short",
    "string", "struct", "supports", "switch", "true", "truncatable",
    "typedef", "typeid", "typename", "typeprefix", "unsigned", "union",
    "uses", "valuebase", "valuetype", "void", "wchar", "wstring",
    "int8", "uint8", "int16", "int32", "int64", "uint16", "uint32", "uint64",
    "empty",
}

_INCLUDE_RE = re.compile(r'#include\s*"([^"]+)"')
_CONST_DEF_RE = re.compile(r'(\bconst\s+[\w:]+\s+)(\w+)(\s*=)')
_STRUCT_DEF_RE = re.compile(r'\bstruct\s+(\w+)\s*\{')


def _rename_self_named_fields(content: str) -> str:
    """A field whose name matches its enclosing struct's name
    case-insensitively (sensor_msgs/Temperature's `temperature` field,
    rosgraph_msgs/Clock's `clock` field, ...) hits the same idlc crash
    as the keyword-collision case. ROS 2's generated IDL structs are
    always flat (no nested struct/union bodies), so a simple brace-depth
    scan to find each struct's body is enough — no real IDL parser
    needed.
    """
    out = []
    i = 0
    n = len(content)
    while i < n:
        m = _STRUCT_DEF_RE.search(content, i)
        if not m:
            out.append(content[i:])
            break
        out.append(content[i:m.end()])
        struct_name = m.group(1)

        depth = 1
        j = m.end()
        body_start = j
        while j < n and depth > 0:
            if content[j] == "{":
                depth += 1
            elif content[j] == "}":
                depth -= 1
            j += 1
        body_end = j - 1  # index of the matching '}'
        body = content[body_start:body_end]

        field_re = re.compile(r"\b" + re.escape(struct_name) + r"\b(\s*(?:\[[^\]]*\])?\s*;)", re.IGNORECASE)
        body = field_re.sub(lambda fm: struct_name + "_field" + fm.group(1), body)

        out.append(body)
        out.append(content[body_end])  # the matching '}'
        i = j
    return "".join(out)


def _guard_macro(rel_path: str) -> str:
    return "HANDYROS_IDL_" + re.sub(r"[^A-Za-z0-9]", "_", rel_path).upper()


def _resolve(rel_path: str, include_dirs: list[str]) -> str:
    for d in include_dirs:
        candidate = os.path.join(d, rel_path)
        if os.path.exists(candidate):
            return candidate
    raise FileNotFoundError(f"could not resolve include '{rel_path}' in {include_dirs}")


def _process(rel_path: str, include_dirs: list[str], out_dir: str, visited: set[str], renames: dict[str, str]) -> None:
    if rel_path in visited:
        return
    visited.add(rel_path)

    with open(_resolve(rel_path, include_dirs)) as f:
        content = f.read()

    for included in _INCLUDE_RE.findall(content):
        _process(included, include_dirs, out_dir, visited, renames)

    content = _rename_self_named_fields(content)

    # ROS 2's generated constants (e.g. PointField_Constants::INT8) are
    # never cross-referenced by other declarations in these files, so a
    # bare rename — no manifest tracking needed, unlike struct names —
    # is enough.
    content = _CONST_DEF_RE.sub(
        lambda m: m.group(1) + m.group(2) + "Const" + m.group(3) if m.group(2).lower() in _RESERVED_COLLISION_NAMES else m.group(0),
        content,
    )

    def rename_sub(match: re.Match) -> str:
        name = match.group(1)
        if name.lower() in _RESERVED_COLLISION_NAMES:
            renamed = name + "Msg"
            renames[name] = renamed
            return f"struct {renamed} {{"
        return match.group(0)

    content = _STRUCT_DEF_RE.sub(rename_sub, content)

    macro = _guard_macro(rel_path)
    guarded = f"#ifndef {macro}\n#define {macro}\n{content}\n#endif // {macro}\n"

    out_path = os.path.join(out_dir, rel_path)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        f.write(guarded)


def _root_entries(roots: list[str], renames: dict[str, str]):
    """(ros_type_name, header_rel_path, c_identifier, struct_name) per
    root, accounting for any keyword-collision rename — computed once
    here so the registry and the wire-typename-mangling manifest can't
    drift apart the way hand-duplicating this in CMake risked.
    """
    entries = []
    for root in roots:
        rel = root[:-len(".idl")] if root.endswith(".idl") else root
        pkg_ns = os.path.dirname(rel).replace("/", "_")
        short_name = os.path.basename(rel)
        struct_name = renames.get(short_name, short_name)
        entries.append((rel, f"{rel}.h", f"{pkg_ns}_{struct_name}_desc", struct_name))
    return entries


def _write_typename_patches(roots: list[str], renames: dict[str, str], out_dir: str) -> None:
    """Emits _typename_patches.tsv: rel_idl_path<TAB>plain_typename<TAB>
    mangled_typename per root type. idlc names a generated type after
    the plain IDL module path using whatever struct name actually ended
    up in the (possibly renamed) source — e.g. "std_msgs::msg::Int16Msg"
    — but rmw_cyclonedds publishes ROS 2 topics under a differently
    mangled wire type name using the *original* ROS name, e.g.
    "std_msgs::msg::dds_::Int16_". CMake patches generated .c files
    from the former to the latter post-generation (see MANGLE_ROS_TYPENAME
    in CMakeLists.txt); this manifest is exact instead of CMake needing
    to re-derive the rename.
    """
    lines = []
    for rel, _, _, struct_name in _root_entries(roots, renames):
        pkg_path = os.path.dirname(rel)
        original_name = os.path.basename(rel)  # pre-rename ROS type name — the real wire identity
        plain = (pkg_path + "/" + struct_name).replace("/", "::")
        mangled = (pkg_path + "/dds_/" + original_name + "_").replace("/", "::")
        lines.append(f"{rel}\t{plain}\t{mangled}")
    with open(os.path.join(out_dir, "_typename_patches.tsv"), "w") as f:
        f.write("\n".join(lines) + ("\n" if lines else ""))


def _write_registry(roots: list[str], renames: dict[str, str], out_dir: str) -> None:
    """Emits topic_registry_generated.{h,cpp}: a ROS type name -> typed
    dds_topic_descriptor_t* table for every root type, so
    TopicStatsTracker can create a typed reader for any of them by a
    plain string lookup instead of per-type C++ dispatch code.
    """
    entries = [(rel, header, c_id) for rel, header, c_id, _ in _root_entries(roots, renames)]

    header = (
        "#pragma once\n"
        "#include <map>\n"
        "#include <string>\n"
        "#include <dds/dds.h>\n\n"
        "// Auto-generated by patch_idl.py — do not hand-edit.\n"
        "const std::map<std::string, const dds_topic_descriptor_t*>& handyrosTopicDescriptors();\n"
    )
    with open(os.path.join(out_dir, "topic_registry_generated.h"), "w") as f:
        f.write(header)

    includes = "\n".join(f'#include "{header_rel}"' for _, header_rel, _ in entries)
    table_rows = "\n".join(f'        {{"{ros_type}", &{c_id}}},' for ros_type, _, c_id in entries)
    source = (
        '#include "topic_registry_generated.h"\n\n'
        f"{includes}\n\n"
        "// Auto-generated by patch_idl.py — do not hand-edit.\n"
        "const std::map<std::string, const dds_topic_descriptor_t*>& handyrosTopicDescriptors()\n"
        "{\n"
        "    static const std::map<std::string, const dds_topic_descriptor_t*> table = {\n"
        f"{table_rows}\n"
        "    };\n"
        "    return table;\n"
        "}\n"
    )
    with open(os.path.join(out_dir, "topic_registry_generated.cpp"), "w") as f:
        f.write(source)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--include-dir", action="append", required=True, help="searched in order, like idlc -I")
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--registry-out-dir", help="where to write topic_registry_generated.{h,cpp} (default: --out-dir)")
    parser.add_argument("roots", nargs="+", help="root .idl paths (relative), e.g. sensor_msgs/msg/Imu.idl")
    args = parser.parse_args()

    visited: set[str] = set()
    renames: dict[str, str] = {}
    for root in args.roots:
        try:
            _process(root, args.include_dir, args.out_dir, visited, renames)
        except FileNotFoundError as e:
            print(f"patch_idl.py: {e}", file=sys.stderr)
            return 1

    with open(os.path.join(args.out_dir, "_rename_manifest.tsv"), "w") as f:
        for original, renamed in sorted(renames.items()):
            f.write(f"{original}\t{renamed}\n")

    with open(os.path.join(args.out_dir, "_processed_files.tsv"), "w") as f:
        for path in sorted(visited):
            rel = path[:-len(".idl")] if path.endswith(".idl") else path
            f.write(f"{rel}\n")

    registry_out_dir = args.registry_out_dir or args.out_dir
    _write_registry(args.roots, renames, registry_out_dir)
    _write_typename_patches(args.roots, renames, registry_out_dir)

    return 0


if __name__ == "__main__":
    sys.exit(main())
