#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// C API surface consumed by the Flutter app over dart:ffi. Keep this
// header FFI-friendly: plain C types only, no C++ classes/exceptions
// crossing the boundary.

#ifdef __cplusplus
extern "C" {
#endif

// Starts DDS discovery on the given ROS domain ID. Safe to call again
// (no-op) if already initialized on the same participant.
//
// peers_csv: comma-separated host IPs to also reach via unicast
// discovery (may be NULL/empty to rely on multicast alone). Use this
// when the network doesn't forward multicast between Wi-Fi clients.
bool handyros_initialize(uint32_t domain_id, const char* peers_csv);

// Tears down the participant and clears the topic registry.
void handyros_shutdown(void);

// Pumps pending discovery events into the topic registry. Call this
// periodically (e.g. every few hundred ms) before reading the JSON
// snapshot, since Cyclone DDS delivers discovery info asynchronously.
void handyros_poll(void);

// Starts/stops measuring real rate/size/bandwidth/latency for one
// topic (only meaningful if its type has a generated binding — see
// CMakeLists.txt). Not automatic for every discovered topic: some are
// camera/point-cloud streams at tens of MB/s, and receiving all of
// them just to report a number nobody's looking at is real bandwidth/
// memory/battery cost on a phone. Call when a topic's detail view
// opens/closes.
void handyros_watch_topic(const char* topic_name);
void handyros_unwatch_topic(const char* topic_name);

// Starts/stops decoding real message field values for one topic —
// only meaningful for the fixed set of types with a dedicated Viewer
// screen (Imu, Image, PointCloud2, LaserScan, Odometry, TFMessage,
// String, Log, Float32, Float64); a no-op for anything else. Call
// when a Viewer screen for that topic opens/closes. Independent of
// handyros_watch_topic/unwatch_topic — a Viewer screen wants both
// stats and decoded payload, but the topic-list card only ever wants
// the former.
void handyros_watch_payload(const char* topic_name);
void handyros_unwatch_payload(const char* topic_name);

// Heap-allocated, null-terminated JSON snapshot of currently known
// topics: [{"name":"/scan","type":"...","publishers":1,"subscribers":2}]
// Caller owns the returned pointer and must release it with
// handyros_free_string.
const char* handyros_topics_json(void);

// Heap-allocated, null-terminated JSON snapshot of the latest decoded
// sample for one topic, e.g. {"available":true,"kind":"imu",...} —
// see TopicPayloadTracker::latestJson for the exact per-type shape.
// {"available":false,"supported":false} if the type isn't decodable;
// {"available":false,"supported":true} if watched but no sample has
// arrived yet. Caller owns the returned pointer and must release it
// with handyros_free_string.
const char* handyros_topic_payload_json(const char* topic_name);

// Heap-allocated raw binary payload paired with the JSON above (image
// pixel bytes, or pre-extracted point cloud [x,y,z,colorBits] float32
// tuples) — *out_len is set to 0 and NULL is returned if the type has
// no blob component or no sample has arrived yet. Caller owns the
// returned pointer and must release it with handyros_free_blob.
const uint8_t* handyros_topic_payload_blob(const char* topic_name, size_t* out_len);

void handyros_free_string(const char* s);
void handyros_free_blob(const uint8_t* ptr);

// Writer side: publishes one sample of a fixed, known message type on
// [topic_name] — used by the Sensors/Teleop screens, the app's own
// only writers on the DDS graph. A writer is created lazily on the
// first publish call for a given topic name and reused after that, so
// a given name should only ever be used with one of these kinds.
// frame_id may be NULL/empty. No-op if DDS isn't initialized.
void handyros_publish_twist(const char* topic_name, double linear_x, double linear_y, double linear_z,
                             double angular_x, double angular_y, double angular_z);

void handyros_publish_imu(const char* topic_name, const char* frame_id, double accel_x, double accel_y,
                           double accel_z, double gyro_x, double gyro_y, double gyro_z, double orient_x,
                           double orient_y, double orient_z, double orient_w);

void handyros_publish_nav_sat_fix(const char* topic_name, const char* frame_id, double latitude, double longitude,
                                   double altitude);

void handyros_publish_magnetic_field(const char* topic_name, const char* frame_id, double x, double y, double z);

void handyros_publish_image(const char* topic_name, const char* frame_id, uint32_t width, uint32_t height,
                             const char* encoding, bool is_bigendian, uint32_t step, const uint8_t* data,
                             size_t data_len);

// Deletes the writer for topic_name (whichever publish kind created
// it). Call when a Sensors card or Teleop's publish toggle turns off.
void handyros_publish_stop(const char* topic_name);

#ifdef __cplusplus
}
#endif
