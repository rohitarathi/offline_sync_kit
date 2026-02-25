import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the Flutter app is currently in the foreground.
///
/// The flag is persisted in [SharedPreferences] so that WorkManager background
/// isolates (which run in a separate Dart VM) can read it.
///
/// ### Setup
///
/// Call [initialize] once inside `main()` before `runApp()`:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   AppLifecycleObserver.initialize();
///   runApp(const MyApp());
/// }
/// ```
class AppLifecycleObserver with WidgetsBindingObserver {
  static const String _prefKey = '_osk_is_foreground';

  static final AppLifecycleObserver _instance = AppLifecycleObserver._();
  AppLifecycleObserver._();

  static bool _registered = false;

  /// Registers the singleton lifecycle observer.
  /// Safe to call multiple times — only registers once.
  static void initialize() {
    if (_registered) return;
    WidgetsBinding.instance.addObserver(_instance);
    _registered = true;
    debugPrint('[OfflineSyncKit] AppLifecycleObserver registered');
  }

  /// Returns `true` if the app is currently in the foreground.
  ///
  /// Can be called from any isolate, including WorkManager background tasks.
  static Future<bool> isAppForeground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Critical: picks up writes from the main isolate.
    return prefs.getBool(_prefKey) ?? false;
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    final prefs = await SharedPreferences.getInstance();

    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        // App is visible — tell background isolates to pause.
        await prefs.setBool(_prefKey, true);
        debugPrint('[OfflineSyncKit] App foreground → sync paused');
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App is not visible — background sync may proceed.
        await prefs.setBool(_prefKey, false);
        debugPrint('[OfflineSyncKit] App background → sync allowed');
        break;
    }
  }
}
