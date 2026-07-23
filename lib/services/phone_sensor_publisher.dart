import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'dds_topic_service.dart';
import 'yuv_to_rgb.dart';

/// Turns the phone into a set of ROS sensor sources — wraps
/// sensors_plus/geolocator/camera streams and republishes each as the
/// matching ROS message via [DdsTopicService]. The four sensor kinds
/// (IMU, GPS, magnetometer, camera) start/stop independently.
class PhoneSensorPublisher extends ChangeNotifier {
  final DdsTopicService dds;
  PhoneSensorPublisher(this.dds);

  // IMU: accelerometer + gyroscope folded into one sensor_msgs/Imu
  // stream, published at the accelerometer's own event rate — the
  // gyroscope's latest reading just rides along as it arrives.
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  String? _imuTopic;
  AccelerometerEvent? lastAccel;
  GyroscopeEvent? lastGyro;
  bool get imuActive => _imuTopic != null;

  void startImu(String topic) {
    if (_imuTopic != null) return;
    _imuTopic = topic;
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((e) => lastGyro = e);
    _accelSub =
        accelerometerEventStream(
          samplingPeriod: SensorInterval.gameInterval,
        ).listen((e) {
          lastAccel = e;
          final g = lastGyro;
          dds.publishImu(
            topic,
            frameId: 'phone',
            ax: e.x,
            ay: e.y,
            az: e.z,
            gx: g?.x ?? 0,
            gy: g?.y ?? 0,
            gz: g?.z ?? 0,
          );
          notifyListeners();
        });
    notifyListeners();
  }

  void stopImu() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    if (_imuTopic != null) dds.stopPublishing(_imuTopic!);
    _imuTopic = null;
    lastAccel = null;
    lastGyro = null;
    notifyListeners();
  }

  // Magnetometer.
  StreamSubscription<MagnetometerEvent>? _magSub;
  String? _magTopic;
  MagnetometerEvent? lastMag;
  bool get magActive => _magTopic != null;

  void startMagnetometer(String topic) {
    if (_magTopic != null) return;
    _magTopic = topic;
    _magSub = magnetometerEventStream().listen((e) {
      lastMag = e;
      // sensors_plus reports microtesla; sensor_msgs/MagneticField
      // wants tesla.
      dds.publishMagneticField(
        topic,
        frameId: 'phone',
        x: e.x * 1e-6,
        y: e.y * 1e-6,
        z: e.z * 1e-6,
      );
      notifyListeners();
    });
    notifyListeners();
  }

  void stopMagnetometer() {
    _magSub?.cancel();
    _magSub = null;
    if (_magTopic != null) dds.stopPublishing(_magTopic!);
    _magTopic = null;
    lastMag = null;
    notifyListeners();
  }

  // GPS.
  StreamSubscription<Position>? _gpsSub;
  String? _gpsTopic;
  Position? lastPosition;
  String? gpsError;
  bool get gpsActive => _gpsTopic != null;

  Future<void> startGps(String topic) async {
    if (_gpsTopic != null) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      gpsError = 'Location permission denied';
      notifyListeners();
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      gpsError = 'Location services are off';
      notifyListeners();
      return;
    }
    gpsError = null;
    _gpsTopic = topic;
    _gpsSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).listen((pos) {
          lastPosition = pos;
          dds.publishNavSatFix(
            topic,
            frameId: 'phone',
            latitude: pos.latitude,
            longitude: pos.longitude,
            altitude: pos.altitude,
          );
          notifyListeners();
        });
    notifyListeners();
  }

  void stopGps() {
    _gpsSub?.cancel();
    _gpsSub = null;
    if (_gpsTopic != null) dds.stopPublishing(_gpsTopic!);
    _gpsTopic = null;
    lastPosition = null;
    notifyListeners();
  }

  // Camera. Frames arrive much faster than we want to publish, so
  // only every _frameSkip-th frame is converted+sent, and a frame
  // already being converted is never queued behind — always publish
  // the freshest one, drop the rest.
  CameraController? cameraController;
  String? _cameraTopic;
  String? cameraError;
  bool get cameraActive => _cameraTopic != null;
  static const _frameSkip = 3; // ~30fps camera -> ~10fps published
  int _frameCounter = 0;
  bool _frameInFlight = false;

  Future<void> startCamera(String topic) async {
    if (_cameraTopic != null) return;
    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (e) {
      cameraError = 'Camera unavailable: $e';
      notifyListeners();
      return;
    }
    if (cameras.isEmpty) {
      cameraError = 'No camera available';
      notifyListeners();
      return;
    }
    final controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    try {
      await controller.initialize();
    } catch (e) {
      cameraError = 'Camera init failed: $e';
      notifyListeners();
      return;
    }
    cameraError = null;
    cameraController = controller;
    _cameraTopic = topic;
    _frameCounter = 0;
    await controller.startImageStream(_onCameraFrame);
    notifyListeners();
  }

  void _onCameraFrame(CameraImage image) {
    if (_cameraTopic == null) return;
    _frameCounter++;
    if (_frameCounter % _frameSkip != 0) return;
    if (_frameInFlight) return;
    if (image.planes.length < 3) return;
    _frameInFlight = true;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final request = Yuv420ToRgbRequest(
      width: image.width,
      height: image.height,
      yBytes: yPlane.bytes,
      yStride: yPlane.bytesPerRow,
      uBytes: uPlane.bytes,
      uStride: uPlane.bytesPerRow,
      uPixelStride: uPlane.bytesPerPixel ?? 1,
      vBytes: vPlane.bytes,
      vStride: vPlane.bytesPerRow,
      vPixelStride: vPlane.bytesPerPixel ?? 1,
    );
    compute(convertYuv420ToRgb, request)
        .then((rgb) {
          _frameInFlight = false;
          final topic = _cameraTopic;
          if (topic == null) return;
          dds.publishImage(
            topic,
            frameId: 'phone_camera',
            width: image.width,
            height: image.height,
            encoding: 'rgb8',
            step: image.width * 3,
            data: rgb,
          );
        })
        .catchError((_) {
          _frameInFlight = false;
        });
  }

  Future<void> stopCamera() async {
    final controller = cameraController;
    cameraController = null;
    final topic = _cameraTopic;
    _cameraTopic = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {
        // Already torn down (e.g. the widget disposed mid-stream) —
        // stopCamera's job is just to make sure it's stopped.
      }
      await controller.dispose();
    }
    if (topic != null) dds.stopPublishing(topic);
    notifyListeners();
  }

  @override
  void dispose() {
    stopImu();
    stopMagnetometer();
    stopGps();
    stopCamera();
    super.dispose();
  }
}
