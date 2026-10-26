class DanmakuMedia {
  final String provider;
  final String mediaId;
  final String title;
  final String type;
  final int? year;
  const DanmakuMedia({
    required this.provider,
    required this.mediaId,
    required this.title,
    required this.type,
    this.year,
  });
}
