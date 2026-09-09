import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:domain/model/attachment.dart';

void main() {
  group('Attachment models', () {
    test('PendingImage equality and hashCode', () {
      const a = PendingImage(
        id: 'img-1',
        mediaType: 'image/png',
        base64Data: 'iVBORw==',
        name: 'test.png',
        byteSize: 100,
      );
      const b = PendingImage(
        id: 'img-1',
        mediaType: 'image/png',
        base64Data: 'iVBORw==',
        name: 'test.png',
        byteSize: 100,
      );
      const diff = PendingImage(
        id: 'img-1',
        mediaType: 'image/jpeg',
        base64Data: 'iVBORw==',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    const ref = AttachmentRef(
      attachmentId: 'att-1',
      mediaType: 'image/png',
      bytes: 2048,
      width: 200,
      height: 200,
      name: 'ref.png',
    );

    test('AttachmentRef equality and hashCode', () {
      const copy = AttachmentRef(
        attachmentId: 'att-1',
        mediaType: 'image/png',
        bytes: 2048,
        width: 200,
        height: 200,
        name: 'ref.png',
      );
      const diff = AttachmentRef(
        attachmentId: 'att-2',
        mediaType: 'image/png',
        bytes: 2048,
        width: 200,
        height: 200,
      );

      expect(ref, equals(copy));
      expect(ref.hashCode, equals(copy.hashCode));
      expect(ref, isNot(equals(diff)));
    });

    test('AttachmentData byte comparison and equality', () {
      final bytes1 = Uint8List.fromList([1, 2, 3, 4]);
      final bytes2 = Uint8List.fromList([1, 2, 3, 4]);
      final bytesDiff = Uint8List.fromList([1, 2, 3, 5]);
      final bytesDiffLen = Uint8List.fromList([1, 2, 3]);

      final a = AttachmentData(ref: ref, data: bytes1);
      final b = AttachmentData(ref: ref, data: bytes2);
      final c = AttachmentData(ref: ref, data: bytesDiff);
      final d = AttachmentData(ref: ref, data: bytesDiffLen);

      expect(a, equals(a)); // identical short-circuit
      expect(a, equals(b)); // equal contents
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('ImageLimits defaults and equality with mediaTypes collection', () {
      const a = ImageLimits();
      const b = ImageLimits();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.maxImageBytes, ImageLimits.defaultMaxImageBytes);
      expect(a.mediaTypes, ImageLimits.defaultMediaTypes);

      const diff = ImageLimits(maxImageBytes: 1024);
      const diffTypes = ImageLimits(mediaTypes: ['image/png']);

      expect(a, isNot(equals(diff)));
      expect(a, isNot(equals(diffTypes)));
    });
  });
}
