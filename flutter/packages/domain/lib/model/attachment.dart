/// Image-attachment vocabulary for the version-one path. Raster images ride
/// the prompt wire as inline content parts; durable references come back in
/// the session log and download through `session.attachment`.
library;

import 'dart:typed_data';

/// One composer-held image awaiting send, encoded as base64.
final class PendingImage {
  const PendingImage({
    required this.id,
    required this.mediaType,
    required this.base64Data,
    this.name,
    this.byteSize = 0,
  });

  final String id;
  final String mediaType;
  final String base64Data;
  final String? name;
  final int byteSize;

  @override
  bool operator ==(Object other) =>
      other is PendingImage &&
      other.id == id &&
      other.mediaType == mediaType &&
      other.base64Data == base64Data &&
      other.name == name &&
      other.byteSize == byteSize;

  @override
  int get hashCode => Object.hash(id, mediaType, base64Data, name, byteSize);
}

/// Durable image reference found inside a message's content blocks.
final class AttachmentRef {
  const AttachmentRef({
    required this.attachmentId,
    required this.mediaType,
    required this.bytes,
    required this.width,
    required this.height,
    this.name,
  });

  final String attachmentId;
  final String mediaType;
  final int bytes;
  final int width;
  final int height;
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is AttachmentRef &&
      other.attachmentId == attachmentId &&
      other.mediaType == mediaType &&
      other.bytes == bytes &&
      other.width == width &&
      other.height == height &&
      other.name == name;

  @override
  int get hashCode =>
      Object.hash(attachmentId, mediaType, bytes, width, height, name);
}

/// One downloaded image: its durable reference plus decoded bytes.
final class AttachmentData {
  AttachmentData({required this.ref, required this.data});

  final AttachmentRef ref;
  final Uint8List data;

  @override
  bool operator ==(Object other) =>
      other is AttachmentData &&
      other.ref == ref &&
      _bytesEqual(other.data, data);

  @override
  int get hashCode => Object.hash(ref, data.length);

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Host admission limits for images, mirrored from the `imageLimits`
/// session projection. Null fields fall back to client-side defaults until
/// the host projection arrives.
final class ImageLimits {
  const ImageLimits({
    this.maxImageBytes = defaultMaxImageBytes,
    this.maxImagesPerMessage = defaultMaxImagesPerMessage,
    this.maxMessageImageBytes = defaultMaxImageBytes,
    this.maxImagePixels = defaultMaxImagePixels,
    this.mediaTypes = defaultMediaTypes,
  });

  static const int defaultMaxImageBytes = 5 * 1024 * 1024;
  static const int defaultMaxImagesPerMessage = 20;
  static const int defaultMaxImagePixels = 30000000;
  static const List<String> defaultMediaTypes = [
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/gif',
  ];

  final int maxImageBytes;
  final int maxImagesPerMessage;
  final int maxMessageImageBytes;
  final int maxImagePixels;
  final List<String> mediaTypes;

  @override
  bool operator ==(Object other) =>
      other is ImageLimits &&
      other.maxImageBytes == maxImageBytes &&
      other.maxImagesPerMessage == maxImagesPerMessage &&
      other.maxMessageImageBytes == maxMessageImageBytes &&
      other.maxImagePixels == maxImagePixels &&
      _listEquals(other.mediaTypes, mediaTypes);

  @override
  int get hashCode => Object.hash(
    maxImageBytes,
    maxImagesPerMessage,
    maxMessageImageBytes,
    maxImagePixels,
    Object.hashAll(mediaTypes),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
