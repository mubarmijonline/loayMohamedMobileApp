import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/features/content_player/player_seek.dart';

void main() {
  const lesson = Duration(minutes: 22, seconds: 6);

  group('skip', () {
    test('moves 10 s either way', () {
      expect(
        PlayerSeek.by(const Duration(seconds: 30), PlayerSeek.skip, lesson),
        const Duration(seconds: 40),
      );
      expect(
        PlayerSeek.by(const Duration(seconds: 30), -PlayerSeek.skip, lesson),
        const Duration(seconds: 20),
      );
    });

    test('never goes before the start', () {
      expect(
        PlayerSeek.by(const Duration(seconds: 4), -PlayerSeek.skip, lesson),
        Duration.zero,
      );
    });

    test('never goes past the end', () {
      expect(
        PlayerSeek.by(
          lesson - const Duration(seconds: 3),
          PlayerSeek.skip,
          lesson,
        ),
        lesson,
      );
    });

    test('before the duration is known, only the start is enforced', () {
      expect(
        PlayerSeek.by(
          const Duration(seconds: 5),
          PlayerSeek.skip,
          Duration.zero,
        ),
        const Duration(seconds: 15),
      );
    });
  });

  group('seek-bar position to time', () {
    test('maps both ends and the middle', () {
      expect(PlayerSeek.at(0, lesson), Duration.zero);
      expect(PlayerSeek.at(1, lesson), lesson);
      expect(PlayerSeek.at(0.5, lesson), const Duration(milliseconds: 663000));
    });

    test('clamps a drag that runs off either end', () {
      expect(PlayerSeek.at(-0.2, lesson), Duration.zero);
      expect(PlayerSeek.at(1.3, lesson), lesson);
    });
  });
}
