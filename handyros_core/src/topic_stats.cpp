#include "topic_stats.h"

#include <atomic>
#include <chrono>
#include <deque>
#include <map>
#include <mutex>
#include <thread>

#include <dds/ddsi/ddsi_serdata.h>

#include "topic_registry_generated.h"

namespace
{
// ROS 2 mangles topic names with an "rt/" prefix at the DDS layer —
// the inverse of DDSManager's demangleTopicName (topicName here always
// starts with '/', e.g. "/imu" -> "rt/imu").
std::string mangleTopicName(const std::string& topicName)
{
    return "rt" + topicName;
}

struct SampleRecord
{
    dds_time_t timestamp = 0;
    uint32_t sizeBytes = 0;
};

// Rate/size/bandwidth are derived from the actual timestamps of the
// last kCapacity samples (same approach `ros2 topic hz` uses), not
// from how much time happened to pass between two poll() calls. A
// poll-cadence window (the previous approach) makes the reading swing
// wildly for low-rate topics: a 500ms poll timer is neither exact nor
// guaranteed prompt (UI thread jank, GC, Android timer coalescing),
// so one message landing in a short tick reads as a much higher Hz
// than the same message spread across a longer one, even though the
// publisher's actual rate never changed.
struct Window
{
    static constexpr size_t kCapacity = 20;
    std::deque<SampleRecord> samples;
    TopicStatsTracker::Stats stats;
};

struct TrackedReader
{
    dds_entity_t topic = 0;
    dds_entity_t reader = 0;
    Window window;
};

constexpr uint32_t kMaxSamplesPerPoll = 8;

// dds_takecdr + ddsi_serdata_size gives the exact on-wire byte count
// for *any* registered type generically — no per-type field-walking
// code needed, unlike measuring size from a deserialized typed sample.
void drain(dds_entity_t reader, Window& window)
{
    struct ddsi_serdata* samples[kMaxSamplesPerPoll] = {};
    dds_sample_info_t infos[kMaxSamplesPerPoll];
    for (;;)
    {
        dds_return_t n = dds_takecdr(reader, samples, kMaxSamplesPerPoll, infos, DDS_ANY_STATE);
        if (n <= 0)
        {
            break;
        }
        for (dds_return_t i = 0; i < n; ++i)
        {
            if (infos[i].valid_data)
            {
                window.samples.push_back({infos[i].source_timestamp, static_cast<uint32_t>(ddsi_serdata_size(samples[i]))});
                if (window.samples.size() > Window::kCapacity)
                {
                    window.samples.pop_front();
                }
            }
            ddsi_serdata_unref(samples[i]);
        }
    }
}

void refreshWindow(Window& window)
{
    // Need at least two samples to measure an interval between them.
    if (window.samples.size() < 2)
    {
        return;
    }

    const SampleRecord& oldest = window.samples.front();
    const SampleRecord& newest = window.samples.back();
    const double elapsedSec = static_cast<double>(newest.timestamp - oldest.timestamp) / 1e9;
    if (elapsedSec <= 0)
    {
        return;  // clock skew/duplicate timestamps — wait for more data
    }

    uint64_t totalBytes = 0;
    for (const auto& sample : window.samples)
    {
        totalBytes += sample.sizeBytes;
    }
    const size_t n = window.samples.size();

    window.stats.available = true;
    window.stats.rateHz = static_cast<double>(n - 1) / elapsedSec;
    window.stats.avgMsgSizeBytes = static_cast<double>(totalBytes) / static_cast<double>(n);
    window.stats.bandwidthBytesPerSec = window.stats.rateHz * window.stats.avgMsgSizeBytes;

    const dds_time_t now = dds_time();
    const double latencyMs = static_cast<double>(now - newest.timestamp) / 1e6;
    // Guards against nonsense from unsynchronized clocks across
    // machines rather than pretending to be a precise measurement.
    if (latencyMs >= 0 && latencyMs < 60000)
    {
        window.stats.latencyMs = latencyMs;
    }
}
}  // namespace

struct TopicStatsTracker::Impl
{
    mutable std::mutex mutex;
    std::map<std::string, TrackedReader> readers;

    // Draining/refreshing on its own tight loop — independent of
    // DDSManager::poll(), which only runs as often as the Dart UI
    // timer fires (500ms, and not even reliably that often under UI
    // jank). At 500ms, a topic publishing faster than
    // (KEEP_LAST depth / 0.5s) silently loses the excess to history
    // overflow before we ever drain it — e.g. depth 8 caps the
    // observed rate at ~16Hz regardless of the real rate, which is
    // exactly what made a 23Hz IMU topic read as ~8Hz. A tight
    // internal loop only needs the depth to cover its own short
    // interval, not the UI's.
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
                    drain(tracked.reader, tracked.window);
                    refreshWindow(tracked.window);
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(30));
        }
    }
};

TopicStatsTracker::TopicStatsTracker() : impl_(std::make_unique<Impl>()) {}
TopicStatsTracker::~TopicStatsTracker() = default;

void TopicStatsTracker::trackIfKnownType(dds_entity_t participant, const std::string& topicName, const std::string& rosType, bool reliable)
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (impl_->readers.count(topicName) > 0)
    {
        return;
    }
    const auto& registry = handyrosTopicDescriptors();
    auto descIt = registry.find(rosType);
    if (descIt == registry.end())
    {
        return;
    }

    // The topic entity itself is created with plain default QoS —
    // *not* the reliability/history below — because TopicPayloadTracker
    // may independently want a topic entity for this same name (a
    // Viewer screen watches both stats and decoded payload at once).
    // Cyclone rejects a second dds_create_topic() on an existing name
    // when the QoS doesn't match the first caller's, so both trackers
    // must agree on the topic-level QoS; the actual reliability/history
    // we care about is set explicitly on the *reader* below, which
    // always takes precedence over the topic's default for that reader.
    dds_qos_t* topicQos = dds_create_qos();
    dds_entity_t topic = dds_create_topic(participant, descIt->second, mangleTopicName(topicName).c_str(), topicQos, nullptr);
    dds_delete_qos(topicQos);
    if (topic < 0)
    {
        return;
    }

    dds_qos_t* readerQos = dds_create_qos();
    // Mirror the publisher's actual reliability: a BEST_EFFORT reader
    // can't match a RELIABLE-only writer (RxO compatibility), and even
    // when it does match a RELIABLE writer, BEST_EFFORT never requests
    // retransmission of a lost fragment — so any large, multi-fragment
    // sample (camera/point-cloud frames) is silently dropped in full
    // the moment a single UDP fragment goes missing.
    if (reliable)
    {
        dds_qset_reliability(readerQos, DDS_RELIABILITY_RELIABLE, DDS_SECS(1));
        dds_qset_history(readerQos, DDS_HISTORY_KEEP_LAST, 8);
    }
    else
    {
        dds_qset_reliability(readerQos, DDS_RELIABILITY_BEST_EFFORT, 0);
        dds_qset_history(readerQos, DDS_HISTORY_KEEP_LAST, 16);
    }

    TrackedReader tracked;
    tracked.topic = topic;
    tracked.reader = dds_create_reader(participant, tracked.topic, readerQos, nullptr);
    dds_delete_qos(readerQos);
    if (tracked.reader < 0)
    {
        dds_delete(tracked.topic);
        return;
    }

    impl_->readers[topicName] = tracked;
}

void TopicStatsTracker::untrack(const std::string& topicName)
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

TopicStatsTracker::Stats TopicStatsTracker::get(const std::string& topicName) const
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    auto it = impl_->readers.find(topicName);
    if (it == impl_->readers.end())
    {
        return {};
    }
    return it->second.window.stats;
}

void TopicStatsTracker::clear()
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->readers.clear();
}
