import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import '../models/danmaku_media.dart';
import '../models/danmaku_episode.dart';
import '../models/danmaku_comment.dart';
import '../widgets/danmaku_overlay.dart';

class DanmakuService {
  static String? _cookie;
  
  static Map<String, String> get _headers {
    return _cookie != null
        ? {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
           'Referer': 'https://www.bilibili.com/',
           'Cookie': _cookie!}
        : {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
           'Referer': 'https://www.bilibili.com/'};
  }
  
  static Future<void> _initCookie() async {
    if (_cookie != null) return;
    try {
      await http.get(Uri.parse('https://www.bilibili.com'), headers: _headers);
      final resp = await http.get(
        Uri.parse('https://api.bilibili.com/x/frontend/finger/spi'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        final data = (json['data'] as Map<String, dynamic>?) ?? {};
        final b3 = data['b_3'] as String? ?? '';
        final b4 = data['b_4'] as String? ?? '';
        if (b3.isNotEmpty || b4.isNotEmpty) {
          _cookie = 'buvid3=$b3; buvid4=$b4';
          DanmakuDebugLogger.add('[Danmaku] Cookie initialized');
        }
      }
    } catch (e) {
      DanmakuDebugLogger.add('[Danmaku] Cookie init error: $e');
    }
  }
  
  static Future<List<DanmakuMedia>> searchMedia(String title, {int? year}) async {
    await _initCookie();
    final results = <DanmakuMedia>[];
    try {
      final resp = await http.get(
        Uri.parse(
          'https://api.bilibili.com/x/web-interface/wbi/search/all/v2?'
          'keyword=${Uri.encodeComponent(title)}&platform=pc&duration=0&order=totalrank',
        ),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      
      if (resp.statusCode != 200) {
        DanmakuDebugLogger.add('[Danmaku] Search API status: ${resp.statusCode}');
        return results;
      }
      
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = (json['data'] as Map<String, dynamic>?) ?? {};
      final resultsList = (data['result'] as List<dynamic>?) ?? [];
      
      for (final item in resultsList) {
        final map = item as Map<String, dynamic>;
        final resultType = (map['result_type'] as String?) ?? '';
        final innerData = (map['data'] as List<dynamic>?) ?? [];
        
        // Match bangumi or feitian types
        if (resultType == 'media_bangumi' || resultType == 'media_ft') {
          for (final i in innerData) {
            final im = i as Map<String, dynamic>;
            final sid = im['season_id'] as int?;
            if (sid != null && sid > 0) {
              final t = (im['title'] as String? ?? '')
                  .replaceAll(RegExp(r'<[^>]*>'), '')
                  .trim();
              DanmakuDebugLogger.add('[Danmaku] Found media: $t (sid:$sid)');
              results.add(DanmakuMedia(
                provider: 'bilibili',
                mediaId: 'ss:$sid',
                title: t,
                type: 'tvseries',
                year: year,
              ));
              return results; // Return first match
            }
          }
        }
      }
      DanmakuDebugLogger.add('[Danmaku] No matching bangumi found for: $title');
    } catch (e) {
      DanmakuDebugLogger.add('[Danmaku] Search error: $e');
    }
    return results;
  }
  
  static Future<List<DanmakuEpisode>> getEpisodes(DanmakuMedia media) async {
    final episodes = <DanmakuEpisode>[];
    try {
      if (media.mediaId.startsWith('ss:')) {
        final sid = media.mediaId.substring(3);
        final resp = await http.get(
          Uri.parse('https://api.bilibili.com/pgc/view/web/ep/list?season_id=$sid'),
          headers: _headers,
        ).timeout(const Duration(seconds: 10));
        
        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body) as Map<String, dynamic>;
          final result = (json['result'] as Map<String, dynamic>?) ?? {};
          final eps = (result['episodes'] as List<dynamic>?) ?? [];
          DanmakuDebugLogger.add('[Danmaku] Episodes found: ${eps.length}');
          
          for (var i = 0; i < eps.length; i++) {
            final ep = eps[i] as Map<String, dynamic>;
            final cid = ep['cid'] as int?;
            if (cid != null && cid > 0) {
              final title = ((ep['long_title'] as String? ?? ep['title'] ?? '')
                  .replaceAll(RegExp(r'<[^>]*>'), '')
                  .trim());
              episodes.add(DanmakuEpisode(
                provider: 'bilibili',
                episodeIndex: ep['ep_id'] ?? i + 1,
                episodeId: '$cid',
                title: title,
              ));
            }
          }
        }
      }
    } catch (e) {
      DanmakuDebugLogger.add('[Danmaku] Episodes error: $e');
    }
    return episodes;
  }
  
  static Future<DanmakuCommentBatch> getComments(DanmakuEpisode episode) async {
    try {
      final cid = episode.episodeId;
      DanmakuDebugLogger.add('[Danmaku] Loading ep: ${episode.title} (cid: $cid)');
      
      final resp = await http.get(
        Uri.parse('https://api.bilibili.com/x/v1/dm/list.so?oid=$cid'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        // Raw deflate (not gzip) - use Inflate
        final inflate = Inflate(resp.bodyBytes);
        final xml = utf8.decode(inflate.output.getBytes());
        final batch = DanmakuCommentBatch.fromXml(xml);
        DanmakuDebugLogger.add('[Danmaku] Loaded ${batch.comments.length} danmaku (raw:${resp.bodyBytes.length} xml:${xml.length})');
        return batch;
      } else {
        DanmakuDebugLogger.add('[Danmaku] XML status: ${resp.statusCode}');
        return const DanmakuCommentBatch([]);
      }
    } catch (e) {
      DanmakuDebugLogger.add('[Danmaku] Comments error: $e');
      return const DanmakuCommentBatch([]);
    }
  }
}
