import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/components.dart';
import '../../core/error/failures.dart';
import '../_shared/models.dart';
import '../content_player/secure_stream_player.dart';
import '../providers.dart';
import '../../core/design/app_palette.dart';

/// Lists every Cloudflare Stream video assigned to a class, grouped by the
/// lesson's `group_title`. Each group renders a horizontal carousel of
/// "part" cards. Tapping a part opens the full-screen [SecureStreamPlayer]
/// with the remaining parts queued as Up Next.
class ClassVideosScreen extends ConsumerStatefulWidget {
  const ClassVideosScreen({
    super.key,
    required this.classId,
    this.fallbackTitle,
    this.highlightGroup,
    this.embedded = false,
  });

  /// Backend class id (same value used for `/api/student/classes/<id>/videos`).
  final String classId;

  /// Shown in the app bar while the class payload is still loading.
  final String? fallbackTitle;

  /// When deep-linked from a push notification, the group title to scroll
  /// to and briefly highlight.
  final String? highlightGroup;

  /// True when used inside an existing screen/tab (no own Scaffold/AppBar).
  final bool embedded;

  @override
  ConsumerState<ClassVideosScreen> createState() => _ClassVideosScreenState();
}

class _ClassVideosScreenState extends ConsumerState<ClassVideosScreen> {
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _groupKeys = {};
  String? _flashGroup;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToHighlightedGroup(List<VideoGroup> groups) {
    final target = widget.highlightGroup;
    if (target == null || target.isEmpty || _flashGroup != null) return;
    final match = groups.firstWhere(
      (g) => g.title == target,
      orElse: () => const VideoGroup(title: '', videos: []),
    );
    if (match.title.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _groupKeys[match.title];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          alignment: 0.05,
        );
      }
      setState(() => _flashGroup = match.title);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _flashGroup = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(classVideosProvider(widget.classId));
    final content = async.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: List.generate(
          3,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.md),
            child: SkeletonBox(height: 180, radius: AppRadius.lg),
          ),
        ),
      ),
      error: (e, _) => ErrorStateView(
        message: e is AppFailure ? e.message : e.toString(),
        onRetry: () => ref.invalidate(classVideosProvider(widget.classId)),
      ),
      data: (data) {
        if (data.groups.isEmpty) {
          return const EmptyState(
            title: 'No videos yet',
            message:
                'Videos assigned to this class will appear here. Pull to refresh.',
            icon: Icons.video_library_outlined,
          );
        }
        _scrollToHighlightedGroup(data.groups);
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(classVideosProvider(widget.classId));
            await ref.read(classVideosProvider(widget.classId).future);
          },
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: data.groups.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.lg),
            itemBuilder: (_, i) {
              final g = data.groups[i];
              final key = _groupKeys.putIfAbsent(g.title, GlobalKey.new);
              return _GroupSection(
                key: key,
                group: g,
                highlighted: _flashGroup == g.title,
                onPlay: (video) => _openPlayer(g, video),
              );
            },
          ),
        );
      },
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          async.valueOrNull?.classTitle.isNotEmpty == true
              ? async.value!.classTitle
              : (widget.fallbackTitle ?? 'Videos'),
        ),
      ),
      body: content,
    );
  }

  void _openPlayer(VideoGroup group, VideoItem video) {
    final startIdx = group.videos.indexWhere((v) => v.id == video.id);
    final upNext =
        startIdx < 0 ? const <VideoItem>[] : group.videos.sublist(startIdx + 1);
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => SecureStreamPlayer(
          video: video,
          groupTitle: group.title,
          upNext: upNext,
        ),
        fullscreenDialog: true,
      ),
    )
        .then((_) {
      // Refresh progress / completion after the player closes.
      ref.invalidate(classVideosProvider(widget.classId));
    });
  }
}

// ───────────────────────── Group section ─────────────────────────

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    super.key,
    required this.group,
    required this.onPlay,
    this.highlighted = false,
  });

  final VideoGroup group;
  final void Function(VideoItem video) onPlay;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle =
        '${group.videoCount} parts · ${_fmtDuration(group.totalDuration)} total';
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (group.isComplete)
                StatusBadge.fromStatus('Completed',
                    icon: Icons.check_circle_rounded),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!isTablet)
            SizedBox(
              height: 188,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: group.videos.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (_, i) => _PartCard(
                  video: group.videos[i],
                  displayTitle: group.displayTitleFor(group.videos[i]),
                  partLabel: 'Part ${i + 1}',
                  onTap: () => onPlay(group.videos[i]),
                ),
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < group.videos.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == group.videos.length - 1 ? 0 : AppSpacing.sm,
                    ),
                    child: _PartCard(
                      video: group.videos[i],
                      displayTitle: group.displayTitleFor(group.videos[i]),
                      partLabel: 'Part ${i + 1}',
                      onTap: () => onPlay(group.videos[i]),
                      tabletFullWidth: true,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PartCard extends StatelessWidget {
  const _PartCard({
    required this.video,
    required this.displayTitle,
    required this.partLabel,
    required this.onTap,
    this.tabletFullWidth = false,
  });

  final VideoItem video;
  final String displayTitle;
  final String partLabel;
  final VoidCallback onTap;
  final bool tabletFullWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: tabletFullWidth ? double.infinity : 220,
      child: PremiumCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.lg),
                    ),
                    child: video.thumbnailUrl != null &&
                            video.thumbnailUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: video.thumbnailUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: context.palette.surfaceTinted,
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: context.palette.surfaceTinted,
                              child: const Icon(Icons.videocam_rounded,
                                  color: Colors.white54),
                            ),
                          )
                        : Container(color: context.palette.surfaceTinted),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _PillLabel(
                      text: partLabel,
                      background: Colors.black54,
                      color: Colors.white,
                    ),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: _PillLabel(
                      text: _fmtDuration(video.duration),
                      background: Colors.black87,
                      color: Colors.white,
                    ),
                  ),
                  if (video.completed)
                    const Positioned(
                      right: 6,
                      top: 6,
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: AppColors.success,
                        child: Icon(Icons.check_rounded,
                            color: Colors.white, size: 14),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: video.progress,
                      minHeight: 3,
                      backgroundColor:
                          theme.colorScheme.onSurface.withValues(alpha: 0.08),
                      color: video.completed
                          ? AppColors.success
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillLabel extends StatelessWidget {
  const _PillLabel({
    required this.text,
    required this.background,
    required this.color,
  });
  final String text;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

String _fmtDuration(Duration d) {
  if (d == Duration.zero) return '—';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
