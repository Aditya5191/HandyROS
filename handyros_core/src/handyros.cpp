#include "handyros.h"
#include "dds_manager.h"

#include <cstdlib>
#include <cstring>
#include <vector>

// Static instance: only visible inside handyros.cpp
static DDSManager g_dds_manager;

bool handyros_initialize(uint32_t domain_id, const char* peers_csv)
{
    return g_dds_manager.initialize(domain_id, peers_csv != nullptr ? peers_csv : "");
}

void handyros_shutdown(void)
{
    g_dds_manager.shutdown();
}

void handyros_poll(void)
{
    g_dds_manager.poll();
}

void handyros_watch_topic(const char* topic_name)
{
    if (topic_name != nullptr)
    {
        g_dds_manager.watchTopic(topic_name);
    }
}

void handyros_unwatch_topic(const char* topic_name)
{
    if (topic_name != nullptr)
    {
        g_dds_manager.unwatchTopic(topic_name);
    }
}

void handyros_watch_payload(const char* topic_name)
{
    if (topic_name != nullptr)
    {
        g_dds_manager.watchPayload(topic_name);
    }
}

void handyros_unwatch_payload(const char* topic_name)
{
    if (topic_name != nullptr)
    {
        g_dds_manager.unwatchPayload(topic_name);
    }
}

const char* handyros_topic_payload_json(const char* topic_name)
{
    const std::string json = topic_name != nullptr ? g_dds_manager.topicPayloadJson(topic_name) : "{\"available\":false,\"supported\":false}";
    char* out = static_cast<char*>(std::malloc(json.size() + 1));
    if (out == nullptr)
    {
        return nullptr;
    }
    std::memcpy(out, json.c_str(), json.size() + 1);
    return out;
}

const uint8_t* handyros_topic_payload_blob(const char* topic_name, size_t* out_len)
{
    const std::vector<uint8_t> blob = topic_name != nullptr ? g_dds_manager.topicPayloadBlob(topic_name) : std::vector<uint8_t>();
    if (out_len != nullptr)
    {
        *out_len = blob.size();
    }
    if (blob.empty())
    {
        return nullptr;
    }
    auto* out = static_cast<uint8_t*>(std::malloc(blob.size()));
    if (out == nullptr)
    {
        if (out_len != nullptr)
        {
            *out_len = 0;
        }
        return nullptr;
    }
    std::memcpy(out, blob.data(), blob.size());
    return out;
}

void handyros_free_blob(const uint8_t* ptr)
{
    std::free(const_cast<uint8_t*>(ptr));
}

const char* handyros_topics_json(void)
{
    const std::string json = g_dds_manager.topicsJson();
    char* out = static_cast<char*>(std::malloc(json.size() + 1));
    if (out == nullptr)
    {
        return nullptr;
    }
    std::memcpy(out, json.c_str(), json.size() + 1);
    return out;
}

void handyros_free_string(const char* s)
{
    std::free(const_cast<char*>(s));
}

void handyros_publish_twist(const char* topic_name, double linear_x, double linear_y, double linear_z,
                             double angular_x, double angular_y, double angular_z)
{
    if (topic_name != nullptr)
    {
        g_dds_manager.publishTwist(topic_name, linear_x, linear_y, linear_z, angular_x, angular_y, angular_z);
    }
}

void handyros_publish_imu(const char* topic_name, const char* frame_id, double accel_x, double accel_y,
                           double accel_z, double gyro_x, double gyro_y, double gyro_z, double orient_x,
                           double orient_y, double orient_z, double orient_w)
{
    if (topic_name != nullptr)
    {
        g_dds_manager.publishImu(topic_name, frame_id != nullptr ? frame_id : "", accel_x, accel_y, accel_z, gyro_x,
                                  gyro_y, gyro_z, orient_x, orient_y, orient_z, orient_w);
    }
}

void handyros_publish_nav_sat_fix(const char* topic_name, const char* frame_id, double latitude, double longitude,
                                   double altitude)
{
    if (topic_name != nullptr)
    {
        g_dds_manager.publishNavSatFix(topic_name, frame_id != nullptr ? frame_id : "", latitude, longitude, altitude);
    }
}

void handyros_publish_magnetic_field(const char* topic_name, const char* frame_id, double x, double y, double z)
{
    if (topic_name != nullptr)
    {
        g_dds_manager.publishMagneticField(topic_name, frame_id != nullptr ? frame_id : "", x, y, z);
    }
}

void handyros_publish_image(const char* topic_name, const char* frame_id, uint32_t width, uint32_t height,
                             const char* encoding, bool is_bigendian, uint32_t step, const uint8_t* data,
                             size_t data_len)
{
    if (topic_name != nullptr)
    {
        g_dds_manager.publishImage(topic_name, frame_id != nullptr ? frame_id : "", width, height,
                                    encoding != nullptr ? encoding : "", is_bigendian, step, data, data_len);
    }
}

void handyros_publish_stop(const char* topic_name)
{
    if (topic_name != nullptr)
    {
        g_dds_manager.stopPublishing(topic_name);
    }
}
