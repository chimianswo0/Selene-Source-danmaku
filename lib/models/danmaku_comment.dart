class DanmakuComment {
  final int timeMs;
  final int mode;
  final int color;
  final String content;
  const DanmakuComment({required this.timeMs, required this.mode, required this.color, required this.content});
}

class DanmakuCommentBatch {
  final List<DanmakuComment> comments;
  const DanmakuCommentBatch(this.comments);
  
  static DanmakuCommentBatch fromXml(String xml) {
    final comments = <DanmakuComment>[];
    final pattern = RegExp(r'<d p="([^"]+)">(.*?)</d>');
    for (final match in pattern.allMatches(xml)) {
      final parts = match.group(1)!.split(',');
      if (parts.length < 4) continue;
      final timeMs = (double.parse(parts[0]) * 1000).round();
      final mode = int.tryParse(parts[1]) ?? 0;
      final colorHex = int.tryParse(parts[2], radix: 16) ?? 0xFFFFFF;
      // Convert from BGR to ARGB
      final color = 0xFF000000 | ((colorHex & 0xFF) << 16) | (colorHex & 0xFF00) | ((colorHex >> 16) & 0xFF);
      comments.add(DanmakuComment(
        timeMs: timeMs,
        mode: mode,
        color: color,
        content: match.group(2) ?? ''
      ));
    }
    return DanmakuCommentBatch(comments);
  }
}
