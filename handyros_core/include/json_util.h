#pragma once
#include <cmath>
#include <sstream>
#include <string>

// Tiny hand-rolled JSON string building — shared by dds_manager.cpp
// (topic metadata) and topic_payload.cpp (decoded message fields), so
// the escaping/number-formatting rules can't drift apart between them.
namespace json_util
{
inline std::string escape(const std::string& in)
{
    std::string out;
    out.reserve(in.size());
    for (char c : in)
    {
        if (c == '"' || c == '\\')
        {
            out += '\\';
        }
        if (static_cast<unsigned char>(c) < 0x20)
        {
            continue;
        }
        out += c;
    }
    return out;
}

// std::to_string on floating point uses a fixed 6 decimals and can
// print "-nan"/"inf" for non-finite values, which isn't valid JSON —
// guard against that since decoded sensor fields can legitimately be
// NaN/Inf (e.g. an invalid LaserScan range).
inline std::string number(double v)
{
    if (!std::isfinite(v))
    {
        return "0";
    }
    std::ostringstream oss;
    oss << v;
    return oss.str();
}
}  // namespace json_util
