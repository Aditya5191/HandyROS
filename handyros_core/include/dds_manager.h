#pragma once
#include <cstdint>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <vector>

#include <dds/dds.h>

#include "topic_payload.h"
#include "topic_publisher.h"
#include "topic_stats.h"

// Tracks live ROS 2 topics by subscribing to Cyclone DDS's builtin
// DcpsParticipant/DcpsPublication/DcpsSubscription topics — the same
// discovery data `ros2 topic list`/`ros2 node list` read. No user
// message types need to be known ahead of time; this only sees topic
// name, type name, QoS, and which processes/hosts are publishing or
// subscribing.
class DDSManager
{
public:
    DDSManager();
    ~DDSManager();

    // peerAddressesCsv: comma-separated host IPs to reach via unicast
    // discovery, in addition to the usual multicast (SPDP). Needed on
    // networks that don't forward multicast between Wi-Fi clients
    // (common on phone hotspots and plenty of consumer routers).
    bool initialize(uint32_t domain_id = 0, const std::string& peerAddressesCsv = "");
    void shutdown();

    // Pumps any pending discovery samples into the internal registry.
    // Call periodically (e.g. from a poll timer).
    void poll();

    // Starts/stops measuring real rate/size/bandwidth/latency for one
    // topic (see TopicStatsTracker). Deliberately *not* automatic for
    // every discovered topic — some are camera/point-cloud streams at
    // tens of MB/s, and subscribing to all of them just to report a
    // number nobody's looking at is real bandwidth/memory/battery cost
    // on a phone. Call when a topic's detail view opens/closes.
    void watchTopic(const std::string& topicName);
    void unwatchTopic(const std::string& topicName);

    // Starts/stops decoding real message field values for one topic
    // (see TopicPayloadTracker) — only meaningful for the fixed set of
    // types with a dedicated Viewer screen. Call when a Viewer screen
    // for that topic opens/closes; independent of watchTopic/
    // unwatchTopic (a topic's stats and its decoded payload have
    // different callers/lifetimes — the topic list card wants the
    // former, an open Viewer screen wants both).
    void watchPayload(const std::string& topicName);
    void unwatchPayload(const std::string& topicName);

    // Decoded fields as JSON — see TopicPayloadTracker::latestJson for
    // the exact shape/availability semantics.
    std::string topicPayloadJson(const std::string& topicName);

    // Paired binary blob for the latest decoded sample (image pixels /
    // pre-extracted point cloud coordinates), empty if the type has
    // none or no sample has arrived yet.
    std::vector<uint8_t> topicPayloadBlob(const std::string& topicName);

    // JSON snapshot of currently known topics:
    // [{"name":"/scan","type":"sensor_msgs/msg/LaserScan",
    //   "reliability":"reliable","durability":"volatile","history":"keep_last","depth":5,
    //   "publishers":[{"process":"lidar_driver","host":"tb4"}],"subscribers":[...]}]
    std::string topicsJson();

    // Writer-side: publish on a fixed, known message type (see
    // TopicPublisher). Unlike watchTopic/watchPayload, these don't
    // require the topic to already be discovered — the app itself is
    // the publisher, so the topic may not exist on the graph yet.
    // No-ops if the participant isn't initialized.
    void publishTwist(const std::string& topicName, double linearX, double linearY, double linearZ, double angularX,
                       double angularY, double angularZ);
    void publishImu(const std::string& topicName, const std::string& frameId, double accelX, double accelY,
                     double accelZ, double gyroX, double gyroY, double gyroZ, double orientX, double orientY,
                     double orientZ, double orientW);
    void publishNavSatFix(const std::string& topicName, const std::string& frameId, double latitude,
                           double longitude, double altitude);
    void publishMagneticField(const std::string& topicName, const std::string& frameId, double x, double y, double z);
    void publishImage(const std::string& topicName, const std::string& frameId, uint32_t width, uint32_t height,
                       const std::string& encoding, bool isBigEndian, uint32_t step, const uint8_t* data,
                       size_t dataLen);
    void stopPublishing(const std::string& topicName);

private:
    struct EndpointKey
    {
        unsigned char bytes[16];
        bool operator<(const EndpointKey& other) const;
        bool operator==(const EndpointKey& other) const;
    };

    struct NodeIdentity
    {
        std::string process_name;
        std::string hostname;
    };

    struct TopicInfo
    {
        std::string type_name;
        // endpoint guid -> owning participant's guid, resolved against
        // participants_ at JSON-serialization time (so renames/late
        // participant discovery are always reflected).
        std::map<EndpointKey, EndpointKey> publishers;
        std::map<EndpointKey, EndpointKey> subscribers;

        // QoS as last observed on any one endpoint of this topic. Real
        // per-endpoint QoS can differ (e.g. a best-effort publisher and
        // a reliable subscriber won't actually match), but the common
        // case — and all our own UI shows — is one profile per topic.
        std::string reliability = "unknown";
        std::string durability = "unknown";
        std::string history = "unknown";
        int32_t depth = 0;
    };

    void drainEndpoints(dds_entity_t reader, bool is_publication);
    void drainParticipants();
    void removeEndpoint(const EndpointKey& key);
    NodeIdentity resolveNode(const EndpointKey& participantKey) const;

    dds_entity_t participant_;
    dds_entity_t pub_reader_;
    dds_entity_t sub_reader_;
    dds_entity_t participant_reader_;
    // Our own participant's GUID — endpoints owned by it (e.g. the
    // typed readers TopicStatsTracker creates to measure real message
    // rate/size) are filtered out of publishers_/subscribers_ so the
    // app never counts itself as "real" presence on a topic. Without
    // this, a topic instrumented for stats would look permanently
    // alive even after every actual external peer disappears.
    EndpointKey ownParticipantKey_{};

    std::mutex mutex_;
    std::map<std::string, TopicInfo> topics_;
    std::map<EndpointKey, std::pair<std::string, bool>> endpointIndex_;  // endpoint guid -> (topic name, is_publication)
    std::map<EndpointKey, NodeIdentity> participants_;                   // participant guid -> identity
    TopicStatsTracker statsTracker_;
    TopicPayloadTracker payloadTracker_;
    TopicPublisher publisher_;
};
