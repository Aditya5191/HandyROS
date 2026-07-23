import '../models/tf_frame.dart';

/// Mock /tf tree data, ported from the HandyROS.dc.html design mockup.
class FakeTfService {
  static List<TfFrame> getFrames() {
    return const [
      TfFrame(
        name: 'map',
        depth: 0,
        parent: '—',
        children: 'odom',
        translation: '0.00, 0.00, 0.00',
        rotation: '0, 0, 0, 1',
        rate: '—',
      ),
      TfFrame(
        name: 'odom',
        depth: 1,
        parent: 'map',
        children: 'base_link',
        translation: '1.24, 0.63, 0.00',
        rotation: '0, 0, 0.08, 0.99',
        rate: '50 Hz',
      ),
      TfFrame(
        name: 'base_link',
        depth: 2,
        parent: 'odom',
        children: '4 frames',
        translation: '0.00, 0.00, 0.10',
        rotation: '0, 0, 0, 1',
        rate: '100 Hz',
      ),
      TfFrame(
        name: 'base_footprint',
        depth: 3,
        parent: 'base_link',
        children: '—',
        translation: '0.00, 0.00, -0.10',
        rotation: '0, 0, 0, 1',
        rate: '100 Hz',
      ),
      TfFrame(
        name: 'camera_link',
        depth: 3,
        parent: 'base_link',
        children: 'camera_optical',
        translation: '0.12, 0.00, 0.22',
        rotation: '0, 0, 0, 1',
        rate: '100 Hz',
      ),
      TfFrame(
        name: 'imu_link',
        depth: 3,
        parent: 'base_link',
        children: '—',
        translation: '-0.03, 0.00, 0.18',
        rotation: '0, 0, 0, 1',
        rate: '100 Hz',
      ),
      TfFrame(
        name: 'laser_link',
        depth: 3,
        parent: 'base_link',
        children: '—',
        translation: '0.00, 0.00, 0.30',
        rotation: '0, 0, 0.71, 0.71',
        rate: '100 Hz',
      ),
    ];
  }
}
