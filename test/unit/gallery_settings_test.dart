// s329 Feature 6 regression pins: GallerySettings.effectiveRowHeight must scale with viewport
// when autoResizeRowHeight is true, and remain fixed when false. Bounds [20, 400] enforced both
// ways. These pins guard the user-reported "tile jump-back when last photo wraps to new row"
// symptom (2026-05-30) — the fix relies on viewport-derived targetH in JustifiedGrid via this
// helper, so any regression here would re-introduce the visual jump.
import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/features/files/gallery_settings.dart';

void main() {
  group('GallerySettings.effectiveRowHeight — Feature 6', () {
    test('auto ON: scales with viewport width (viewport / 5)', () {
      final s = GallerySettings(autoResizeRowHeight: true, justifiedRowHeight: 200);
      expect(s.effectiveRowHeight(1000), 200, reason: '1000/5=200');
      expect(s.effectiveRowHeight(600), 120, reason: '600/5=120');
      expect(s.effectiveRowHeight(1500), 300, reason: '1500/5=300');
      expect(s.effectiveRowHeight(2000), 400, reason: '2000/5=400 (within bounds)');
    });

    test('auto ON: clamps to min 20px when viewport tiny', () {
      final s = GallerySettings(autoResizeRowHeight: true, justifiedRowHeight: 200);
      expect(s.effectiveRowHeight(50), 20, reason: '50/5=10 → clamp to 20');
      expect(s.effectiveRowHeight(0), 20, reason: '0 → clamp to min');
    });

    test('auto ON: clamps to max 400px when viewport huge', () {
      final s = GallerySettings(autoResizeRowHeight: true, justifiedRowHeight: 200);
      expect(s.effectiveRowHeight(3000), 400, reason: '3000/5=600 → clamp to max 400');
      expect(s.effectiveRowHeight(10000), 400, reason: 'extreme → clamp');
    });

    test('auto OFF: returns fixed slider value regardless of viewport', () {
      final s = GallerySettings(autoResizeRowHeight: false, justifiedRowHeight: 150);
      expect(s.effectiveRowHeight(600), 150);
      expect(s.effectiveRowHeight(1500), 150);
      expect(s.effectiveRowHeight(3000), 150);
    });

    test('auto OFF: still clamps slider value into [20, 400]', () {
      // Even if persisted state somehow has out-of-range value (e.g. migration from older version),
      // effectiveRowHeight enforces the new bounds.
      final tooSmall = GallerySettings(autoResizeRowHeight: false, justifiedRowHeight: 5);
      expect(tooSmall.effectiveRowHeight(1000), 20);
      final tooBig = GallerySettings(autoResizeRowHeight: false, justifiedRowHeight: 999);
      expect(tooBig.effectiveRowHeight(1000), 400);
    });

    test('bounds constants match user 2026-05-30 request (min 20px, max 400px)', () {
      expect(GallerySettings.minRowHeight, 20, reason: 'user wymaga "min. 20px"');
      expect(GallerySettings.maxRowHeight, 400, reason: 'extended from prev 320 for wide monitors');
    });

    test('default ctor: autoResizeRowHeight defaults to true', () {
      final s = GallerySettings();
      expect(s.autoResizeRowHeight, isTrue, reason: 'default ON eliminates the jump-back symptom by default for new users');
    });
  });
}
