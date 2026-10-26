class DanmakuSettings {
  final String displayMode;
  final double opacity;
  final double speed;
  final double fontScale;
  final int densityPct;
  final bool antiOverlap;
  const DanmakuSettings({
    this.displayMode = 'auto',
    this.opacity = 1.0,
    this.speed = 1.0,
    this.fontScale = 1.0,
    this.densityPct = 100,
    this.antiOverlap = true,
  });
}
