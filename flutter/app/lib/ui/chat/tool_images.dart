/// Durable images a tool result carried — the `read_image` family's card.
///
/// The reference web client renders those results as their own toolview
/// (`ui-tool/.../read-image-row.tsx` → the `tool.call.images` slot filled by
/// `ui-attachment/MessageImage.tsx`): a single image sized to a 240px long
/// edge with its natural aspect ratio clamped to `[0.25, 4]`, or 64px square
/// tiles when the result carried several, and a full-viewport lightbox on
/// tap. The bytes never ride the event; each reference is fetched through
/// the repository's session-authorized `readAttachment` seam.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/attachment.dart';
import 'package:flutter/material.dart';

import 'chat_screen.dart' show AttachmentLoader;
import '../theme/theme.dart';

/// Long edge of a single-image card (web `singleFit`).
const double kToolImageLongEdge = 240;

/// Edge of one tile when a result carried several images.
const double kToolImageTileEdge = 64;

/// Aspect-ratio window a single image is clamped into before cropping.
const double kToolImageMinAspect = 0.25;
const double kToolImageMaxAspect = 4;

/// The images of one tool result: a label-free gallery sized the way the
/// reference sizes it, each frame opening the lightbox.
class ToolImageGallery extends StatelessWidget {
  const ToolImageGallery({
    required this.sessionId,
    required this.images,
    required this.loadAttachment,
    super.key,
  });

  final String sessionId;
  final List<AttachmentRef> images;
  final AttachmentLoader loadAttachment;

  @override
  Widget build(BuildContext context) {
    final multiple = images.length > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final ref in images)
            _ToolImageFrame(
              sessionId: sessionId,
              ref: ref,
              loadAttachment: loadAttachment,
              tile: multiple,
            ),
        ],
      ),
    );
  }
}

/// One framed image: the frame keeps the reference's geometry while it
/// loads, and taps open [showImageLightbox].
class _ToolImageFrame extends StatefulWidget {
  const _ToolImageFrame({
    required this.sessionId,
    required this.ref,
    required this.loadAttachment,
    required this.tile,
  });

  final String sessionId;
  final AttachmentRef ref;
  final AttachmentLoader loadAttachment;
  final bool tile;

  @override
  State<_ToolImageFrame> createState() => _ToolImageFrameState();
}

class _ToolImageFrameState extends State<_ToolImageFrame> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final bytes = await widget.loadAttachment(widget.sessionId, widget.ref);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _failed = bytes == null;
    });
  }

  /// The frame's box: a 64dp square for a tile, and the reference's
  /// long-edge fit for a single image (never upscaled past its own pixels,
  /// aspect clamped and cover-cropped past the window).
  Size get _box {
    if (widget.tile) {
      return const Size(kToolImageTileEdge, kToolImageTileEdge);
    }
    final width = widget.ref.width.toDouble();
    final height = widget.ref.height.toDouble();
    if (width <= 0 || height <= 0) {
      return const Size(kToolImageLongEdge, kToolImageLongEdge);
    }
    final aspect = width / height;
    final clamped = aspect.clamp(kToolImageMinAspect, kToolImageMaxAspect);
    if (clamped >= 1) {
      final boxWidth = width < kToolImageLongEdge ? width : kToolImageLongEdge;
      return Size(boxWidth, boxWidth / clamped);
    }
    final boxHeight = height < kToolImageLongEdge ? height : kToolImageLongEdge;
    return Size(boxHeight * clamped, boxHeight);
  }

  /// Where the cover crop is anchored once the aspect clamp bites (web
  /// `singleFit`'s `objectPosition`).
  Alignment get _crop {
    if (widget.tile) return Alignment.center;
    final aspect = widget.ref.width / widget.ref.height;
    if (aspect < kToolImageMinAspect) return Alignment.topCenter;
    if (aspect > kToolImageMaxAspect) return Alignment.centerLeft;
    return Alignment.center;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final box = _box;
    final bytes = _bytes;
    return Semantics(
      image: true,
      label: widget.ref.name,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(kShapeCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(kShapeCard),
          onTap: bytes == null
              ? null
              : () => showImageLightbox(
                  context,
                  bytes: bytes,
                  name: widget.ref.name,
                ),
          child: Container(
            width: box.width,
            height: box.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kShapeCard),
              // The reference frame's hairline (`.frame` border-l2).
              border: Border.all(color: scheme.outlineVariant, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: bytes != null
                ? Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    alignment: _crop,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => _placeholder(context, l10n),
                  )
                : _placeholder(context, l10n),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: _failed
          ? Icon(Icons.broken_image_outlined, size: 18, color: scheme.outline)
          : Icon(
              Icons.image_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
    );
  }
}

/// Full-viewport image preview — the reference lightbox: the image contained
/// in the viewport, the scrim dismissing, and a close seat.
Future<void> showImageLightbox(
  BuildContext context, {
  required Uint8List bytes,
  String? name,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.9),
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(dialogContext).pop(),
                child: InteractiveViewer(
                  maxScale: 4,
                  child: Center(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      semanticLabel: name,
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: Material(
                // The inverse pair is the one surface that stays legible
                // over the scrim in both brightnesses.
                color: Theme.of(dialogContext).colorScheme.inverseSurface,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: l10n.close,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(dialogContext).colorScheme.onInverseSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
