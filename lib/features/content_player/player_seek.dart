/// Seek arithmetic for the native player, kept out of the widgets so it can be
/// tested without a platform video player.
class PlayerSeek {
  PlayerSeek._();

  /// How far a skip button or a double tap moves.
  static const skip = Duration(seconds: 10);

  /// [current] moved by [delta], held inside the video. While [duration] is
  /// still unknown (zero), only the start is enforced.
  static Duration by(Duration current, Duration delta, Duration duration) {
    final t = current + delta;
    if (t < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && t > duration) return duration;
    return t;
  }

  /// A seek-bar position (0 to 1) as a time in the video. A drag that runs off
  /// either end is clamped.
  static Duration at(double fraction, Duration duration) => Duration(
        milliseconds:
            (fraction.clamp(0.0, 1.0) * duration.inMilliseconds).round(),
      );
}
