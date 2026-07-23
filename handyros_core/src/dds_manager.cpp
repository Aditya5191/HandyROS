#include "dds_manager.h"

#include <cstring>
#include <optional>

#include "json_util.h"

namespace
{
constexpr uint32_t kMaxSamplesPerTake = 32;

// ROS 2 mangles names at the DDS layer: topics get an "rt/" prefix,
// service request/reply get "rq/"/"rr/", plus an internal graph-cache
// topic. Only "rt/" entries are user-facing topics; strip the prefix
// back to the ROS 2 topic name (e.g. "rt/chatter" -> "/chatter").
std::optional<std::string> demangleTopicName(const std::string& ddsName)
{
    constexpr char kTopicPrefix[] = "rt/";
    if (ddsName.rfind(kTopicPrefix, 0) != 0)
    {
        return std::nullopt;
    }
    return "/" + ddsName.substr(std::strlen(kTopicPrefix));
}

// e.g. "std_msgs::msg::dds_::String_" -> "std_msgs/msg/String"
std::string demangleTypeName(const std::string& ddsType)
{
    constexpr char kDdsNamespaceMarker[] = "::dds_::";
    std::string mangled = ddsType;
    if (auto pos = mangled.find(kDdsNamespaceMarker); pos != std::string::npos)
    {
        mangled = mangled.substr(0, pos) + "::" + mangled.substr(pos + std::strlen(kDdsNamespaceMarker));
    }
    if (!mangled.empty() && mangled.back() == '_')
    {
        mangled.pop_back();
    }

    std::string out;
    out.reserve(mangled.size());
    for (size_t i = 0; i < mangled.size();)
    {
        if (i + 1 < mangled.size() && mangled[i] == ':' && mangled[i + 1] == ':')
        {
            out += '/';
            i += 2;
        }
        else
        {
            out += mangled[i];
            ++i;
        }
    }
    return out;
}

std::string reliabilityLabel(const dds_qos_t* qos)
{
    dds_reliability_kind_t kind;
    if (qos == nullptr || !dds_qget_reliability(qos, &kind, nullptr))
    {
        return "unknown";
    }
    return kind == DDS_RELIABILITY_RELIABLE ? "reliable" : "best_effort";
}

std::string durabilityLabel(const dds_qos_t* qos)
{
    dds_durability_kind_t kind;
    if (qos == nullptr || !dds_qget_durability(qos, &kind))
    {
        return "unknown";
    }
    switch (kind)
    {
        case DDS_DURABILITY_VOLATILE:
            return "volatile";
        case DDS_DURABILITY_TRANSIENT_LOCAL:
            return "transient_local";
        case DDS_DURABILITY_TRANSIENT:
            return "transient";
        case DDS_DURABILITY_PERSISTENT:
            return "persistent";
        default:
            return "unknown";
    }
}

std::string historyLabel(const dds_qos_t* qos, int32_t* depthOut)
{
    dds_history_kind_t kind;
    int32_t depth = 0;
    if (qos == nullptr || !dds_qget_history(qos, &kind, &depth))
    {
        return "unknown";
    }
    *depthOut = depth;
    return kind == DDS_HISTORY_KEEP_ALL ? "keep_all" : "keep_last";
}

// Every rmw_cyclonedds participant sets these two properties, so this
// is the same identity `ros2 node list`/`ros2 doctor` ultimately draw
// on (though the real ROS 2 *node* name — as opposed to process name —
// lives in the ros_discovery_info topic's payload, which needs actual
// message decoding we don't have yet; process name is a close proxy
// for the common one-node-per-process case).
std::string qosProperty(const dds_qos_t* qos, const char* name)
{
    if (qos == nullptr)
    {
        return "";
    }
    char* value = nullptr;
    if (!dds_qget_prop(qos, name, &value) || value == nullptr)
    {
        return "";
    }
    std::string result(value);
    dds_string_free(value);
    return result;
}
}  // namespace

bool DDSManager::EndpointKey::operator<(const EndpointKey& other) const
{
    return std::memcmp(bytes, other.bytes, sizeof(bytes)) < 0;
}

bool DDSManager::EndpointKey::operator==(const EndpointKey& other) const
{
    return std::memcmp(bytes, other.bytes, sizeof(bytes)) == 0;
}

DDSManager::DDSManager()
    : participant_(0), pub_reader_(0), sub_reader_(0), participant_reader_(0)
{
}

DDSManager::~DDSManager()
{
    shutdown();
}

bool DDSManager::initialize(uint32_t domain_id, const std::string& peerAddressesCsv)
{
    if (participant_ > 0)
    {
        return true;  // Already initialized
    }

    std::string configXml = "<CycloneDDS><Domain>";

#if defined(__ANDROID__)
    // Native stdout/stderr aren't visible in logcat, so point Cyclone's
    // own tracing at a file we can pull with `adb shell run-as ... cat`
    // — this is a temporary diagnostic, not meant to ship as-is (it
    // grows unbounded for the life of the process).
    configXml +=
        "<Tracing><Category>trace</Category>"
        "<OutputFile>/data/data/com.handyros.handy_ros/files/handyros_cdds_trace.log</OutputFile>"
        "</Tracing>";
#endif

    if (!peerAddressesCsv.empty())
    {
        // Unicast discovery peers, used *alongside* the default SPDP
        // multicast — needed on networks that don't forward multicast
        // between Wi-Fi clients (phone hotspots, plenty of consumer
        // routers with client isolation).
        configXml += "<Discovery><Peers>";
        size_t start = 0;
        while (start <= peerAddressesCsv.size())
        {
            const size_t comma = peerAddressesCsv.find(',', start);
            const std::string addr = peerAddressesCsv.substr(start, comma == std::string::npos ? std::string::npos : comma - start);
            if (!addr.empty())
            {
                configXml += "<Peer address=\"" + addr + "\"/>";
            }
            if (comma == std::string::npos)
            {
                break;
            }
            start = comma + 1;
        }
        configXml += "</Peers></Discovery>";
    }

    configXml += "</Domain></CycloneDDS>";
    setenv("CYCLONEDDS_URI", configXml.c_str(), 1);

    participant_ = dds_create_participant(static_cast<dds_domainid_t>(domain_id), nullptr, nullptr);
    if (participant_ < 0)
    {
        participant_ = 0;
        return false;
    }

    dds_guid_t ownGuid;
    if (dds_get_guid(participant_, &ownGuid) == DDS_RETCODE_OK)
    {
        std::memcpy(ownParticipantKey_.bytes, ownGuid.v, sizeof(ownParticipantKey_.bytes));
    }

    pub_reader_ = dds_create_reader(participant_, DDS_BUILTIN_TOPIC_DCPSPUBLICATION, nullptr, nullptr);
    sub_reader_ = dds_create_reader(participant_, DDS_BUILTIN_TOPIC_DCPSSUBSCRIPTION, nullptr, nullptr);
    participant_reader_ = dds_create_reader(participant_, DDS_BUILTIN_TOPIC_DCPSPARTICIPANT, nullptr, nullptr);
    if (pub_reader_ < 0 || sub_reader_ < 0 || participant_reader_ < 0)
    {
        shutdown();
        return false;
    }

    return true;
}

void DDSManager::shutdown()
{
    if (participant_ > 0)
    {
        dds_delete(participant_);  // also deletes the readers created on it
    }
    participant_ = 0;
    pub_reader_ = 0;
    sub_reader_ = 0;
    participant_reader_ = 0;

    std::lock_guard<std::mutex> lock(mutex_);
    topics_.clear();
    endpointIndex_.clear();
    participants_.clear();
    statsTracker_.clear();
    payloadTracker_.clear();
    publisher_.clear();
}

void DDSManager::poll()
{
    if (participant_ <= 0)
    {
        return;
    }
    // Participants first so a publisher/subscriber discovered in the
    // same poll can resolve its node identity immediately. Message
    // rate/size stats for watched topics are drained on their own
    // background thread (see TopicStatsTracker) — no call needed here.
    drainParticipants();
    drainEndpoints(pub_reader_, true);
    drainEndpoints(sub_reader_, false);
}

void DDSManager::watchTopic(const std::string& topicName)
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = topics_.find(topicName);
    if (it == topics_.end() || it->second.type_name.empty())
    {
        return;
    }
    statsTracker_.trackIfKnownType(participant_, topicName, it->second.type_name, it->second.reliability == "reliable");
}

void DDSManager::unwatchTopic(const std::string& topicName)
{
    std::lock_guard<std::mutex> lock(mutex_);
    statsTracker_.untrack(topicName);
}

void DDSManager::watchPayload(const std::string& topicName)
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = topics_.find(topicName);
    if (it == topics_.end() || it->second.type_name.empty())
    {
        return;
    }
    payloadTracker_.watch(participant_, topicName, it->second.type_name, it->second.reliability == "reliable");
}

void DDSManager::unwatchPayload(const std::string& topicName)
{
    std::lock_guard<std::mutex> lock(mutex_);
    payloadTracker_.unwatch(topicName);
}

std::string DDSManager::topicPayloadJson(const std::string& topicName)
{
    // Not holding mutex_ here — TopicPayloadTracker has its own
    // internal locking (same as statsTracker_.get()), and this can be
    // called from Dart at a much higher cadence than topicsJson().
    return payloadTracker_.latestJson(topicName);
}

std::vector<uint8_t> DDSManager::topicPayloadBlob(const std::string& topicName)
{
    return payloadTracker_.latestBlob(topicName);
}

void DDSManager::publishTwist(const std::string& topicName, double linearX, double linearY, double linearZ,
                               double angularX, double angularY, double angularZ)
{
    if (participant_ <= 0)
    {
        return;
    }
    publisher_.publishTwist(participant_, topicName, linearX, linearY, linearZ, angularX, angularY, angularZ);
}

void DDSManager::publishImu(const std::string& topicName, const std::string& frameId, double accelX, double accelY,
                             double accelZ, double gyroX, double gyroY, double gyroZ, double orientX, double orientY,
                             double orientZ, double orientW)
{
    if (participant_ <= 0)
    {
        return;
    }
    publisher_.publishImu(participant_, topicName, frameId, accelX, accelY, accelZ, gyroX, gyroY, gyroZ, orientX,
                           orientY, orientZ, orientW);
}

void DDSManager::publishNavSatFix(const std::string& topicName, const std::string& frameId, double latitude,
                                   double longitude, double altitude)
{
    if (participant_ <= 0)
    {
        return;
    }
    publisher_.publishNavSatFix(participant_, topicName, frameId, latitude, longitude, altitude);
}

void DDSManager::publishMagneticField(const std::string& topicName, const std::string& frameId, double x, double y,
                                       double z)
{
    if (participant_ <= 0)
    {
        return;
    }
    publisher_.publishMagneticField(participant_, topicName, frameId, x, y, z);
}

void DDSManager::publishImage(const std::string& topicName, const std::string& frameId, uint32_t width,
                               uint32_t height, const std::string& encoding, bool isBigEndian, uint32_t step,
                               const uint8_t* data, size_t dataLen)
{
    if (participant_ <= 0)
    {
        return;
    }
    publisher_.publishImage(participant_, topicName, frameId, width, height, encoding, isBigEndian, step, data,
                             dataLen);
}

void DDSManager::stopPublishing(const std::string& topicName)
{
    publisher_.stopPublishing(topicName);
}

void DDSManager::drainParticipants()
{
    void* samples[kMaxSamplesPerTake] = {};
    dds_sample_info_t infos[kMaxSamplesPerTake];

    for (;;)
    {
        dds_return_t n = dds_take(participant_reader_, samples, infos, kMaxSamplesPerTake, kMaxSamplesPerTake);
        if (n <= 0)
        {
            break;
        }

        std::lock_guard<std::mutex> lock(mutex_);
        for (dds_return_t i = 0; i < n; ++i)
        {
            auto* pp = static_cast<dds_builtintopic_participant_t*>(samples[i]);
            EndpointKey key;
            std::memcpy(key.bytes, pp->key.v, sizeof(key.bytes));

            if (infos[i].valid_data)
            {
                std::string processName = qosProperty(pp->qos, "__ProcessName");
                std::string hostname = qosProperty(pp->qos, "__Hostname");
                participants_[key] = {processName.empty() ? "unknown" : processName, hostname.empty() ? "unknown" : hostname};
            }
            else
            {
                participants_.erase(key);
            }
        }
        dds_return_loan(participant_reader_, samples, n);
    }
}

DDSManager::NodeIdentity DDSManager::resolveNode(const EndpointKey& participantKey) const
{
    auto it = participants_.find(participantKey);
    if (it == participants_.end())
    {
        return {"unknown", "unknown"};
    }
    return it->second;
}

void DDSManager::drainEndpoints(dds_entity_t reader, bool is_publication)
{
    void* samples[kMaxSamplesPerTake] = {};
    dds_sample_info_t infos[kMaxSamplesPerTake];

    for (;;)
    {
        dds_return_t n = dds_take(reader, samples, infos, kMaxSamplesPerTake, kMaxSamplesPerTake);
        if (n <= 0)
        {
            break;
        }

        std::lock_guard<std::mutex> lock(mutex_);
        for (dds_return_t i = 0; i < n; ++i)
        {
            auto* ep = static_cast<dds_builtintopic_endpoint_t*>(samples[i]);

            EndpointKey key;
            std::memcpy(key.bytes, ep->key.v, sizeof(key.bytes));

            // demangleTopicName rejects Cyclone's own builtin discovery
            // topics (DCPSPublication, ...), ROS 2 services (rq//rr/),
            // and the ros_discovery_info graph-cache topic — only "rt/"
            // entries (real ROS 2 topics) come back Some.
            const std::optional<std::string> topicName =
                ep->topic_name != nullptr ? demangleTopicName(ep->topic_name) : std::nullopt;

            if (infos[i].valid_data && topicName.has_value())
            {
                EndpointKey participantKey;
                std::memcpy(participantKey.bytes, ep->participant_key.v, sizeof(participantKey.bytes));

                // Skip our own endpoints (e.g. TopicStatsTracker's typed
                // readers) — the app instrumenting a topic for stats
                // shouldn't count as real external publisher/subscriber
                // presence, and a topic should disappear once no real
                // peer is left even if we're still internally tracking it.
                if (participantKey == ownParticipantKey_)
                {
                    continue;
                }

                TopicInfo& info = topics_[*topicName];
                if (ep->type_name != nullptr)
                {
                    info.type_name = demangleTypeName(ep->type_name);
                }
                // Only the publisher's *offered* QoS determines what a
                // reader actually needs to match it and how the writer
                // really behaves — a subscriber's requested QoS (e.g. a
                // best-effort rviz/image_view reader on a reliable
                // camera topic) is a different thing and must not
                // clobber this, or a later-discovered subscriber can
                // silently flip what we think the topic's QoS is.
                if (is_publication)
                {
                    info.reliability = reliabilityLabel(ep->qos);
                    info.durability = durabilityLabel(ep->qos);
                    info.history = historyLabel(ep->qos, &info.depth);
                }
                (is_publication ? info.publishers : info.subscribers)[key] = participantKey;
                endpointIndex_[key] = {*topicName, is_publication};
            }
            else
            {
                removeEndpoint(key);
            }
        }
        dds_return_loan(reader, samples, n);
    }
}

void DDSManager::removeEndpoint(const EndpointKey& key)
{
    auto indexIt = endpointIndex_.find(key);
    if (indexIt == endpointIndex_.end())
    {
        return;
    }
    const std::string topicName = indexIt->second.first;
    const bool isPublication = indexIt->second.second;

    auto topicIt = topics_.find(topicName);
    if (topicIt != topics_.end())
    {
        auto& endpoints = isPublication ? topicIt->second.publishers : topicIt->second.subscribers;
        endpoints.erase(key);
        if (topicIt->second.publishers.empty() && topicIt->second.subscribers.empty())
        {
            topics_.erase(topicIt);
            statsTracker_.untrack(topicName);
            payloadTracker_.unwatch(topicName);
        }
    }
    endpointIndex_.erase(indexIt);
}

std::string DDSManager::topicsJson()
{
    std::lock_guard<std::mutex> lock(mutex_);

    auto nodesJson = [this](const std::map<EndpointKey, EndpointKey>& endpoints) {
        std::string out = "[";
        bool first = true;
        for (const auto& [endpointKey, participantKey] : endpoints)
        {
            if (!first)
            {
                out += ",";
            }
            first = false;
            const NodeIdentity node = resolveNode(participantKey);
            out += "{\"process\":\"" + json_util::escape(node.process_name) + "\",";
            out += "\"host\":\"" + json_util::escape(node.hostname) + "\"}";
        }
        out += "]";
        return out;
    };

    std::string out = "[";
    bool first = true;
    for (const auto& [name, info] : topics_)
    {
        if (!first)
        {
            out += ",";
        }
        first = false;

        const TopicStatsTracker::Stats stats = statsTracker_.get(name);

        out += "{\"name\":\"" + json_util::escape(name) + "\",";
        out += "\"type\":\"" + json_util::escape(info.type_name) + "\",";
        out += "\"publishers\":" + nodesJson(info.publishers) + ",";
        out += "\"subscribers\":" + nodesJson(info.subscribers) + ",";
        out += "\"reliability\":\"" + info.reliability + "\",";
        out += "\"durability\":\"" + info.durability + "\",";
        out += "\"history\":\"" + info.history + "\",";
        out += "\"depth\":" + std::to_string(info.depth) + ",";
        out += "\"statsAvailable\":" + std::string(stats.available ? "true" : "false") + ",";
        out += "\"rateHz\":" + std::to_string(stats.rateHz) + ",";
        out += "\"avgMsgSizeBytes\":" + std::to_string(stats.avgMsgSizeBytes) + ",";
        out += "\"bandwidthBytesPerSec\":" + std::to_string(stats.bandwidthBytesPerSec) + ",";
        out += "\"latencyMs\":" + std::to_string(stats.latencyMs) + "}";
    }
    out += "]";
    return out;
}
