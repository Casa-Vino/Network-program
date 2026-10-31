import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the device (screen + radio) awake during active transfers so power
/// saving can't pause them. Ref-counted: nested/overlapping transfers each
/// acquire/release, and the wakelock only drops when the last one is done.
class KeepAwake {
  static int _count = 0;

  static Future<void> acquire() async {
    _count++;
    if (_count == 1) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }
  }

  static Future<void> release() async {
    if (_count > 0) _count--;
    if (_count == 0) {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }
}
