#include "topic_publisher.h"

#include <cstring>
#include <map>
#include <mutex>

#include "geometry_msgs/msg/Twist.h"
#include "sensor_msgs/msg/Image.h"
#include "sensor_msgs/msg/Imu.h"
#include "sensor_msgs/msg/MagneticField.h"
#include "sensor_msgs/msg/NavSatFix.h"

namespace
{
// ROS 2 mangles topic names with an "rt/" prefix at the DDS layer —
// same convention as DDSManager::demangleTopicName/TopicStatsTracker's
// mangleTopicName, just for a name that always starts with '/' here.
std::string mangleTopicName(const std::string& topicName)
{
    return "rt" + topicName;
}

// REP-103/145 convention: a covariance matrix's first element set to
// -1 means "unknown", since a phone sensor has no real covariance
// estimate to report.
void setCovarianceUnknown(double (&covariance)[9])
{
    covariance[0] = -1;
    for (int i = 1; i < 9; ++i)
    {
        covariance[i] = 0;
    }
}

void setHeader(std_msgs_msg_Header& header, const char* frameId)
{
    const dds_time_t now = dds_time();
    header.stamp.sec = static_cast<int32_t>(now / DDS_NSECS_IN_SEC);
    header.stamp.nanosec = static_cast<uint32_t>(now % DDS_NSECS_IN_SEC);
    header.frame_id = const_cast<char*>(frameId);
}

struct TrackedWriter
{
    dds_entity_t topic = 0;
    dds_entity_t writer = 0;
};
}  // namespace

struct TopicPublisher::Impl
{
    std::mutex mutex;
    std::map<std::string, TrackedWriter> writers;

    // Looks up (or lazily creates) the writer for topicName. A given
    // name is expected to only ever be used with one descriptor/QoS
    // pair — the first publish call for that name wins.
    dds_entity_t getOrCreateWriter(dds_entity_t participant, const std::string& topicName,
                                    const dds_topic_descriptor_t* descriptor, bool reliable, int32_t historyDepth)
    {
        auto it = writers.find(topicName);
        if (it != writers.end())
        {
            return it->second.writer;
        }

        dds_qos_t* topicQos = dds_create_qos();
        dds_entity_t topic = dds_create_topic(participant, descriptor, mangleTopicName(topicName).c_str(), topicQos, nullptr);
        dds_delete_qos(topicQos);
        if (topic < 0)
        {
            return 0;
        }

        dds_qos_t* writerQos = dds_create_qos();
        if (reliable)
        {
            dds_qset_reliability(writerQos, DDS_RELIABILITY_RELIABLE, DDS_SECS(1));
        }
        else
        {
            dds_qset_reliability(writerQos, DDS_RELIABILITY_BEST_EFFORT, 0);
        }
        dds_qset_history(writerQos, DDS_HISTORY_KEEP_LAST, historyDepth);

        dds_entity_t writer = dds_create_writer(participant, topic, writerQos, nullptr);
        dds_delete_qos(writerQos);
        if (writer < 0)
        {
            dds_delete(topic);
            return 0;
        }

        writers[topicName] = TrackedWriter{topic, writer};
        return writer;
    }
};

TopicPublisher::TopicPublisher() : impl_(std::make_unique<Impl>()) {}
TopicPublisher::~TopicPublisher() = default;

void TopicPublisher::publishTwist(dds_entity_t participant, const std::string& topicName, double linearX,
                                   double linearY, double linearZ, double angularX, double angularY, double angularZ)
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    const dds_entity_t writer = impl_->getOrCreateWriter(participant, topicName, &geometry_msgs_msg_Twist_desc, true, 10);
    if (writer <= 0)
    {
        return;
    }

    geometry_msgs_msg_Twist sample{};
    sample.linear.x = linearX;
    sample.linear.y = linearY;
    sample.linear.z = linearZ;
    sample.angular.x = angularX;
    sample.angular.y = angularY;
    sample.angular.z = angularZ;
    dds_write(writer, &sample);
}

void TopicPublisher::publishImu(dds_entity_t participant, const std::string& topicName, const std::string& frameId,
                                 double accelX, double accelY, double accelZ, double gyroX, double gyroY,
                                 double gyroZ, double orientX, double orientY, double orientZ, double orientW)
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    const dds_entity_t writer = impl_->getOrCreateWriter(participant, topicName, &sensor_msgs_msg_Imu_desc, true, 10);
    if (writer <= 0)
    {
        return;
    }

    sensor_msgs_msg_Imu sample{};
    setHeader(sample.header, frameId.c_str());
    sample.orientation.x = orientX;
    sample.orientation.y = orientY;
    sample.orientation.z = orientZ;
    sample.orientation.w = orientW;
    sample.angular_velocity.x = gyroX;
    sample.angular_velocity.y = gyroY;
    sample.angular_velocity.z = gyroZ;
    sample.linear_acceleration.x = accelX;
    sample.linear_acceleration.y = accelY;
    sample.linear_acceleration.z = accelZ;
    setCovarianceUnknown(sample.orientation_covariance);
    setCovarianceUnknown(sample.angular_velocity_covariance);
    setCovarianceUnknown(sample.linear_acceleration_covariance);
    dds_write(writer, &sample);
}

void TopicPublisher::publishNavSatFix(dds_entity_t participant, const std::string& topicName,
                                       const std::string& frameId, double latitude, double longitude, double altitude)
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    const dds_entity_t writer =
        impl_->getOrCreateWriter(participant, topicName, &sensor_msgs_msg_NavSatFix_desc, true, 10);
    if (writer <= 0)
    {
        return;
    }

    sensor_msgs_msg_NavSatFix sample{};
    setHeader(sample.header, frameId.c_str());
    sample.status.status = sensor_msgs_msg_NavSatStatus_Constants_STATUS_FIX;
    sample.status.service = sensor_msgs_msg_NavSatStatus_Constants_SERVICE_GPS;
    sample.latitude = latitude;
    sample.longitude = longitude;
    sample.altitude = altitude;
    sample.position_covariance_type = sensor_msgs_msg_NavSatFix_Constants_COVARIANCE_TYPE_UNKNOWN;
    dds_write(writer, &sample);
}

void TopicPublisher::publishMagneticField(dds_entity_t participant, const std::string& topicName,
                                           const std::string& frameId, double x, double y, double z)
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    const dds_entity_t writer =
        impl_->getOrCreateWriter(participant, topicName, &sensor_msgs_msg_MagneticField_desc, true, 10);
    if (writer <= 0)
    {
        return;
    }

    sensor_msgs_msg_MagneticField sample{};
    setHeader(sample.header, frameId.c_str());
    sample.magnetic_field.x = x;
    sample.magnetic_field.y = y;
    sample.magnetic_field.z = z;
    setCovarianceUnknown(sample.magnetic_field_covariance);
    dds_write(writer, &sample);
}

void TopicPublisher::publishImage(dds_entity_t participant, const std::string& topicName, const std::string& frameId,
                                   uint32_t width, uint32_t height, const std::string& encoding, bool isBigEndian,
                                   uint32_t step, const uint8_t* data, size_t dataLen)
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    // RELIABLE (not BEST_EFFORT): a RELIABLE writer satisfies both
    // RELIABLE and BEST_EFFORT readers, whereas a BEST_EFFORT writer
    // only satisfies BEST_EFFORT readers (DDS RxO compatibility needs
    // writer reliability >= reader's). RViz2's Image display defaults
    // to a RELIABLE subscription, so a BEST_EFFORT writer here simply
    // never matches it — no error, just silently no image. History
    // stays shallow (2) so a slow subscriber doesn't pile up stale
    // frames behind a fresh one.
    const dds_entity_t writer = impl_->getOrCreateWriter(participant, topicName, &sensor_msgs_msg_Image_desc, true, 2);
    if (writer <= 0)
    {
        return;
    }

    sensor_msgs_msg_Image sample{};
    setHeader(sample.header, frameId.c_str());
    sample.width = width;
    sample.height = height;
    sample.encoding = const_cast<char*>(encoding.c_str());
    sample.is_bigendian = isBigEndian ? 1 : 0;
    sample.step = step;
    // dds_write copies the sample synchronously, so it's safe to point
    // straight at the caller's buffer for the duration of this call —
    // _release = false tells Cyclone it doesn't own (and must not
    // free) this pointer.
    sample.data._buffer = const_cast<uint8_t*>(data);
    sample.data._length = static_cast<uint32_t>(dataLen);
    sample.data._maximum = static_cast<uint32_t>(dataLen);
    sample.data._release = false;
    dds_write(writer, &sample);
}

void TopicPublisher::stopPublishing(const std::string& topicName)
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    auto it = impl_->writers.find(topicName);
    if (it == impl_->writers.end())
    {
        return;
    }
    dds_delete(it->second.writer);
    dds_delete(it->second.topic);
    impl_->writers.erase(it);
}

void TopicPublisher::clear()
{
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->writers.clear();
}
