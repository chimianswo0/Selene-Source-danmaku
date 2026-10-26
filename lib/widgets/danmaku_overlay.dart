import 'dart:async';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../models/danmaku_comment.dart';
import '../models/danmaku_settings.dart';
import '../models/danmaku_render_settings.dart';
import '../services/danmaku_settings_provider.dart';

/// Simple danmaku overlay using positioned Text widgets
/// This avoids the Metal texture layer issue with canvas_danmaku
class DanmakuOverlay extends StatefulWidget {
  final List<DanmakuComment> comments;
  final DanmakuRenderSettings settings;
  final Duration videoPosition;
  final bool enabled;
  final Widget child;
  
  const DanmakuOverlay({
    super.key,
    required this.comments,
    required this.settings,
    required this.videoPosition,
    required this.enabled,
    required this.child,
  });

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<_DanmakuLine> _lines = [];
  Timer? _timer;
  int _lastAddedIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 6));
    _controller.addListener(_onTick);
    if (widget.enabled && widget.comments.isNotEmpty) _start();
  }

  @override
  void didUpdateWidget(DanmakuOverlay old) {
    super.didUpdateWidget(old);
    if (widget.comments != old.comments) {
      _lastAddedIndex = 0;
      _lines = [];
    }
    if (widget.enabled && !old.enabled) _start();
    else if (!widget.enabled && old.enabled) { _timer?.cancel(); _controller.stop(); }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !widget.enabled) return;
      final now = widget.videoPosition.inMilliseconds;
      // Add comments that are due
      for (int i = _lastAddedIndex; i < widget.comments.length; i++) {
        final c = widget.comments[i];
        if (c.timeMs <= now && c.timeMs > now - 2000) {
          _addComment(c, i);
          _lastAddedIndex = i + 1;
        }
      }
    });
  }

  void _addComment(DanmakuComment c, int index) {
    if (!mounted) return;
    setState(() {
      // Find a lane that's available (not occupied in the last 5 seconds)
      int lane = -1;
      for (int i = 0; i < _lines.length && i < 8; i++) {
        final line = _lines[i];
        if (c.timeMs - line.endTimeMs > 5000) {
          lane = i;
          break;
        }
      }
      if (lane == -1) {
        if (_lines.length < 8) lane = _lines.length;
        else return; // Too many lines
      }
      while (_lines.length <= lane) _lines.add(_DanmakuLine());
      _lines[lane] = _DanmakuLine(
        comment: c,
        startTimeMs: c.timeMs,
        endTimeMs: c.timeMs + 5000,
      );
    });
  }

  void _onTick() {
    if (!mounted) return;
    final progress = _controller.value;
    // Update line positions based on animation progress
    // This is handled by the build method
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.enabled && _lines.isNotEmpty)
          Positioned.fill(
            child: CustomPaint(
              painter: _DanmakuPainter(
                lines: _lines,
                progress: _controller.value,
                settings: widget.settings,
              ),
            ),
          ),
      ],
    );
  }
}

class _DanmakuLine {
  final DanmakuComment comment;
  final int startTimeMs;
  final int endTimeMs;
  _DanmakuLine({
    this.comment = const DanmakuComment(timeMs: 0, mode: 0, color: 0xFFFFFF, content: ''),
    this.startTimeMs = 0,
    this.endTimeMs = 0,
  });
}

class _DanmakuPainter extends CustomPainter {
  final List<_DanmakuLine> lines;
  final double progress;
  final DanmakuRenderSettings settings;

  _DanmakuPainter({
    required this.lines,
    required this.progress,
    required this.settings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final elapsed = progress * 6000; // 6 second animation
      final commentElapsed = elapsed - (line.startTimeMs - (line.startTimeMs));
      
      final startX = size.width;
      final endX = -line.comment.content.length * 10 * settings.fontScale;
      final x = startX + (endX - startX) * (commentElapsed / 6000);
      final y = 30.0 + i * 28.0;
      
      if (x > -500 && x < size.width + 50) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: line.comment.content,
            style: TextStyle(
              color: Color(line.comment.color),
              fontSize: 14 * settings.fontScale,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: size.width);
        textPainter.paint(canvas, Offset(x, y));
      }
    }
  }

  @override
  bool shouldRepaint(_DanmakuPainter old) => true;
}

/// Danmaku debug logger
class DanmakuDebugLogger {
  static final List<String> _logs = [];
  static const _max = 100;
  static bool _init = false;
  
  static void add(String m) {
    if (!_init) {
      _init = true;
      _logs.add('[Danmaku] === Initialized ===');
    }
    _logs.add('[${DateTime.now().toString().substring(11, 19)}] $m');
    if (_logs.length > _max) _logs.removeAt(0);
  }
  
  static List<String> get logs => List.unmodifiable(_logs);
}

/// Danmaku debug overlay panel
class DanmakuDebugOverlay extends StatefulWidget {
  final VoidCallback onClose;
  const DanmakuDebugOverlay({super.key, required this.onClose});
  
  @override
  State<DanmakuDebugOverlay> createState() => _DanmakuDebugOverlayState();
}

class _DanmakuDebugOverlayState extends State<DanmakuDebugOverlay> {
  final _ctrl = TextEditingController();
  
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _search() async {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    DanmakuDebugLogger.add('[Danmaku] Manual search: $v');
    
    if (v.toUpperCase().startsWith('BV')) {
      try {
        final r = await http.get(
          Uri.parse('https://api.bilibili.com/x/player/pagelist?bvid=${v.toUpperCase()}'),
          headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://www.bilibili.com/'},
        ).timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body);
          final pages = (j['data'] as List<dynamic>?) ?? [];
          DanmakuDebugLogger.add('[Danmaku] BV $v: ${pages.length} eps');
          if (pages.isNotEmpty) {
            final p = pages.first as Map<String, dynamic>;
            final cid = p['cid'];
            final part = p['part'] as String? ?? 'P1';
            if (cid != null) await _loadByCid(cid, part);
          }
        }
      } catch (e) { DanmakuDebugLogger.add('[Danmaku] BV error: $e'); }
    } else if (v.toLowerCase().startsWith('ep')) {
      final epId = int.tryParse(v.substring(2));
      if (epId != null) {
        try {
          final r = await http.get(
            Uri.parse('https://api.bilibili.com/pgc/view/web/ep/list?ep_id=$epId'),
            headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://www.bilibili.com/'},
          ).timeout(const Duration(seconds: 10));
          if (r.statusCode == 200) {
            final j = jsonDecode(r.body);
            final result = (j['result'] as Map<String, dynamic>?) ?? {};
            final eps = (result['episodes'] as List<dynamic>?) ?? [];
            for (final ep in eps) {
              final em = ep as Map<String, dynamic>;
              if ((em['ep_id'] as int?) == epId) {
                final cid = em['cid'];
                final title = (em['long_title'] ?? em['title'] ?? 'Ep$epId')
                    .replaceAll(RegExp(r'<[^>]*>'), '');
                DanmakuDebugLogger.add('[Danmaku] EpID $epId: $title, cid=$cid');
                if (cid != null) await _loadByCid(cid, title);
                return;
              }
            }
            DanmakuDebugLogger.add('[Danmaku] EpID $epId not found');
          }
        } catch (e) { DanmakuDebugLogger.add('[Danmaku] EpID error: $e'); }
      }
    } else {
      DanmakuDebugLogger.add('[Danmaku] Unknown format: $v');
    }
  }

  Future<void> _loadByCid(dynamic cid, String title) async {
    try {
      final r = await http.get(
        Uri.parse('https://api.bilibili.com/x/v1/dm/list.so?oid=$cid'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://www.bilibili.com/'},
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        final inflate = Inflate(r.bodyBytes);
        final xml = utf8.decode(inflate.output.getBytes());
        final comments = DanmakuCommentBatch.fromXml(xml);
        DanmakuDebugLogger.add('[Danmaku] Loaded ${comments.comments.length} for $title');
        if (comments.comments.isEmpty) DanmakuDebugLogger.add('[Danmaku] WARNING: 0 danmaku');
      } else {
        DanmakuDebugLogger.add('[Danmaku] XML status: ${r.statusCode}');
      }
    } catch (e) { DanmakuDebugLogger.add('[Danmaku] XML error: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final logs = DanmakuDebugLogger.logs;
    return Positioned(top: 10, right: 10, child: Container(
      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 250),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1a1a1a).withOpacity(0.95) : Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(children: [
            const Icon(Icons.bug_report, size: 14, color: Colors.orange),
            const SizedBox(width: 6),
            Text('弹幕调试 (${logs.length})', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const Spacer(),
            GestureDetector(onTap: () => setState(() {}), child: const Icon(Icons.refresh, size: 14, color: Colors.white54)),
            const SizedBox(width: 4),
            GestureDetector(onTap: widget.onClose, child: const Icon(Icons.close, size: 14, color: Colors.white54)),
          ]),
        ),
        // Search input
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Row(children: [
          Expanded(child: TextField(
            controller: _ctrl,
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.white70),
            decoration: const InputDecoration(
              hintText: '输入BV号或ep号 (如 BV1xx4c12345 或 ep437500)',
              hintStyle: TextStyle(fontSize: 10, color: Colors.grey),
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              border: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey), borderRadius: BorderRadius.all(Radius.circular(4))),
            ),
            onSubmitted: (_) => _search(),
          )),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _search,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const BoxDecoration(color: Color(0xFF1976d2), borderRadius: BorderRadius.all(Radius.circular(4))),
              child: const Text('搜索', style: TextStyle(fontSize: 10, color: Colors.white)),
            ),
          ),
        ])),
        // Logs
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (logs.isEmpty) const Text('暂无日志', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ...logs.reversed.map((l) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(l, style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.white70)),
            )),
          ]),
        )),
      ]),
    ));
  }
}

/// Danmaku settings panel
class DanmakuSettingsPanel extends StatefulWidget {
  final VoidCallback onClose;
  const DanmakuSettingsPanel({super.key, required this.onClose});
  
  @override
  State<DanmakuSettingsPanel> createState() => _DanmakuSettingsPanelState();
}

class _DanmakuSettingsPanelState extends State<DanmakuSettingsPanel> {
  @override
  Widget build(BuildContext context) {
    final p = context.watch<DanmakuSettingsProvider>();
    final s = p.settings;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(bottom: 60, right: 10, child: Container(
      width: 300, constraints: const BoxConstraints(maxHeight: 380),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1e1e1e) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF252525) : Colors.grey[100],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            const Icon(Icons.dns, size: 18, color: Colors.lightBlueAccent),
            const SizedBox(width: 8),
            Text('弹幕设置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: dark ? Colors.white : Colors.black)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: widget.onClose,
              color: dark ? Colors.white54 : Colors.black54,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
        // Settings
        SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _section(context, '模式', ['关闭', '手动', '自动'].map((m) =>
              _chip(context, m, s.displayMode == m.toLowerCase(), () => p.saveDisplayMode(m.toLowerCase()))
            ).toList()),
            _section(context, '不透明度', DanmakuRenderSettings.opacities.map((o) =>
              _chip(context, '${(o*100).toInt()}%', (s.opacity-o).abs()<0.01, () => p.saveOpacity(o))
            ).toList()),
            _section(context, '速度', DanmakuRenderSettings.speeds.map((sp) =>
              _chip(context, '${sp}x', (s.speed-sp).abs()<0.01, () => p.saveSpeed(sp))
            ).toList()),
            _section(context, '字体', DanmakuRenderSettings.fontScales.map((fs) =>
              _chip(context, '${(fs*100).toInt()}%', (s.fontScale-fs).abs()<0.01, () => p.saveFontScale(fs))
            ).toList()),
            SwitchListTile(
              title: const Text('防重叠'),
              subtitle: const Text('弹幕过多时自动错开'),
              value: s.antiOverlap,
              onChanged: (v) => p.saveAntiOverlap(v),
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.lightBlueAccent,
            ),
          ]),
        ),
      ]),
    ));
  }

  Widget _section(BuildContext c, String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: dark ? Colors.white70 : Colors.black87)),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, children: children),
    ]),
  );

  late final bool dark = Theme.of(context).brightness == Brightness.dark;

  Widget _chip(BuildContext c, String label, bool sel, VoidCallback tap) {
    return InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? (dark ? const Color(0xFF1565c0) : const Color(0xFF1976d2)) : (dark ? const Color(0xFF333333) : Colors.grey[200]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: TextStyle(color: sel ? Colors.white : (dark ? Colors.white70 : Colors.black87), fontSize: 11)),
      ),
    );
  }
}
