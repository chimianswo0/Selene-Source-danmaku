class DanmakuRenderSettings {
  final double opacity;
  final double speed;
  final double fontScale;
  final int densityPct;
  final bool antiOverlap;
  static const opacities = [0.4, 0.55, 0.7, 0.85, 1.0];
  static const speeds = [0.5, 0.75, 1.0, 1.5, 2.0];
  static const fontScales = [0.7, 0.85, 1.0, 1.2, 1.4];
  static const densityPcts = [25, 50, 75, 100];
  const DanmakuRenderSettings({
    this.opacity = 1.0,
    this.speed = 1.0,
    this.fontScale = 1.0,
    this.densityPct = 100,
    this.antiOverlap = true,
  });
}
