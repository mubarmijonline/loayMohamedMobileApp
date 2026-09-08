import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/features/_shared/models.dart';

/// `/student/content` arrives already sorted by
/// `(class_id, group_title, order_index, created_at)` and the client groups it
/// by walking that order once.
///
/// A regression here is quiet: the list still renders and every video still
/// plays, it just loses its course headings and section breaks and turns back
/// into the flat "Library" the app used to show.
void main() {
  ContentItem item(
    String id, {
    required String classId,
    required String group,
    int? order,
    String? className,
    bool watched = false,
  }) =>
      ContentItem.fromJson({
        '_id': id,
        'title': 'Video $id',
        'type': 'video',
        'class_id': classId,
        'class_name': className ?? 'Class $classId',
        'group_title': group,
        'order_index': order,
        'watched': watched,
      });

  group('grouping preserves server order', () {
    test('breaks a section on class_id and a group on group_title', () {
      final sections = ContentSection.group([
        item('1', classId: 'c1', group: 'Algebra', order: 1),
        item('2', classId: 'c1', group: 'Algebra', order: 2),
        item('3', classId: 'c1', group: 'Calculus', order: 1),
        item('4', classId: 'c2', group: 'Mechanics', order: 1),
      ]);

      expect(sections, hasLength(2));
      expect(sections[0].classId, 'c1');
      expect(sections[0].groups.map((g) => g.title), ['Algebra', 'Calculus']);
      expect(sections[0].groups[0].items, hasLength(2));
      expect(sections[1].classId, 'c2');
    });

    test('does not reorder within a group', () {
      // Deliberately non-monotonic order_index. The server decided; we render.
      final sections = ContentSection.group([
        item('a', classId: 'c1', group: 'Algebra', order: 2),
        item('b', classId: 'c1', group: 'Algebra', order: 1),
        item('c', classId: 'c1', group: 'Algebra', order: 3),
      ]);
      expect(
        sections.single.groups.single.items.map((i) => i.id),
        ['a', 'b', 'c'],
        reason: 'client-side sorting is what produced the old flat list',
      );
    });

    test('a group that reappears later opens a new section block', () {
      // Server order is authoritative even when it looks odd — if Algebra
      // appears twice, that is two runs, not one merged group.
      final sections = ContentSection.group([
        item('1', classId: 'c1', group: 'Algebra'),
        item('2', classId: 'c1', group: 'Calculus'),
        item('3', classId: 'c1', group: 'Algebra'),
      ]);
      expect(
        sections.single.groups.map((g) => g.title),
        ['Algebra', 'Calculus', 'Algebra'],
      );
    });
  });

  group('(Ungrouped)', () {
    test('renders as its own section, with no special case', () {
      // API_BRIEF §6: items with no group arrive as the literal string, never
      // null, so no branch is needed.
      final sections = ContentSection.group([
        item('1', classId: 'c1', group: '(Ungrouped)'),
        item('2', classId: 'c1', group: 'Algebra'),
      ]);
      expect(sections.single.groups.first.title, '(Ungrouped)');
      expect(sections.single.groups, hasLength(2));
    });

    test('a null group_title still lands somewhere', () {
      final sections = ContentSection.group([
        ContentItem.fromJson({
          '_id': 'x',
          'title': 'No group',
          'class_id': 'c1',
        }),
      ]);
      expect(sections.single.groups.single.title, '(Ungrouped)');
    });
  });

  group('the summary line', () {
    test('counts groups and videos, matching "4 groups • 10 videos"', () {
      final sections = ContentSection.group([
        item('1', classId: 'c1', group: 'A'),
        item('2', classId: 'c1', group: 'A'),
        item('3', classId: 'c1', group: 'B'),
        item('4', classId: 'c1', group: 'C'),
      ]);
      expect(sections.single.summary, '3 groups • 4 videos');
      expect(sections.single.videoCount, 4);
    });

    test('singularises correctly', () {
      final sections = ContentSection.group([
        item('1', classId: 'c1', group: 'A'),
      ]);
      expect(sections.single.summary, '1 group • 1 video');
    });
  });

  group('class header', () {
    test('takes its name and watched pill from /student/classes', () {
      final sections = ContentSection.group(
        [item('1', classId: 'c1', group: 'A')],
        classes: [
          StudentClass.fromJson({
            '_id': 'c1',
            'name': 'Mobile Trial — AS Edexcel',
            'video_total': 10,
            'video_watched': 6,
          }),
        ],
      );
      expect(sections.single.className, 'Mobile Trial — AS Edexcel');
      expect(sections.single.studentClass!.watchedLabel, '6/10 watched');
    });

    test('falls back to class_name when /student/classes is unavailable', () {
      // The header is a nicety; losing it must not empty the screen.
      final sections = ContentSection.group([
        item('1', classId: 'c1', group: 'A', className: 'Physics 12'),
      ]);
      expect(sections.single.className, 'Physics 12');
      expect(sections.single.studentClass, isNull);
    });
  });

  group('card fields', () {
    test('duration renders mm:ss like the portal badge', () {
      ContentItem withDuration(int s) => ContentItem.fromJson({
            '_id': 'x',
            'title': 't',
            'duration_seconds': s,
          });
      expect(withDuration(1326).durationLabel, '22:06');
      expect(withDuration(711).durationLabel, '11:51');
      expect(withDuration(1675).durationLabel, '27:55');
      expect(withDuration(3661).durationLabel, '1:01:01');
      expect(withDuration(0).durationLabel, '');
    });

    test('order_index drives the #n badge and is per group', () {
      final sections = ContentSection.group([
        item('1', classId: 'c1', group: 'Algebra', order: 1),
        item('2', classId: 'c1', group: 'Calculus', order: 1),
      ]);
      // Both are #1 — the badge is per group, not global.
      expect(sections.single.groups[0].items.single.orderIndex, 1);
      expect(sections.single.groups[1].items.single.orderIndex, 1);
    });

    test('thumbnail_url is carried through for the authenticated fetch', () {
      final c = ContentItem.fromJson({
        '_id': 'abc',
        'title': 't',
        'thumbnail_url': '/api/v1/student/content/abc/thumbnail',
      });
      expect(c.thumbnailUrl, '/api/v1/student/content/abc/thumbnail');
    });
  });

  test('an empty response produces no sections', () {
    expect(ContentSection.group(const []), isEmpty);
  });
}
