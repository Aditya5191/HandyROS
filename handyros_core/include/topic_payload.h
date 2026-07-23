#pragma once
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include <dds/dds.h>

// Real decoded message field values — for the fixed, hand-picked set
// of message types with a dedicated Viewer screen (Imu, Image,
// PointCloud2, LaserScan, Odometry, TFMessage, String, Log, Float32,
// Float64). Deliberately NOT generic/reflective: each type's decoder
// is a small hand-written function that knows its own generated C
// struct, the same "known types only" approach used elsewhere in this
// codebase (ViewerRegistry's type lists, TopicStatsTracker). A type
// outside this set just isn't watchable here — [watch] returns false
// and the caller falls back to showing topic metadata only.
//
// Distinct from TopicStatsTracker: that one uses dds_takecdr to stay
// generic across all 144 registered types but never looks at field
// values. This one uses the typed dds_take specifically so it can
// read real fields, at the cost of only working for types it has a
// decoder for. Only one or two topics are ever watched here at once
// (whichever Viewer screen is open), so the cost of a second reader
// per watched topic is negligible next to what TopicStatsTracker
// already does.
class TopicPayloadTracker
{
public:
    TopicPayloadTracker();
    ~TopicPayloadTracker();

    // Creates a typed reader for topicName if rosType is one of the
    // decodable types and it isn't already tracked. Returns false
    // (no-op) for any other type. `reliable` should mirror the actual
    // publisher's QoS, same rationale as TopicStatsTracker::trackIfKnownType.
    bool watch(dds_entity_t participant, const std::string& topicName, const std::string& rosType, bool reliable);

    void unwatch(const std::string& topicName);

    // Decoded fields as JSON, always including a top-level
    // "available" bool: false until at least one sample has actually
    // been received (not merely "some time has passed" — see the
    // stats-availability fix earlier for why that distinction
    // matters). Large binary payloads (image pixels, point cloud
    // coordinates) are NOT included here — see latestBlob.
    std::string latestJson(const std::string& topicName) const;

    // The paired binary blob for the latest sample, if the type has
    // one (Image: raw pixel bytes; PointCloud2: pre-extracted
    // [x,y,z,intensity] float32 tuples). Empty for types without a
    // blob component, or before the first sample arrives.
    std::vector<uint8_t> latestBlob(const std::string& topicName) const;

    // Drops every tracked reader (does not itself delete DDS entities —
    // call this after the owning participant has been/is being deleted).
    void clear();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
