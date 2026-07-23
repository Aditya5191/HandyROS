/// A single frame in the /tf tree, as shown in the TF Viewer.
class TfFrame {
  final String name;
  final int depth;
  final String parent;
  final String children;
  final String translation;
  final String rotation;
  final String rate;

  const TfFrame({
    required this.name,
    required this.depth,
    required this.parent,
    required this.children,
    required this.translation,
    required this.rotation,
    required this.rate,
  });
}
