import 'package:flutter/services.dart';

/// Haptic + soft system click when an ISBN locks in.
class DetectionFeedback {
  DetectionFeedback._();

  static DateTime? _lastAt;

  /// Plays at most once every [cooldown] to avoid spam.
  static Future<void> playIsbnLocked({
    Duration cooldown = const Duration(milliseconds: 1500),
  }) async {
    final now = DateTime.now();
    if (_lastAt != null && now.difference(_lastAt!) < cooldown) return;
    _lastAt = now;

    await HapticFeedback.mediumImpact();
    await SystemSound.play(SystemSoundType.click);
    // Second lighter pulse feels like a soft "beep" confirmation.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.lightImpact();
  }
}
