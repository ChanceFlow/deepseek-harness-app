/// Byte-level codec for the Volcengine full-duplex streaming ASR (v3)
/// binary protocol, mirrored from the official Python demo
/// (`sauc_websocket_demo.py` / `protocol.py`).
///
/// Every frame starts with a 4-byte header:
///
/// ```text
/// byte 0: protocol version (4 bits, 0b0001) | header size (4 bits, words of 4 bytes)
/// byte 1: message type (4 bits)            | message flags (4 bits)
/// byte 2: serialization (4 bits)           | compression (4 bits)
/// byte 3: reserved (0x00)
/// ```
///
/// Flags: bit 0 — a 4-byte sequence number precedes the rest of the payload;
/// bit 1 — this is the last audio package (sequence must be negative);
/// bit 2 — an event code follows the sequence. Client requests and server
/// responses are all gzip-compressed JSON-or-PCM payloads, each preceded by
/// a 4-byte big-endian size.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Message types carried in header byte 1's high nibble.
abstract final class AsrV3MessageType {
  static const int clientFullRequest = 0x1;
  static const int clientAudioOnly = 0x2;
  static const int serverFullResponse = 0x9;
  static const int serverErrorResponse = 0xF;
}

/// Message-flag bits, per header byte 1's low nibble.
abstract final class AsrV3Flags {
  /// Payload begins with a 4-byte sequence number.
  static const int sequence = 0x1;

  /// This package is the last of the session.
  static const int lastPackage = 0x2;

  /// A 4-byte event code follows the sequence number.
  static const int event = 0x4;
}

/// Volcengine v3 request builders.
abstract final class AsrV3Request {
  /// Builds the session-opening full client request: header + sequence +
  /// 4-byte size + gzip(JSON payload). [sequence] counts from 1.
  static Uint8List fullClientRequest(
    Map<String, Object?> payload,
    int sequence,
  ) {
    final Uint8List compressed = _gzip(utf8.encode(jsonEncode(payload)));
    final ByteData size = ByteData(4)
      ..setUint32(0, compressed.length, Endian.big);
    return _frame(
      AsrV3MessageType.clientFullRequest,
      AsrV3Flags.sequence,
      _prefixSequence(sequence, size.buffer.asUint8List(), compressed),
    );
  }

  /// Builds one audio-only request. Regular chunks carry a positive
  /// sequence; the last chunk carries a negative one
  /// (flags `sequence | lastPackage`), mirroring the official demo.
  static Uint8List audioOnlyRequest(
    List<int> pcmBytes, {
    required int sequence,
    required bool isLast,
  }) {
    final Uint8List compressed = _gzip(pcmBytes);
    final ByteData size = ByteData(4)
      ..setUint32(0, compressed.length, Endian.big);
    final Uint8List body = _prefixSequence(
      isLast ? -sequence : sequence,
      size.buffer.asUint8List(),
      compressed,
    );
    return _frame(
      AsrV3MessageType.clientAudioOnly,
      isLast
          ? AsrV3Flags.sequence | AsrV3Flags.lastPackage
          : AsrV3Flags.sequence,
      body,
    );
  }

  static Uint8List _prefixSequence(
    int sequence,
    Uint8List size,
    Uint8List payload,
  ) {
    final ByteData seq = ByteData(4)..setInt32(0, sequence, Endian.big);
    final Uint8List out = Uint8List(4 + size.length + payload.length);
    out.setRange(0, 4, seq.buffer.asUint8List());
    out.setRange(4, 4 + size.length, size);
    out.setRange(4 + size.length, out.length, payload);
    return out;
  }

  static Uint8List _frame(int messageType, int flags, Uint8List body) {
    final Uint8List out = Uint8List(4 + body.length);
    out[0] = 0x11; // protocol version 0b0001, header size 1 word (4 bytes)
    out[1] = (messageType << 4) | flags;
    out[2] = 0x11; // serialization JSON, compression gzip
    out[3] = 0x00;
    out.setRange(4, out.length, body);
    return out;
  }

  static Uint8List _gzip(List<int> bytes) =>
      Uint8List.fromList(GZipCodec().encode(bytes));
}

/// One parsed server frame.
sealed class AsrV3ServerFrame {
  const AsrV3ServerFrame();
}

/// A full server response carrying JSON [payloadMsg].
class AsrV3FullResponse extends AsrV3ServerFrame {
  const AsrV3FullResponse({
    required this.isLastPackage,
    required this.payloadMsg,
  });

  /// Whether this response closes the session.
  final bool isLastPackage;

  /// Decoded response body (`audio_info`, `result`, `additions`, ...).
  final Map<String, Object?> payloadMsg;
}

/// An error response; the session is dead after this.
class AsrV3ErrorResponse extends AsrV3ServerFrame {
  const AsrV3ErrorResponse({required this.code, required this.message});

  final int code;
  final String message;
}

/// A frame the engine can ignore (e.g. an event-only ack).
class AsrV3IgnoredFrame extends AsrV3ServerFrame {
  const AsrV3IgnoredFrame({required this.messageType});

  final int messageType;
}

/// Volcengine v3 response parser.
abstract final class AsrV3ResponseParser {
  /// Parses one binary server frame.
  ///
  /// Throws [ArgumentError] on frames too short to carry the 4-byte header
  /// — a malformed frame is a wire bug, never a silent skip.
  static AsrV3ServerFrame parse(Uint8List frame) {
    if (frame.length < 4) {
      throw ArgumentError('ASR v3 frame shorter than its 4-byte header');
    }
    final int headerSizeWords = frame[0] & 0x0f;
    final int headerSize = headerSizeWords * 4;
    final int messageType = frame[1] >> 4;
    final int flags = frame[1] & 0x0f;
    final int compression = frame[2] & 0x0f;
    if (frame.length <= headerSize) {
      // Header-only frame: nothing to decode, nothing to act on.
      return AsrV3IgnoredFrame(messageType: messageType);
    }
    Uint8List payload = Uint8List.sublistView(frame, headerSize);

    // Flag order matches the official parser: sequence, then event, then
    // (for the payload-proper) size.
    if (flags & AsrV3Flags.sequence != 0) {
      payload = _drop(payload, 4);
    }
    if (flags & AsrV3Flags.event != 0) {
      payload = _drop(payload, 4);
    }
    final bool isLastPackage = flags & AsrV3Flags.lastPackage != 0;

    if (messageType == AsrV3MessageType.serverErrorResponse) {
      final int code = _readInt32(payload);
      payload = _drop(payload, 4);
      final int size = _readUint32(payload);
      payload = _drop(payload, 4);
      return AsrV3ErrorResponse(
        code: code,
        message: _decodeMessage(_decompress(payload, compression), size),
      );
    }
    if (messageType == AsrV3MessageType.serverFullResponse) {
      final int size = _readUint32(payload);
      payload = _drop(payload, 4);
      // Honor the declared size when it is sane; a mismatch is the
      // service's problem to notice, not ours to pad.
      if (size > 0 && size < payload.length) {
        payload = Uint8List.sublistView(payload, 0, size);
      }
      final Object? decoded = jsonDecode(
        utf8.decode(_decompress(payload, compression)),
      );
      if (decoded is Map<String, Object?>) {
        return AsrV3FullResponse(
          isLastPackage: isLastPackage,
          payloadMsg: decoded,
        );
      }
      throw ArgumentError('ASR v3 response payload is not a JSON object');
    }
    return AsrV3IgnoredFrame(messageType: messageType);
  }

  static Uint8List _drop(Uint8List payload, int count) {
    if (payload.length < count) {
      throw ArgumentError('ASR v3 payload truncated in the size field');
    }
    return Uint8List.sublistView(payload, count);
  }

  static int _readInt32(Uint8List payload) {
    if (payload.length < 4) {
      throw ArgumentError('ASR v3 payload truncated before an int32 field');
    }
    return ByteData.sublistView(payload).getInt32(0, Endian.big);
  }

  static int _readUint32(Uint8List payload) => _readInt32(payload) & 0xFFFFFFFF;

  static Uint8List _decompress(Uint8List payload, int compression) {
    if (compression == 0x1) {
      return Uint8List.fromList(GZipCodec().decode(payload));
    }
    return payload;
  }

  /// Error bodies may be raw text or JSON carrying `message`/`msg`;
  /// both surface verbatim, a decode failure is not worth a crash.
  static String _decodeMessage(Uint8List payload, int size) {
    try {
      final String text = utf8.decode(
        size > 0 && size <= payload.length
            ? Uint8List.sublistView(payload, 0, size)
            : payload,
      );
      final Object? decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) {
        final Object? message = decoded['message'] ?? decoded['msg'];
        if (message is String) return message;
      }
      return text;
    } on FormatException {
      return '';
    }
  }
}
