#include "topic_payload.h"

#include <atomic>
#include <chrono>
#include <cstring>
#include <functional>
#include <map>
#include <mutex>
#include <thread>

#include "json_util.h"
#include "topic_registry_generated.h"

#include "nav_msgs/msg/Odometry.h"
#include "rcl_interfaces/msg/Log.h"
#include "sensor_msgs/msg/Image.h"
#include "sensor_msgs/msg/Imu.h"
#include "sensor_msgs/msg/LaserScan.h"
#include "sensor_msgs/msg/PointCloud2.h"
#include "std_msgs/msg/Float32.h"
#include "std_msgs/msg/Float64.h"
#include "std_msgs/msg/String.h"
#include "tf2_msgs/msg/TFMessage.h"

namespace
{
using DecodeFn = std::function<void(const void* sample, std::string& json, std::vector<uint8_t>& blob)>;

std::string safeStr(const char* s)
{
    return s != nullptr ? std::string(s) : std::string();
}

// ROS 2 mangles topic names with an "rt/" prefix at the DDS layer —
// same convention as TopicStatsTracker's mangleTopicName.
std::string mangleTopicName(const std::string& topicName)
{
    return "rt" + topicName;
}

void decodeImu(const void* sample, std::string& json, std::vector<uint8_t>&)
{
    const auto* m = static_cast<const sensor_msgs_msg_Imu*>(sample);
    json = "{\"available\":true,\"kind\":\"imu\","
           "\"frameId\":\"" +
           json_util::escape(safeStr(m->header.frame_id)) + "\","
           "\"orientation\":{\"x\":" +
           json_util::number(m->orientation.x) + ",\"y\":" + json_util::number(m->orientation.y) +
           ",\"z\":" + json_util::number(m->orientation.z) + ",\"w\":" + json_util::number(m->orientation.w) + "},"
           "\"angularVelocity\":{\"x\":" +
           json_util::number(m->angular_velocity.x) + ",\"y\":" + json_util::number(m->angular_velocity.y) +
           ",\"z\":" + json_util::number(m->angular_velocity.z) + "},"
           "\"linearAcceleration\":{\"x\":" +
           json_util::number(m->linear_acceleration.x) + ",\"y\":" + json_util::number(m->linear_acceleration.y) +
           ",\"z\":" + json_util::number(m->linear_acceleration.z) + "}}";
}

void decodeImage(const void* sample, std::string& json, std::vector<uint8_t>& blob)
{
    const auto* m = static_cast<const sensor_msgs_msg_Image*>(sample);
    json = "{\"available\":true,\"kind\":\"image\","
           "\"frameId\":\"" +
           json_util::escape(safeStr(m->header.frame_id)) + "\","
           "\"width\":" +
           std::to_string(m->width) + ",\"height\":" + std::to_string(m->height) +
           ",\"step\":" + std::to_string(m->step) + ",\"encoding\":\"" + json_util::escape(safeStr(m->encoding)) +
           "\",\"isBigEndian\":" + (m->is_bigendian != 0 ? "true" : "false") + "}";
    if (m->data._buffer != nullptr && m->data._length > 0)
    {
        blob.assign(m->data._buffer, m->data._buffer + m->data._length);
    }
    else
    {
        blob.clear();
    }
}

void decodeLaserScan(const void* sample, std::string& json, std::vector<uint8_t>&)
{
    const auto* m = static_cast<const sensor_msgs_msg_LaserScan*>(sample);
    std::string ranges = "[";
    for (uint32_t i = 0; i < m->ranges._length; ++i)
    {
        if (i > 0)
        {
            ranges += ",";
        }
        ranges += json_util::number(m->ranges._buffer[i]);
    }
    ranges += "]";
    json = "{\"available\":true,\"kind\":\"laserScan\","
           "\"frameId\":\"" +
           json_util::escape(safeStr(m->header.frame_id)) + "\","
           "\"angleMin\":" +
           json_util::number(m->angle_min) + ",\"angleMax\":" + json_util::number(m->angle_max) +
           ",\"angleIncrement\":" + json_util::number(m->angle_increment) + ",\"rangeMin\":" +
           json_util::number(m->range_min) + ",\"rangeMax\":" + json_util::number(m->range_max) +
           ",\"ranges\":" + ranges + "}";
}

// Every ROS PointField numeric datatype (see sensor_msgs/msg/PointField's
// INT8..FLOAT64 constants) read via memcpy rather than a reinterpret_cast
// dereference — offsets inside a packed point aren't guaranteed aligned
// for their type, and an unaligned load can trap on some ARM configs.
double readPointFieldNumeric(const uint8_t* base, uint8_t datatype)
{
    switch (datatype)
    {
        case 1:
        {
            int8_t v;
            std::memcpy(&v, base, sizeof(v));
            return v;
        }
        case 2:
        {
            uint8_t v;
            std::memcpy(&v, base, sizeof(v));
            return v;
        }
        case 3:
        {
            int16_t v;
            std::memcpy(&v, base, sizeof(v));
            return v;
        }
        case 4:
        {
            uint16_t v;
            std::memcpy(&v, base, sizeof(v));
            return v;
        }
        case 5:
        {
            int32_t v;
            std::memcpy(&v, base, sizeof(v));
            return v;
        }
        case 6:
        {
            uint32_t v;
            std::memcpy(&v, base, sizeof(v));
            return v;
        }
        case 7:
        {
            float v;
            std::memcpy(&v, base, sizeof(v));
            return v;
        }
        case 8:
        {
            double v;
            std::memcpy(&v, base, sizeof(v));
            return v;
        }
        default:
            return 0.0;
    }
}

uint32_t pointFieldDatatypeSize(uint8_t datatype)
{
    switch (datatype)
    {
        case 1:
        case 2:
            return 1;
        case 3:
        case 4:
            return 2;
        case 5:
        case 6:
        case 7:
            return 4;
        case 8:
            return 8;
        default:
            return 0;
    }
}

// Pre-extracts [x,y,z,colorBits] float32 tuples so the Dart side never
// has to re-parse PointField offsets/datatypes itself — robust to
// organized/unorganized clouds and different field layouts (XYZI vs
// XYZRGB) since that's all resolved here, once, using the standard
// ROS field-naming convention ("x"/"y"/"z"/"rgb"/"rgba").
void decodePointCloud2(const void* sample, std::string& json, std::vector<uint8_t>& blob)
{
    const auto* m = static_cast<const sensor_msgs_msg_PointCloud2*>(sample);

    const sensor_msgs_msg_PointField* xField = nullptr;
    const sensor_msgs_msg_PointField* yField = nullptr;
    const sensor_msgs_msg_PointField* zField = nullptr;
    const sensor_msgs_msg_PointField* colorField = nullptr;
    for (uint32_t i = 0; i < m->fields._length; ++i)
    {
        const auto& f = m->fields._buffer[i];
        const std::string name = safeStr(f.name);
        if (name == "x")
        {
            xField = &f;
        }
        else if (name == "y")
        {
            yField = &f;
        }
        else if (name == "z")
        {
            zField = &f;
        }
        else if ((name == "rgb" || name == "rgba") && colorField == nullptr)
        {
            colorField = &f;
        }
    }

    auto fieldFits = [&](const sensor_msgs_msg_PointField* f, uint32_t size) {
        return f != nullptr && m->point_step > 0 && static_cast<uint64_t>(f->offset) + size <= m->point_step;
    };
    if (!fieldFits(xField, pointFieldDatatypeSize(xField != nullptr ? xField->datatype : 0)) ||
        !fieldFits(yField, pointFieldDatatypeSize(yField != nullptr ? yField->datatype : 0)) ||
        !fieldFits(zField, pointFieldDatatypeSize(zField != nullptr ? zField->datatype : 0)))
    {
        xField = yField = zField = nullptr;
    }
    if (!fieldFits(colorField, 4))
    {
        colorField = nullptr;
    }

    uint32_t pointCount = m->width * m->height;
    if (m->point_step > 0)
    {
        const uint64_t maxPoints = static_cast<uint64_t>(m->data._length) / m->point_step;
        if (maxPoints < pointCount)
        {
            pointCount = static_cast<uint32_t>(maxPoints);
        }
    }
    else
    {
        pointCount = 0;
    }
    if (xField == nullptr || m->data._buffer == nullptr)
    {
        pointCount = 0;
    }

    const char* colorMode = colorField != nullptr ? "rgb" : "none";
    json = "{\"available\":true,\"kind\":\"pointCloud\","
           "\"frameId\":\"" +
           json_util::escape(safeStr(m->header.frame_id)) + "\","
           "\"width\":" +
           std::to_string(m->width) + ",\"height\":" + std::to_string(m->height) + ",\"pointCount\":" +
           std::to_string(pointCount) + ",\"colorMode\":\"" + colorMode + "\"}";

    if (pointCount == 0)
    {
        blob.clear();
        return;
    }

    blob.resize(static_cast<size_t>(pointCount) * 4 * sizeof(float));
    auto* out = reinterpret_cast<float*>(blob.data());
    constexpr uint32_t kNanBits = 0x7fc00000u;
    float nanColor;
    std::memcpy(&nanColor, &kNanBits, sizeof(nanColor));

    for (uint32_t i = 0; i < pointCount; ++i)
    {
        const uint8_t* base = m->data._buffer + static_cast<size_t>(i) * m->point_step;
        out[i * 4 + 0] = static_cast<float>(readPointFieldNumeric(base + xField->offset, xField->datatype));
        out[i * 4 + 1] = static_cast<float>(readPointFieldNumeric(base + yField->offset, yField->datatype));
        out[i * 4 + 2] = static_cast<float>(readPointFieldNumeric(base + zField->offset, zField->datatype));
        if (colorField != nullptr)
        {
            // Raw 4-byte passthrough (not a numeric conversion): packed
            // RGB is just bytes to us, however the field's declared
            // datatype claims to interpret them — Dart bit-reinterprets
            // the same 4 bytes back into R/G/B.
            std::memcpy(&out[i * 4 + 3], base + colorField->offset, sizeof(float));
        }
        else
        {
            out[i * 4 + 3] = nanColor;
        }
    }
}

void decodeOdometry(const void* sample, std::string& json, std::vector<uint8_t>&)
{
    const auto* m = static_cast<const nav_msgs_msg_Odometry*>(sample);
    const auto& pos = m->pose.pose.position;
    const auto& ori = m->pose.pose.orientation;
    const auto& lin = m->twist.twist.linear;
    const auto& ang = m->twist.twist.angular;
    json = "{\"available\":true,\"kind\":\"odometry\","
           "\"frameId\":\"" +
           json_util::escape(safeStr(m->header.frame_id)) + "\",\"childFrameId\":\"" +
           json_util::escape(safeStr(m->child_frame_id)) + "\","
           "\"position\":{\"x\":" +
           json_util::number(pos.x) + ",\"y\":" + json_util::number(pos.y) + ",\"z\":" + json_util::number(pos.z) +
           "},\"orientation\":{\"x\":" + json_util::number(ori.x) + ",\"y\":" + json_util::number(ori.y) +
           ",\"z\":" + json_util::number(ori.z) + ",\"w\":" + json_util::number(ori.w) +
           "},\"linearVelocity\":{\"x\":" + json_util::number(lin.x) + ",\"y\":" + json_util::number(lin.y) +
           ",\"z\":" + json_util::number(lin.z) + "},\"angularVelocity\":{\"x\":" + json_util::number(ang.x) +
           ",\"y\":" + json_util::number(ang.y) + ",\"z\":" + json_util::number(ang.z) + "}}";
}

void decodeTf(const void* sample, std::string& json, std::vector<uint8_t>&)
{
    const auto* m = static_cast<const tf2_msgs_msg_TFMessage*>(sample);
    std::string transforms = "[";
    for (uint32_t i = 0; i < m->transforms._length; ++i)
    {
        const auto& t = m->transforms._buffer[i];
        if (i > 0)
        {
            transforms += ",";
        }
        transforms += "{\"parent\":\"" + json_util::escape(safeStr(t.header.frame_id)) + "\",\"child\":\"" +
                      json_util::escape(safeStr(t.child_frame_id)) + "\","
                      "\"translation\":{\"x\":" +
                      json_util::number(t.transform.translation.x) + ",\"y\":" +
                      json_util::number(t.transform.translation.y) + ",\"z\":" +
                      json_util::number(t.transform.translation.z) + "},\"rotation\":{\"x\":" +
                      json_util::number(t.transform.rotation.x) + ",\"y\":" +
                      json_util::number(t.transform.rotation.y) + ",\"z\":" + json_util::number(t.transform.rotation.z) +
                      ",\"w\":" + json_util::number(t.transform.rotation.w) + "}}";
    }
    transforms += "]";
    json = "{\"available\":true,\"kind\":\"tf\",\"transforms\":" + transforms + "}";
}

void decodeString(const void* sample, std::string& json, std::vector<uint8_t>&)
{
    const auto* m = static_cast<const std_msgs_msg_StringMsg*>(sample);
    json = "{\"available\":true,\"kind\":\"string\",\"text\":\"" + json_util::escape(safeStr(m->data)) + "\"}";
}

void decodeLog(const void* sample, std::string& json, std::vector<uint8_t>&)
{
    const auto* m = static_cast<const rcl_interfaces_msg_Log*>(sample);
    json = "{\"available\":true,\"kind\":\"log\",\"level\":" + std::to_string(static_cast<int>(m->level)) +
           ",\"name\":\"" + json_util::escape(safeStr(m->name)) + "\",\"text\":\"" +
           json_util::escape(safeStr(m->msg)) + "\"}";
}

void decodeFloat32(const void* sample, std::string& json, std::vector<uint8_t>&)
{
    const auto* m = static_cast<const std_msgs_msg_Float32Msg*>(sample);
    json = "{\"available\":true,\"kind\":\"float\",\"value\":" + json_util::number(m->data) + "}";
}

void decodeFloat64(const void* sample, std::string& json, std::vector<uint8_t>&)
{
    const auto* m = static_cast<const std_msgs_msg_Float64Msg*>(sample);
    json = "{\"available\":true,\"kind\":\"float\",\"value\":" + json_util::number(m->data) + "}";
}

const std::map<std::string, DecodeFn>& decoderTable()
{
    static const std::map<std::string, DecodeFn> table = {
        {"sensor_msgs/msg/Imu", decodeImu},
        {"sensor_msgs/msg/Image", decodeImage},
        {"sensor_msgs/msg/LaserScan", decodeLaserScan},
        {"sensor_msgs/msg/PointCloud2", decodePointCloud2},
        {"nav_msgs/msg/Odometry", decodeOdometry},
        {"tf2_msgs/msg/TFMessage", decodeTf},
        {"std_msgs/msg/String", decodeString},
        {"rcl_interfaces/msg/Log", decodeLog},
        {"std_msgs/msg/Float32", decodeFloat32},
        {"std_msgs/msg/Float64", decodeFloat64},
    };
    return table;
}

struct TrackedReader
{
    dds_entity_t topic = 0;
    dds_entity_t reader = 0;
    DecodeFn decode;
    std::string latestJson;
    std::vector<uint8_t> latestBlob;
    bool hasSample = false;
};

constexpr uint32_t kMaxSamplesPerPoll = 4;

void drainOne(TrackedReader& tracked)
{
    void* samples[kMaxSamplesPerPoll] = {};
    dds_sample_info_t infos[kMaxSamplesPerPoll];
    for (;;)
    {
        dds_return_t n = dds_take(tracked.reader, samples, infos, kMaxSamplesPerPoll, kMaxSamplesPerPoll);
        if (n <= 0)
        {
            break;
        }
        for (dds_return_t i = 0; i < n; ++i)
        {
            if (infos[i].valid_data)
            {
                tracked.decode(samples[i], tracked.latestJson, tracked.latestBlob);
                tracked.hasSample = true;
            }
        }
        dds_return_loan(tracked.reader, samples, n);
    }
}
}  // namespace

struct TopicPayloadTracker::Impl
{
    mutable std::mutex mutex;
    std::map<std::string, TrackedReader> readers;

    // Same rationale as TopicStatsTracker's background thread: draining
    // needs to keep up with the publish rate independent of however
    // often/rarely the UI happens to poll, or KEEP_LAST silently drops
    // samples we never got around to reading.
    std::atomic<bool> stop{false};
    std::thread worker;

    Impl() : worker([this] { run(); }) {}

    ~Impl()
    {
        stop.store(true, std::memory_order_relaxed);
        if (worker.joinable())
        {
            worker.join();
        }
    }

    void run()
    {
        while (!stop.load(std::memory_order_relaxed))
        {
            {
                std::lock_guard<std::mutex> lock(mutex);
                for (auto& [name, tracked] : readers)
                {
                    drainOne(tracked);
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(30));
        }
    }
};

TopicPayloadTracker::TopicPayloadTracker() : impl_(std::make_unique<Impl>()) {}
TopicPayloadTracker::~TopicPayloadTracker() = default;

bool TopicPayloadTracker::watch(dds_entity_t participant, const std::string& topicName, const std::string& rosType, bool reliable)
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (impl_->readers.count(topicName) > 0)
    {
        return true;
    }

    const auto& decoders = decoderTable();
    auto decodeIt = decoders.find(rosType);
    if (decodeIt == decoders.end())
    {
        return false;
    }

    const auto& registry = handyrosTopicDescriptors();
    auto descIt = registry.find(rosType);
    if (descIt == registry.end())
    {
        return false;
    }

    // Plain default QoS for the topic entity itself — *not* the
    // reliability/history below. TopicStatsTracker may independently
    // want a topic entity for this same name (a Viewer screen watches
    // both stats and decoded payload at once), and Cyclone rejects a
    // second dds_create_topic() on an existing name when its QoS
    // doesn't match the first caller's ("Inconsistent Policy"). The
    // two trackers must therefore agree on topic-level QoS; the actual
    // reliability/history we want is set on the *reader* below, which
    // always takes precedence over the topic's default for that reader.
    dds_qos_t* topicQos = dds_create_qos();
    dds_entity_t topic = dds_create_topic(participant, descIt->second, mangleTopicName(topicName).c_str(), topicQos, nullptr);
    dds_delete_qos(topicQos);
    if (topic < 0)
    {
        return false;
    }

    dds_qos_t* readerQos = dds_create_qos();
    if (reliable)
    {
        dds_qset_reliability(readerQos, DDS_RELIABILITY_RELIABLE, DDS_SECS(1));
    }
    else
    {
        dds_qset_reliability(readerQos, DDS_RELIABILITY_BEST_EFFORT, 0);
    }
    // Only the latest sample ever matters here — no rate averaging
    // like TopicStatsTracker, so there's no reason to buffer more.
    dds_qset_history(readerQos, DDS_HISTORY_KEEP_LAST, 2);

    TrackedReader tracked;
    tracked.decode = decodeIt->second;
    tracked.topic = topic;
    tracked.reader = dds_create_reader(participant, tracked.topic, readerQos, nullptr);
    dds_delete_qos(readerQos);
    if (tracked.reader < 0)
    {
        dds_delete(tracked.topic);
        return false;
    }

    impl_->readers[topicName] = std::move(tracked);
    return true;
}

void TopicPayloadTracker::unwatch(const std::string& topicName)
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    auto it = impl_->readers.find(topicName);
    if (it == impl_->readers.end())
    {
        return;
    }
    dds_delete(it->second.reader);
    dds_delete(it->second.topic);
    impl_->readers.erase(it);
}

std::string TopicPayloadTracker::latestJson(const std::string& topicName) const
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    auto it = impl_->readers.find(topicName);
    if (it == impl_->readers.end())
    {
        return "{\"available\":false,\"supported\":false}";
    }
    if (!it->second.hasSample)
    {
        return "{\"available\":false,\"supported\":true}";
    }
    return it->second.latestJson;
}

std::vector<uint8_t> TopicPayloadTracker::latestBlob(const std::string& topicName) const
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    auto it = impl_->readers.find(topicName);
    if (it == impl_->readers.end() || !it->second.hasSample)
    {
        return {};
    }
    return it->second.latestBlob;
}

void TopicPayloadTracker::clear()
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->readers.clear();
}
