import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/saba_icons.dart';

import '../../../../core/localization/failure_messages.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../domain/entities.dart';
import '../media_messages.dart';
import '../media_providers.dart';

/// What the add button offers.
enum MediaUploadMode { images, files }

/// A reusable upload slot: pick, preview, reorder, remove, retry, progress.
///
/// Every feature that attaches files uses this, so upload behaviour is written
/// once (§56). The parent reads the finished uploads at submit time:
///
/// ```dart
/// final media = ref.read(mediaUploadProvider(slot).notifier).uploadedMedia;
/// ```
class MediaUploadField extends ConsumerWidget {
  const MediaUploadField({
    super.key,
    required this.slot,
    this.label,
    this.mode = MediaUploadMode.images,
    this.allowReorder = true,
    this.allowCamera = true,
    this.tileSize = 104,
  });

  final MediaSlot slot;
  final String? label;
  final MediaUploadMode mode;

  /// Order matters for a product gallery: the first image is the main one.
  final bool allowReorder;

  final bool allowCamera;
  final double tileSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final items = ref.watch(mediaUploadProvider(slot));
    final controller = ref.read(mediaUploadProvider(slot).notifier);
    final isFull = items.length >= slot.constraints.maxItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                // Gives way to the count: in Arabic at 320 px the label ran
                // 6.5 px past the edge.
                Expanded(
                  child: Text(label!, style: context.textStyles.titleSmall),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${items.length}/${slot.constraints.maxItems}',
                  style: context.textStyles.labelSmall,
                ),
              ],
            ),
          ),
        SizedBox(
          height: tileSize + 28,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (items.isNotEmpty)
                Expanded(
                  // A tap, not a drag.
                  //
                  // This was a horizontal ReorderableListView, and that
                  // throws a rendering assertion as soon as it holds more
                  // than one item — so the picker broke for any merchant
                  // running a screen reader the moment they added a second
                  // photograph, and no test could draw the field either.
                  //
                  // Nothing is lost by dropping the drag: the only thing the
                  // order carried was which picture comes first, and saying
                  // "use this one" is one tap instead of dragging a tile
                  // across a strip that sits inside a scrolling form.
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, index) => _Tile(
                      key: ValueKey(items[index].localId),
                      item: items[index],
                      slot: slot,
                      size: tileSize,
                      isPrimary: allowReorder && index == 0,
                      onMakePrimary: allowReorder && index != 0
                          ? () => controller.reorder(index, 0)
                          : null,
                    ),
                  ),
                )
              else
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      l10n.noFilesSelected,
                      style: context.textStyles.bodySmall,
                    ),
                  ),
                ),
              // Full, no add tile: it said "You have reached the maximum
              // number of files", cut off, where the count already says so.
              if (!isFull) ...[
                const SizedBox(width: AppSpacing.sm),
                _AddButton(
                  size: tileSize,
                  mode: mode,
                  allowCamera: allowCamera,
                  enabled: true,
                  onPick: (fromCamera) => _pick(context, ref, fromCamera),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    bool fromCamera,
  ) async {
    final controller = ref.read(mediaUploadProvider(slot).notifier);

    final rejections = switch (mode) {
      MediaUploadMode.images => await controller.pickImages(
        fromCamera: fromCamera,
      ),
      MediaUploadMode.files => await controller.pickFiles(),
    };

    if (!context.mounted || rejections.isEmpty) return;

    // Valid files are already uploading; this only explains the rest.
    AppSnackBar.error(context, describeRejections(rejections, context.l10n));
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.size,
    required this.mode,
    required this.allowCamera,
    required this.enabled,
    required this.onPick,
  });

  final double size;
  final MediaUploadMode mode;
  final bool allowCamera;
  final bool enabled;
  final Future<void> Function(bool fromCamera) onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final label = switch (mode) {
      MediaUploadMode.images => l10n.addPhoto,
      MediaUploadMode.files => l10n.attachFile,
    };

    final icon = switch (mode) {
      MediaUploadMode.images => SabaIcons.image,
      MediaUploadMode.files => SabaIcons.clipboard,
    };

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: enabled ? () => _onTap(context) : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: enabled ? context.market.border : context.market.border,
              style: BorderStyle.solid,
            ),
            color: context.market.surfaceMuted,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SabaIcon(
                icon,
                size: AppSizes.iconLg,
                color: enabled
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context) async {
    // Only images can come from a camera, so only they need the choice.
    if (mode != MediaUploadMode.images || !allowCamera) {
      await onPick(false);
      return;
    }

    final fromCamera = await AppDialogs.bottomSheet<bool>(
      context,
      isScrollControlled: false,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: SabaIcon(SabaIcons.image),
              title: Text(sheetContext.l10n.chooseFromGallery),
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
            ListTile(
              leading: SabaIcon(SabaIcons.camera),
              title: Text(sheetContext.l10n.takePhoto),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );

    if (fromCamera == null) return;
    await onPick(fromCamera);
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({
    super.key,
    required this.item,
    required this.slot,
    required this.size,
    required this.isPrimary,
    this.onMakePrimary,
  });

  final MediaUploadItem item;
  final MediaSlot slot;
  final double size;
  final bool isPrimary;

  /// Moves this picture to the front, where the shop window looks. Null on
  /// the one already there, and on videos, which have no cover.
  final VoidCallback? onMakePrimary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(mediaUploadProvider(slot).notifier);

    final tile = Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
      child: SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: _Preview(item: item),
                  ),
                ),
                if (item.isBusy)
                  Positioned.fill(
                    child: _ProgressOverlay(
                      progress: item.progress,
                      onCancel: () => controller.cancel(item.localId),
                    ),
                  ),
                if (item.status == MediaUploadStatus.failed ||
                    item.status == MediaUploadStatus.cancelled)
                  Positioned.fill(
                    child: _RetryOverlay(
                      isFailure: item.status == MediaUploadStatus.failed,
                      onRetry: () => controller.retry(item.localId),
                    ),
                  ),
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: Material(
                    color: context.colors.surface.withValues(alpha: 0.9),
                    shape: const CircleBorder(),
                    child: IconButton(
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      tooltip: l10n.removeFile,
                      onPressed: () => controller.remove(item.localId),
                      icon: SabaIcon(SabaIcons.close),
                    ),
                  ),
                ),
                if (isPrimary && item.isDone)
                  PositionedDirectional(
                    bottom: 0,
                    start: 0,
                    end: 0,
                    child: Container(
                      color: context.colors.primary.withValues(alpha: 0.85),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xxs,
                      ),
                      child: Text(
                        l10n.primaryImage,
                        textAlign: TextAlign.center,
                        style: context.textStyles.labelSmall?.copyWith(
                          color: context.colors.onPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (item.failure != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text(
                  item.failure!.localizedMessage(l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.labelSmall?.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final onMakePrimary = this.onMakePrimary;
    if (onMakePrimary == null || !item.isDone) return tile;

    return Semantics(
      button: true,
      label: l10n.makeMainImage,
      child: Tooltip(
        message: l10n.makeMainImage,
        child: InkWell(
          onTap: onMakePrimary,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: tile,
        ),
      ),
    );
  }
}

/// Shows the local file while it uploads, then whatever the server returned.
class _Preview extends StatelessWidget {
  const _Preview({required this.item});

  final MediaUploadItem item;

  @override
  Widget build(BuildContext context) {
    final source = item.source;

    if (source != null && source.kind == MediaKind.image) {
      final bytes = source.bytes;
      if (bytes != null) {
        return Image.memory(bytes, fit: BoxFit.cover);
      }
      final path = source.path;
      if (path != null && !kIsWeb) {
        return Image.file(File(path), fit: BoxFit.cover);
      }
    }

    final uploaded = item.uploaded;
    if (uploaded != null && uploaded.kind != MediaKind.document) {
      return AppNetworkImage(url: uploaded.previewUrl, radius: 0);
    }

    return Container(
      color: context.market.surfaceMuted,
      child: Center(
        child: SabaIcon(switch (source?.kind ??
            uploaded?.kind ??
            MediaKind.unknown) {
          MediaKind.video => SabaIcons.video,
          MediaKind.document => SabaIcons.clipboard,
          _ => SabaIcons.clipboard,
        }, color: context.colors.onSurfaceVariant),
      ),
    );
  }
}

class _ProgressOverlay extends StatelessWidget {
  const _ProgressOverlay({required this.progress, required this.onCancel});

  final double progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.45),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              // Indeterminate until the first progress event arrives.
              value: progress > 0 ? progress : null,
              strokeWidth: 3,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            child: Text(
              context.l10n.cancel,
              style: context.textStyles.labelSmall?.copyWith(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetryOverlay extends StatelessWidget {
  const _RetryOverlay({required this.isFailure, required this.onRetry});

  final bool isFailure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: IconButton(
          onPressed: onRetry,
          tooltip: context.l10n.retryUpload,
          icon: SabaIcon(
            isFailure ? SabaIcons.refresh : SabaIcons.play,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
