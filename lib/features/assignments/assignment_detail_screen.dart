import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/components.dart';
import '../../core/error/failures.dart';
import '../_shared/models.dart';
import '../providers.dart';
import '../sync/app_data_sync.dart';
import '../../core/design/app_palette.dart';

class AssignmentDetailScreen extends ConsumerStatefulWidget {
  const AssignmentDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<AssignmentDetailScreen> createState() =>
      _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState
    extends ConsumerState<AssignmentDetailScreen> {
  final _text = TextEditingController();
  PlatformFile? _file;
  bool _submitting = false;

  static const _maxFileMb = 25;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.size > _maxFileMb * 1024 * 1024) {
      _toast('File is larger than ${_maxFileMb}MB.');
      return;
    }
    setState(() => _file = f);
  }

  Future<void> _submit(Assignment a) async {
    if (_text.text.trim().isEmpty && _file == null) {
      _toast('Add text or attach a file before submitting.');
      return;
    }
    setState(() => _submitting = true);
    try {
      MultipartFile? mp;
      if (_file != null) {
        mp = _file!.bytes != null
            ? MultipartFile.fromBytes(_file!.bytes!, filename: _file!.name)
            : await MultipartFile.fromFile(_file!.path!, filename: _file!.name);
      }
      await ref.read(studentRepositoryProvider).submitAssignment(
            id: widget.id,
            textContent: _text.text.trim().isEmpty ? null : _text.text.trim(),
            // The route accepts several files under `attachments[]`; the
            // picker is single-select today, so this is a one-item list.
            attachments: mp == null ? const <MultipartFile>[] : [mp],
          );
      if (!mounted) return;
      ref
          .read(appDataSyncProvider)
          .onAssignmentSubmitted(assignmentId: widget.id);
      _text.clear();
      setState(() => _file = null);
      _toast('Submission sent.', success: true);
    } catch (e) {
      if (!mounted) return;
      _toast(e is AppFailure ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? AppColors.success : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assignmentAsync = ref.watch(assignmentProvider(widget.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          assignmentAsync.valueOrNull?.title.isNotEmpty == true
              ? assignmentAsync.value!.title
              : (assignmentAsync.valueOrNull?.type == 'quiz'
                  ? 'Quiz'
                  : 'Assignment'),
        ),
        elevation: 0,
      ),
      body: assignmentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorStateView(
          message: e is AppFailure ? e.message : e.toString(),
          onRetry: () => ref.invalidate(assignmentProvider(widget.id)),
        ),
        data: (a) => _buildBody(a),
      ),
    );
  }

  Widget _buildBody(Assignment a) {
    final theme = Theme.of(context);
    final isQuiz = a.type == 'quiz';
    // `late` is not a submission_status — it only ever appears in
    // `submission_states` alongside `submitted` (API_BRIEF §7).
    final hasSubmission = a.isSubmitted;
    // The backend accepts resubmission right up until the work is graded.
    final readOnly = hasSubmission || !a.canResubmit;
    final overdue = a.isOverdue;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        // ── Header ────────────────────────────────────────────────────────
        PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (isQuiz ? AppColors.info : AppColors.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isQuiz ? Icons.quiz_outlined : Icons.assignment_outlined,
                      color: isQuiz ? AppColors.info : AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title.isNotEmpty
                              ? a.title
                              : (isQuiz ? 'Quiz' : 'Assignment'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        if (a.subjectName?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              a.subjectName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.65),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Pill(
                    icon: isQuiz
                        ? Icons.quiz_outlined
                        : Icons.assignment_outlined,
                    label: isQuiz ? 'Quiz' : 'Homework',
                    color: isQuiz ? AppColors.info : AppColors.primary,
                  ),
                  _statusPill(a, overdue: overdue),
                  if (a.dueAt != null)
                    _Pill(
                      icon: Icons.schedule_rounded,
                      label: _dueLabel(
                        a.dueAt!,
                        done: a.isSubmitted || a.status == 'late',
                      ),
                      color: overdue
                          ? AppColors.danger
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.65),
                    ),
                  if (a.maxScore != null)
                    _Pill(
                      icon: Icons.star_outline_rounded,
                      label: 'Max ${a.maxScore}',
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.65),
                    ),
                ],
              ),
              if (a.description?.trim().isNotEmpty == true) ...[
                const SizedBox(height: AppSpacing.md),
                Divider(height: 1, color: context.palette.divider),
                const SizedBox(height: AppSpacing.md),
                SelectableText(
                  a.description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    height: 1.5,
                  ),
                ),
              ],
              if (a.attachmentUrl?.isNotEmpty == true) ...[
                const SizedBox(height: AppSpacing.md),
                _AttachmentChip(
                  assignmentId: a.id,
                  filename: a.attachmentFilename,
                ),
              ],
            ],
          ),
        ),

        // ── Mark (graded + released) ─────────────────────────────────────
        // When `submission.released == false` the grade and feedback are
        // ABSENT from the payload — not zero. Show the awaiting-release state
        // and no number (API_BRIEF §7).
        if (a.awaitingRelease) ...[
          const SizedBox(height: AppSpacing.md),
          const _AwaitingReleaseCard(),
        ] else if (a.isGraded) ...[
          const SizedBox(height: AppSpacing.md),
          _ScoreCard(
            score: a.visibleGrade,
            maxScore: a.submission?.marking?.totalMax ?? a.maxScore,
            feedback: a.submission?.feedback,
          ),
        ],

        // ── Submission status (already submitted) ────────────────────────
        if (hasSubmission && a.status != 'graded') ...[
          const SizedBox(height: AppSpacing.md),
          PremiumCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: AppColors.success,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Submission received',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Awaiting grading.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Submission form ──────────────────────────────────────────────
        // Hidden once any submission exists — the "Submission received" /
        // "Score" card above already conveys the status.
        if (!hasSubmission) ...[
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              readOnly ? 'Submission' : 'Your submission',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (readOnly)
            const PremiumCard(
              child: EmptyState(
                title: 'Submissions closed',
                message: 'You can no longer submit this item.',
                icon: Icons.lock_outline_rounded,
              ),
            )
          else
            _SubmissionForm(
              controller: _text,
              file: _file,
              onPick: _pickFile,
              onClearFile: () => setState(() => _file = null),
              onSubmit: _submitting ? null : () => _submit(a),
              submitting: _submitting,
            ),
        ],
      ],
    );
  }

  Widget _statusPill(Assignment a, {required bool overdue}) {
    final s = a.status ?? 'pending';
    late final Color color;
    late final String label;
    late final IconData icon;
    switch (s) {
      case 'graded':
        color = AppColors.success;
        label = 'Graded';
        icon = Icons.task_alt_rounded;
        break;
      case 'submitted':
        color = AppColors.info;
        label = 'Submitted';
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'late':
        color = AppColors.warning;
        label = 'Late';
        icon = Icons.history_toggle_off_rounded;
        break;
      default:
        if (overdue) {
          color = AppColors.danger;
          label = 'Overdue';
          icon = Icons.error_outline_rounded;
        } else {
          color = AppColors.warning;
          label = 'Pending';
          icon = Icons.hourglass_bottom_rounded;
        }
    }
    return _Pill(icon: icon, label: label, color: color, filled: true);
  }

  /// [done] is true once the work is handed in or marked. The deadline is
  /// still worth showing then, but "Overdue · 14 days" beside a "Graded" pill
  /// reads as a contradiction — it only ever meant the date had passed.
  String _dueLabel(DateTime due, {bool done = false}) {
    final now = DateTime.now();
    final diff = due.difference(now);
    final fmt = DateFormat.MMMd().add_jm().format(due);
    if (done) return 'Due $fmt';
    if (diff.isNegative) {
      final d = -diff.inDays;
      if (d > 0) return 'Overdue · $d day${d == 1 ? '' : 's'}';
      final h = -diff.inHours;
      return h > 0 ? 'Overdue · $h hour${h == 1 ? '' : 's'}' : 'Overdue';
    }
    if (diff.inDays >= 1) return 'Due in ${diff.inDays}d · $fmt';
    if (diff.inHours >= 1) return 'Due in ${diff.inHours}h · $fmt';
    return 'Due soon · $fmt';
  }
}

// ──────────────────────────── Submission form ───────────────────────────────

class _SubmissionForm extends StatelessWidget {
  const _SubmissionForm({
    required this.controller,
    required this.file,
    required this.onPick,
    required this.onClearFile,
    required this.onSubmit,
    required this.submitting,
  });
  final TextEditingController controller;
  final PlatformFile? file;
  final VoidCallback onPick;
  final VoidCallback onClearFile;
  final VoidCallback? onSubmit;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Text field — bordered, multiline.
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.4),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: TextField(
                controller: controller,
                minLines: 5,
                maxLines: 10,
                inputFormatters: [LengthLimitingTextInputFormatter(5000)],
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: const InputDecoration(
                  hintText: 'Type your answer (optional)',
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // File chip (shown only when picked).
          if (file != null) ...[
            _FileChip(file: file!, onRemove: onClearFile),
            const SizedBox(height: 12),
          ],

          // Action row.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: submitting ? null : onPick,
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: Text(file == null ? 'Attach file' : 'Replace file'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: context.palette.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSubmit,
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(submitting ? 'Sending…' : 'Submit'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(
              'You can attach a single file up to 25MB (pdf, image, doc).',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.file, required this.onRemove});
  final PlatformFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _iconFor(file.extension),
            color: AppColors.primary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _humanSize(file.size),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 18),
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.grid_on_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
      case 'gif':
        return Icons.image_rounded;
      case 'mp4':
      case 'mov':
      case 'm4v':
        return Icons.movie_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

// ──────────────────────────── Pieces ────────────────────────────────────────

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.color,
    this.filled = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final bg = filled
        ? color.withValues(alpha: 0.12)
        : context.palette.divider.withValues(alpha: 0.6);
    final fg = filled
        ? color
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens a teacher attachment.
///
/// `attachment_url` is a **token-protected** path (API_BRIEF §7): it only
/// serves bytes when the request carries the `Authorization` header. Handing
/// the URL to `launchUrl`, `Image.network` or a bare WebView sends no header
/// and gets a 401.
///
/// So: fetch through the authenticated Dio client, write to the app's own
/// sandboxed temp directory, and hand that local path to the system viewer.
/// Nothing is written to shared storage and no URL leaves the app.
class _AttachmentChip extends ConsumerStatefulWidget {
  const _AttachmentChip({required this.assignmentId, this.filename});
  final String assignmentId;
  final String? filename;

  @override
  ConsumerState<_AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends ConsumerState<_AttachmentChip> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await ref
          .read(studentRepositoryProvider)
          .assignmentAttachment(widget.assignmentId);
      final dir = await getTemporaryDirectory();
      // Sanitise: the filename comes from a server header, so it must not be
      // able to escape the temp directory.
      final safe = file.filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '${dir.path}/$safe';
      await File(path).writeAsBytes(file.bytes, flush: true);
      final result = await OpenFilex.open(path);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg =
          e is AppFailure ? e.message : 'Could not open the attachment.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        widget.filename?.isNotEmpty == true ? widget.filename! : 'Attachment';
    return Material(
      color: context.palette.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : _open,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.palette.divider),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.attachment_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (_busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.download_rounded,
                  size: 16,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the work is marked but the teacher has not released the mark.
///
/// The grade is ABSENT from the payload in this state — rendering a 0 here
/// would tell the student they failed when nothing has been published yet.
class _AwaitingReleaseCard extends StatelessWidget {
  const _AwaitingReleaseCard();

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Awaiting release',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your teacher has marked this but has not published the '
                  'result yet.',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({this.score, this.maxScore, this.feedback});
  final num? score;
  final num? maxScore;
  final String? feedback;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (score != null && maxScore != null && maxScore != 0)
        ? (score!.toDouble() / maxScore!.toDouble()).clamp(0.0, 1.0)
        : 0.0;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: AppColors.success,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Score',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65),
                      ),
                    ),
                    Text(
                      '${score ?? '—'} / ${maxScore ?? '—'}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(pct * 100).round()}%',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: context.palette.divider,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.success),
            ),
          ),
          if (feedback?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 14),
            Text(
              'Feedback',
              style: theme.textTheme.labelMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              feedback!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
