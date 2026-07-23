#pragma once
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

#include <dds/dds.h>

// Writer-side counterpart to TopicStatsTracker/TopicPayloadTracker —
// publishes on a fixed, known set of message types (the ones the
// Sensors/Teleop UI can produce) rather than anything generic. A
// writer is created lazily on the first publish call for a given
// topic name and reused after that; the topic name determines which
// writer is reused, so a given name should only ever be used with one
// of the publish* kinds below.
class TopicPublisher
{
public:
    TopicPublisher();
    ~TopicPublisher();

    void publishTwist(dds_entity_t participant, const std::string& topicName, double linearX, double linearY,
                       double linearZ, double angularX, double angularY, double angularZ);

    void publishImu(dds_entity_t participant, const std::string& topicName, const std::string& frameId,
                     double accelX, double accelY, double accelZ, double gyroX, double gyroY, double gyroZ,
                     double orientX, double orientY, double orientZ, double orientW);

    void publishNavSatFix(dds_entity_t participant, const std::string& topicName, const std::string& frameId,
                           double latitude, double longitude, double altitude);

    void publishMagneticField(dds_entity_t participant, const std::string& topicName, const std::string& frameId,
                               double x, double y, double z);

    void publishImage(dds_entity_t participant, const std::string& topicName, const std::string& frameId,
                       uint32_t width, uint32_t height, const std::string& encoding, bool isBigEndian,
                       uint32_t step, const uint8_t* data, size_t dataLen);

    // Deletes the cached writer (and its topic entity) for topicName,
    // whichever publish* kind created it.
    void stopPublishing(const std::string& topicName);

    // Drops every cached writer (does not itself delete DDS entities —
    // call after the owning participant has been/is being deleted),
    // mirrors TopicStatsTracker::clear()/TopicPayloadTracker::clear().
    void clear();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
