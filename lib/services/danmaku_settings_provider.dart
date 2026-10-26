import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/danmaku_settings.dart';

class DanmakuSettingsProvider extends ChangeNotifier {
  DanmakuSettings _settings = const DanmakuSettings();
  bool _danmakuEnabled = true;
  
  DanmakuSettings get settings => _settings;
  bool get danmakuEnabled => _danmakuEnabled;
  
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _settings = DanmakuSettings(
        displayMode: prefs.getString('danmaku_mode') ?? 'auto',
        opacity: prefs.getDouble('danmaku_opacity') ?? 1.0,
        speed: prefs.getDouble('danmaku_speed') ?? 1.0,
        fontScale: prefs.getDouble('danmaku_font_scale') ?? 1.0,
        densityPct: prefs.getInt('danmaku_density_pct') ?? 100,
        antiOverlap: prefs.getBool('danmaku_anti_overlap') ?? true,
      );
      _danmakuEnabled = prefs.getBool('danmaku_enabled') ?? true;
    } catch (e) {
      debugPrint('[Danmaku] Load error: $e');
    }
    notifyListeners();
  }
  
  Future<void> toggle() async {
    _danmakuEnabled = !_danmakuEnabled;
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('danmaku_enabled', _danmakuEnabled);
    notifyListeners();
  }
  
  Future<void> saveDisplayMode(String m) async {
    _settings = _settings.copyWith(displayMode: m);
    (await SharedPreferences.getInstance()).setString('danmaku_mode', m);
    notifyListeners();
  }
  
  Future<void> saveOpacity(double o) async {
    _settings = _settings.copyWith(opacity: o);
    (await SharedPreferences.getInstance()).setDouble('danmaku_opacity', o);
    notifyListeners();
  }
  
  Future<void> saveSpeed(double s) async {
    _settings = _settings.copyWith(speed: s);
    (await SharedPreferences.getInstance()).setDouble('danmaku_speed', s);
    notifyListeners();
  }
  
  Future<void> saveFontScale(double f) async {
    _settings = _settings.copyWith(fontScale: f);
    (await SharedPreferences.getInstance()).setDouble('danmaku_font_scale', f);
    notifyListeners();
  }
  
  Future<void> saveDensityPct(int d) async {
    _settings = _settings.copyWith(densityPct: d);
    (await SharedPreferences.getInstance()).setInt('danmaku_density_pct', d);
    notifyListeners();
  }
  
  Future<void> saveAntiOverlap(bool v) async {
    _settings = _settings.copyWith(antiOverlap: v);
    (await SharedPreferences.getInstance()).setBool('danmaku_anti_overlap', v);
    notifyListeners();
  }
}

extension on DanmakuSettings {
  DanmakuSettings copyWith({
    String? displayMode,
    double? opacity,
    double? speed,
    double? fontScale,
    int? densityPct,
    bool? antiOverlap,
  }) => DanmakuSettings(
    displayMode: displayMode ?? this.displayMode,
    opacity: opacity ?? this.opacity,
    speed: speed ?? this.speed,
    fontScale: fontScale ?? this.fontScale,
    densityPct: densityPct ?? this.densityPct,
    antiOverlap: antiOverlap ?? this.antiOverlap,
  );
}
