#pragma once
#include <memory>
#include <string>

#include <dds/dds.h>

// Real message rate/size/bandwidth/latency for every ROS 2 message
// type we have generated typed bindings for — see CMakeLists.txt's
// idlc build step and topic_registry_generated.{h,cpp} (produced by
// tools/patch_idl.py from ROS 2's own .idl files at build time). Byte
// size comes from dds_takecdr + ddsi_serdata_size, both fully standard
// public Cyclone DDS APIs — no custom serializer plugin, and no
// per-type C++ needed here since we only measure size/timing, never
// decode fields. A topic whose type has no generated binding (a
// project-specific custom type) just won't have stats available.
//
// Each tracked reader is drained on its own background thread (~30ms
// cadence) rather than from DDSManager::poll() — that's driven by the
// Dart UI timer (500ms, and not reliably even that), and a reader's
// DDS-side history cache (KEEP_LAST) overflows and silently discards
// samples if they're not drained often enough relative to the
// publish rate, capping the observed rate at (depth / drain interval)
// well below the real one.
class TopicStatsTracker
{
public:
    struct Stats
    {
        bool available = false;
        double rateHz = 0;
        double avgMsgSizeBytes = 0;
        double bandwidthBytesPerSec = 0;
        double latencyMs = 0;
    };

    TopicStatsTracker();
    ~TopicStatsTracker();

    // Creates a typed reader for topicName if rosType is one we have
    // bindings for and it isn't already tracked. No-op otherwise.
    //
    // reliable should mirror the actual publisher's QoS (DDSManager
    // already observes this from builtin-topic discovery). A reader
    // QoS mismatch either fails to match a RELIABLE-only writer at
    // all, or — for a RELIABLE writer — silently loses any large,
    // multi-fragment sample (camera/point-cloud frames) to a single
    // dropped UDP fragment, since a BEST_EFFORT reader never sends
    // ACKNACKs to request retransmission.
    void trackIfKnownType(dds_entity_t participant, const std::string& topicName, const std::string& rosType, bool reliable);

    // Drops the reader for a topic that's no longer discovered.
    void untrack(const std::string& topicName);

    Stats get(const std::string& topicName) const;

    // Drops every tracked reader (does not itself delete DDS entities —
    // call this after the owning participant has been/is being deleted).
    void clear();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
