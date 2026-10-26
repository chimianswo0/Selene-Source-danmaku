import 'dart:async';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/danmaku_comment.dart';

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
