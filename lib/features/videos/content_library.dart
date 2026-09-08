import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_palette.dart';
import '../../core/design/app_spacing.dart';
import '../../core/providers.dart';
import '../_shared/models.dart';
import '../providers.dart';

/// The video library.
///
/// ## Why this is a dense list and not the portal's card grid
///
/// The portal has a wide viewport and real poster images, so large 16:9 cards
/// read well there. On a phone the same layout fitted roughly one and a half
/// videos on screen, and — because the deployed API sends no `thumbnail_url`
/// yet — most of that height was an empty black rectangle. A column of large
/// placeholders is worse than a list.
///
/// So: one compact row per video, poster on the left at a fixed 96x54. A real
/// thumbnail drops into the same box when the backend starts sending them;
/// until then the tile is a small play glyph rather than a large void. About
/// six videos now fit where one and a half did.
///
/// The information is the same as the portal card — `#n`, title, group,
/// duration, watched — laid out for a narrow screen.
class ContentLibrary extends ConsumerWidget {
  const ContentLibrary({
    super.key,
    required this.sections,
    required this.onOpen,
    this.emptyState,
    this.showClassHeader = true,
  });

  final List<ContentSection> sections;
  final void Function(ContentItem item) onOpen;
  final Widget? emptyState;

  /// Whether to draw the class name above each section.
  ///
  /// False when the host screen already shows it. The subject detail screen
  /// has the class name in its header, and repeating it immediately below is
  /// noise.
  final bool showClassHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sections.isEmpty) return emptyState ?? const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections)
          _Section(
            section: section,
            onOpen: onOpen,
            showClassHeader: showClassHeader,
          ),
      ],
    );
  }
}

class _Section extends ConsumerStatefulWidget {
  const _Section({
    required this.section,
    required this.onOpen,
    required this.showClassHeader,
  });

  final ContentSection section;
  final void Function(ContentItem item) onOpen;
  final bool showClassHeader;

  @override
  ConsumerState<_Section> createState() => _SectionState();
}

class _SectionState extends ConsumerState<_Section> {
  String get _key => 'videos.collapsed.${widget.section.classId}';
  late bool _collapsed;

  @override
  void initState() {
    super.initState();
    _collapsed = ref.read(kvCacheProvider).getBool(_key);
  }

  void _toggle() {
    setState(() => _collapsed = !_collapsed);
    ref.read(kvCacheProvider).setBool(_key, _collapsed);
  }

  /// Per-group collapse, persisted like the class-level one. Keyed on class
  /// and group so two classes with an "Algebra" group stay independent.
  String _groupKey(String title) =>
      'videos.group.${widget.section.classId}.$title';

  bool _isGroupCollapsed(String title) =>
      ref.read(kvCacheProvider).getBool(_groupKey(title));

  void _toggleGroup(String title) {
    final next = !_isGroupCollapsed(title);
    ref.read(kvCacheProvider).setBool(_groupKey(title), next);
    setState(() {});
  }

  /// A single group called "(Ungrouped)" is not worth a heading.
  ///
  /// It is the API's placeholder for "the teacher did not file these", so
  /// showing it as a section title puts an implementation detail in front of
  /// the student. Real groups render normally.
  bool get _showGroupHeadings {
    final g = widget.section.groups;
    if (g.length > 1) return true;
    return g.isNotEmpty && g.first.title != '(Ungrouped)';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.section;
    final cls = s.studentClass;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showClassHeader) ...[
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.className,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.summary,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (cls != null && cls.videoTotal > 0)
                    _WatchedPill(
                      watched: cls.videoWatched,
                      total: cls.videoTotal,
                    ),
                  Icon(
                    _collapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    color: context.palette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (!_collapsed)
          for (final group in s.groups) ...[
            if (_showGroupHeadings)
              _GroupHeading(
                group: group,
                collapsed: _isGroupCollapsed(group.title),
                onToggle: () => _toggleGroup(group.title),
              ),
            if (!_showGroupHeadings || !_isGroupCollapsed(group.title))
              for (final item in group.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _VideoRow(
                    item: item,
                    onTap: () => widget.onOpen(item),
                    // The group name is already the heading above, so printing
                    // it on every row underneath was pure repetition — and it
                    // was what pushed the meta line past the card edge.
                    showGroup: !_showGroupHeadings,
                  ),
                ),
            const SizedBox(height: AppSpacing.xs),
          ],
      ],
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({
    required this.group,
    required this.collapsed,
    required this.onToggle,
  });

  final ContentGroup group;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final n = group.items.length;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, AppSpacing.sm, 2, AppSpacing.sm),
        child: Row(
          children: [
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                group.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.palette.textPrimary,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$n',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Divider(height: 1, color: context.palette.divider)),
          ],
        ),
      ),
    );
  }
}

/// One video. Poster left, meta right, chevron at the end.
class _VideoRow extends StatelessWidget {
  const _VideoRow({
    required this.item,
    required this.onTap,
    this.showGroup = true,
  });

  final ContentItem item;
  final VoidCallback onTap;

  /// Whether to repeat the group name in the meta line. False when a group
  /// heading is already shown above these rows.
  final bool showGroup;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.palette.divider),
          ),
          child: Row(
            children: [
              _Poster(item: item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.orderIndex != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 1, right: 6),
                            child: Text(
                              '#${item.orderIndex}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              color: context.palette.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _MetaLine(item: item, showGroup: showGroup),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.palette.textHint,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Duration, group and watched on one quiet line, rather than a row of chips.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.item, this.showGroup = true});

  final ContentItem item;
  final bool showGroup;

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];

    if (item.durationLabel.isNotEmpty) {
      parts.add(_meta(context, Icons.schedule_rounded, item.durationLabel));
    }
    // When the group is a real one it is already the heading above, so it is
    // only repeated here if it is not being shown as a heading.
    if (showGroup &&
        item.groupTitle != null &&
        item.groupTitle != '(Ungrouped)') {
      parts.add(_meta(context, Icons.folder_outlined, item.groupTitle!));
    }

    // Wrap, not Row: a long title plus duration plus "Watched" cannot always
    // fit one line on a narrow phone, and a Row overflows rather than
    // reflowing. This is what produced the 1.1px overflow stripe.
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...parts,
        if (item.watched)
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 13,
                color: AppColors.success,
              ),
              SizedBox(width: 4),
              Text(
                'Watched',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _meta(BuildContext context, IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: context.palette.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: context.palette.textSecondary,
            ),
          ),
        ],
      );
}

/// 96x54 poster.
///
/// `thumbnail_url` is token-protected, so the bytes come through the
/// authenticated client — `Image.network` cannot attach a bearer token and
/// would show a broken image on every row.
///
/// The deployed API sends no thumbnails yet, so the play-glyph tile is the
/// common case rather than a rare fallback, and is sized to look deliberate.
class _Poster extends ConsumerWidget {
  const _Poster({required this.item});

  final ContentItem item;

  static const double _w = 96;
  static const double _h = 54;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget frame(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: SizedBox(width: _w, height: _h, child: child),
        );

    final url = item.thumbnailUrl;
    if (url == null || url.isEmpty) return frame(const _GlyphTile());

    final bytes = ref.watch(contentThumbnailProvider(item.id));
    return frame(
      bytes.when(
        loading: () => const _GlyphTile(),
        error: (_, __) => const _GlyphTile(),
        data: (data) => data == null
            ? const _GlyphTile()
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true),
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 26,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GlyphTile extends StatelessWidget {
  const _GlyphTile();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: context.palette.surfaceTinted,
        child: Center(
          child: Icon(
            Icons.play_arrow_rounded,
            size: 26,
            color: AppColors.primary,
          ),
        ),
      );
}

class _WatchedPill extends StatelessWidget {
  const _WatchedPill({required this.watched, required this.total});

  final int watched;
  final int total;

  @override
  Widget build(BuildContext context) {
    final done = total > 0 && watched >= total;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: done
            ? AppColors.success.withValues(alpha: 0.12)
            : context.palette.surfaceTinted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        '$watched/$total',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: done ? AppColors.success : AppColors.primary,
        ),
      ),
    );
  }
}
