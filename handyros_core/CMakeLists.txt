cmake_minimum_required(VERSION 3.16)

project(handyros_core LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Falls back to the ROS 2 Humble apt package's CycloneDDS if the caller
# hasn't already pointed CMAKE_PREFIX_PATH/CycloneDDS_DIR at one (e.g.
# via `source /opt/ros/humble/setup.bash` before configuring).
if(NOT DEFINED CycloneDDS_DIR AND EXISTS "/opt/ros/humble/lib/x86_64-linux-gnu/cmake/CycloneDDS/CycloneDDSConfig.cmake")
    set(CycloneDDS_DIR "/opt/ros/humble/lib/x86_64-linux-gnu/cmake/CycloneDDS")
endif()
find_package(CycloneDDS REQUIRED)
find_package(Threads REQUIRED)

# ---------------------------------------------------------------------------
# Typed bindings for every ROS 2 message type in the standard interface
# packages (std_msgs, sensor_msgs, geometry_msgs, nav_msgs, ...), generated
# at build time by Cyclone's own idlc from the real IDL files ROS 2 ships.
# Reading topics of these types (message rate/size/bandwidth/latency, see
# topic_stats.cpp) needs no custom/unsafe DDS internals — dds_takecdr +
# ddsi_serdata_size on a normal typed reader is fully standard public API.
#
# idlc is a code generator: even when cross-compiling handyros_core for
# Android, it must run on the *build* host, hence NO_CMAKE_FIND_ROOT_PATH.
find_program(HANDYROS_IDLC_EXECUTABLE idlc
    PATHS /opt/ros/humble/bin
    NO_CMAKE_FIND_ROOT_PATH
)
if(NOT HANDYROS_IDLC_EXECUTABLE)
    message(FATAL_ERROR "idlc not found (looked in /opt/ros/humble/bin) - needed to generate ROS 2 message bindings")
endif()

find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(HANDYROS_ROS_IDL_SHARE /opt/ros/humble/share)
set(HANDYROS_IDL_PATCHES ${CMAKE_CURRENT_SOURCE_DIR}/idl_patches)
set(HANDYROS_IDL_GUARDED_DIR ${CMAKE_CURRENT_BINARY_DIR}/idl_guarded)
set(HANDYROS_IDL_GEN_DIR ${CMAKE_CURRENT_BINARY_DIR}/idl_gen)

# Every .msg type in these packages becomes trackable for real stats.
# This is ROS 2's own "common_interfaces" bundle plus the core
# infrastructure packages (rcl_interfaces, tf2_msgs, ...) — effectively
# "every default datatype a stock ROS 2 install offers". A project's
# own custom message packages are never in this list, so those
# correctly stay unsupported until their definition is imported.
set(HANDYROS_IDL_ROOT_PACKAGES
    std_msgs sensor_msgs geometry_msgs nav_msgs actionlib_msgs
    diagnostic_msgs shape_msgs stereo_msgs trajectory_msgs
    visualization_msgs tf2_msgs rcl_interfaces rosgraph_msgs
    action_msgs statistics_msgs builtin_interfaces
)
set(HANDYROS_IDL_ROOTS "")
foreach(pkg ${HANDYROS_IDL_ROOT_PACKAGES})
    file(GLOB _handyros_pkg_idls "${HANDYROS_ROS_IDL_SHARE}/${pkg}/msg/*.idl")
    foreach(f ${_handyros_pkg_idls})
        file(RELATIVE_PATH _handyros_rel ${HANDYROS_ROS_IDL_SHARE} ${f})
        list(APPEND HANDYROS_IDL_ROOTS ${_handyros_rel})
    endforeach()
endforeach()

# tools/patch_idl.py resolves every transitive .idl dependency of the
# roots above (preferring idl_patches/ over the stock ROS 2 files where
# both exist), fixes two confirmed idlc crashes neither we nor ROS 2
# caused (missing include guards; struct/field/const names that
# collide case-insensitively with an IDL keyword), and emits:
#   idl_guarded/<pkg>/msg/<Type>.idl   — patched copies, ready for idlc
#   idl_guarded/_processed_files.tsv   — every file that needs compiling
#   idl_guarded/_typename_patches.tsv  — per-root wire-typename mangling
#   idl_guarded/topic_registry_generated.{h,cpp} — ROS type name -> descriptor
# See the script's own docstring for why each fix is needed.
set(HANDYROS_PATCH_IDL_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/tools/patch_idl.py)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${HANDYROS_PATCH_IDL_SCRIPT})

execute_process(
    COMMAND ${Python3_EXECUTABLE} ${HANDYROS_PATCH_IDL_SCRIPT}
            --include-dir ${HANDYROS_IDL_PATCHES}
            --include-dir ${HANDYROS_ROS_IDL_SHARE}
            --out-dir ${HANDYROS_IDL_GUARDED_DIR}
            ${HANDYROS_IDL_ROOTS}
    RESULT_VARIABLE HANDYROS_PATCH_IDL_RESULT
)
if(NOT HANDYROS_PATCH_IDL_RESULT EQUAL 0)
    message(FATAL_ERROR "tools/patch_idl.py failed (see output above)")
endif()

file(STRINGS ${HANDYROS_IDL_GUARDED_DIR}/_processed_files.tsv HANDYROS_IDL_ALL_FILES)

# Parallel lists standing in for a "file -> (plain typename, mangled
# typename)" map, since CMake has no real associative container.
set(HANDYROS_MANGLE_FILES "")
set(HANDYROS_MANGLE_PLAIN "")
set(HANDYROS_MANGLE_TARGET "")
file(STRINGS ${HANDYROS_IDL_GUARDED_DIR}/_typename_patches.tsv HANDYROS_TYPENAME_LINES)
foreach(_line ${HANDYROS_TYPENAME_LINES})
    string(REPLACE "\t" ";" _parts "${_line}")
    list(GET _parts 0 _f)
    list(GET _parts 1 _plain)
    list(GET _parts 2 _mangled)
    list(APPEND HANDYROS_MANGLE_FILES "${_f}")
    list(APPEND HANDYROS_MANGLE_PLAIN "${_plain}")
    list(APPEND HANDYROS_MANGLE_TARGET "${_mangled}")
endforeach()

function(handyros_add_idl_file rel)
    set(src_idl ${HANDYROS_IDL_GUARDED_DIR}/${rel}.idl)
    set(out_c ${HANDYROS_IDL_GEN_DIR}/${rel}.c)
    set(out_h ${HANDYROS_IDL_GEN_DIR}/${rel}.h)
    get_filename_component(out_dir ${out_c} DIRECTORY)

    set(idlc_command
        ${CMAKE_COMMAND} -E make_directory ${out_dir}
        COMMAND ${HANDYROS_IDLC_EXECUTABLE}
                -I ${HANDYROS_IDL_GUARDED_DIR}
                -b ${HANDYROS_IDL_GUARDED_DIR} -o ${HANDYROS_IDL_GEN_DIR} -l c
                ${src_idl}
    )

    list(FIND HANDYROS_MANGLE_FILES "${rel}" _idx)
    if(NOT _idx EQUAL -1)
        list(GET HANDYROS_MANGLE_PLAIN ${_idx} _plain)
        list(GET HANDYROS_MANGLE_TARGET ${_idx} _mangled)
        # DDS requires an exact type-name string match for a reader to
        # connect to a writer; idlc has no flag to control the name it
        # generates, so patch it in post-generation (see patch_idl.py).
        list(APPEND idlc_command COMMAND sed -i "s@\"${_plain}\"@\"${_mangled}\"@" ${out_c})
    endif()

    add_custom_command(
        OUTPUT ${out_c} ${out_h}
        COMMAND ${idlc_command}
        DEPENDS ${src_idl}
        COMMENT "idlc: ${rel}"
        VERBATIM
    )
    set(HANDYROS_IDL_GENERATED_SOURCES ${HANDYROS_IDL_GENERATED_SOURCES} ${out_c} PARENT_SCOPE)
endfunction()

foreach(_rel ${HANDYROS_IDL_ALL_FILES})
    handyros_add_idl_file(${_rel})
endforeach()

add_library(handyros_core SHARED
        src/handyros.cpp
        src/dds_manager.cpp
        src/topic_stats.cpp
        src/topic_payload.cpp
        src/topic_publisher.cpp
        ${HANDYROS_IDL_GUARDED_DIR}/topic_registry_generated.cpp
        ${HANDYROS_IDL_GENERATED_SOURCES}
)

target_include_directories(handyros_core
        PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        PRIVATE
        ${HANDYROS_IDL_GEN_DIR}
        ${HANDYROS_IDL_GUARDED_DIR}
)

target_link_libraries(handyros_core
        CycloneDDS::ddsc
        Threads::Threads
)

# The standalone smoke-test binary isn't useful on Android (nothing to
# run it with there) and pulls in extra link surface we don't need in
# the on-device build.
if(NOT ANDROID)
    add_executable(test_handyros test.cpp)
    target_link_libraries(test_handyros handyros_core)
endif()
