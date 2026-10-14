/// PDF page-renderer seam tests — the channel contract and its non-throwing
/// fallbacks.
library;

import 'package:app/platform/pdf_page_renderer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(kPdfPageRendererChannel);

  /// A short stand-in for a PDF: the contract is that the complete file
  /// travels in one argument, not that the bytes are interesting.
  final Uint8List bytes = Uint8List.fromList(<int>[37, 80, 68, 70, 45, 49, 46]);

  void answerWith(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('open sends the complete bytes and reports the page count', () async {
    answerWith((MethodCall call) async {
      expect(call.method, equals('open'));
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(arguments.keys, equals(<String>['bytes']));
      expect(arguments['bytes'], equals(bytes));
      return <String, Object?>{'token': 'doc-1', 'count': 3};
    });

    final renderer = PlatformPdfPageRenderer();
    final document = await renderer.open(bytes);

    expect(document, isNotNull);
    expect(document, isA<PdfDocument>());
    expect(document!.pageCount, equals(3));
    expect(renderer.lastOpenFailure, isNull);
  });

  test('a missing channel answers null instead of throwing', () async {
    final renderer = PlatformPdfPageRenderer();

    expect(await renderer.open(bytes), isNull);
    expect(renderer.lastOpenFailure, equals(PdfRenderFailure.unsupported));
  });

  test('a password-protected document reports that failure', () async {
    answerWith((MethodCall call) async {
      throw PlatformException(
        code: 'password',
        message: 'the document needs a password',
      );
    });

    final renderer = PlatformPdfPageRenderer();

    expect(await renderer.open(bytes), isNull);
    expect(renderer.lastOpenFailure, equals(PdfRenderFailure.password));
  });

  test('a malformed open reply answers null, not a document', () async {
    answerWith(
      (MethodCall call) async => <String, Object?>{'token': 7, 'count': 'many'},
    );

    final renderer = PlatformPdfPageRenderer();

    expect(await renderer.open(bytes), isNull);
    expect(renderer.lastOpenFailure, equals(PdfRenderFailure.failed));
  });

  test('every machine code maps to its failure', () {
    expect(
      pdfRenderFailureFromCode('unsupported'),
      equals(PdfRenderFailure.unsupported),
    );
    expect(
      pdfRenderFailureFromCode('invalid'),
      equals(PdfRenderFailure.invalid),
    );
    expect(
      pdfRenderFailureFromCode('password'),
      equals(PdfRenderFailure.password),
    );
    expect(pdfRenderFailureFromCode('failed'), equals(PdfRenderFailure.failed));
    expect(
      pdfRenderFailureFromCode('something_else'),
      equals(PdfRenderFailure.failed),
    );
    expect(pdfRenderFailureFromCode(null), equals(PdfRenderFailure.failed));
  });

  test('renderPage sends token, index and maxPixels, and decodes the '
      'image', () async {
    final methods = <String>[];
    answerWith((MethodCall call) async {
      methods.add(call.method);
      if (call.method == 'open') {
        return <String, Object?>{'token': 'doc-7', 'count': 2};
      }
      expect(call.method, equals('renderPage'));
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(
        arguments.keys,
        equals(<String>['token', 'index', 'targetWidth', 'maxPixels']),
      );
      expect(arguments['token'], equals('doc-7'));
      expect(arguments['index'], equals(1));
      expect(arguments['targetWidth'], equals(800));
      expect(arguments['maxPixels'], equals(4096));
      return <String, Object?>{
        'bytes': Uint8List.fromList(<int>[137, 80, 78, 71]),
        'width': 64,
        'height': 32,
      };
    });

    final document = await PlatformPdfPageRenderer().open(bytes);
    final page = await document!.renderPage(
      1,
      targetWidth: 800,
      maxPixels: 4096,
    );

    expect(page, isNotNull);
    expect(page!.bytes, isA<Uint8List>());
    expect(page.bytes, equals(<int>[137, 80, 78, 71]));
    expect(page.width, equals(64));
    expect(page.height, equals(32));
    expect(methods, equals(<String>['open', 'renderPage']));
  });

  test('a failed renderPage answers null, not a throw', () async {
    answerWith((MethodCall call) async {
      if (call.method == 'open') {
        return <String, Object?>{'token': 'doc-2', 'count': 1};
      }
      throw PlatformException(code: 'failed', message: 'the page did not draw');
    });

    final document = await PlatformPdfPageRenderer().open(bytes);

    expect(
      await document!.renderPage(0, targetWidth: 800, maxPixels: 1024),
      isNull,
    );
  });

  test('a malformed renderPage reply answers null', () async {
    answerWith((MethodCall call) async {
      if (call.method == 'open') {
        return <String, Object?>{'token': 'doc-3', 'count': 1};
      }
      return <String, Object?>{'bytes': 'not bytes', 'width': 0, 'height': -1};
    });

    final document = await PlatformPdfPageRenderer().open(bytes);

    expect(
      await document!.renderPage(0, targetWidth: 800, maxPixels: 1024),
      isNull,
    );
  });

  test('a target width below one answers null without a host call', () async {
    final methods = <String>[];
    answerWith((MethodCall call) async {
      methods.add(call.method);
      return <String, Object?>{'token': 'doc-9', 'count': 2};
    });

    final document = await PlatformPdfPageRenderer().open(bytes);

    expect(
      await document!.renderPage(0, targetWidth: 0, maxPixels: 1024),
      isNull,
    );
    expect(methods, equals(<String>['open']));
  });

  test(
    'an index outside the document answers null without a host call',
    () async {
      final methods = <String>[];
      answerWith((MethodCall call) async {
        methods.add(call.method);
        return <String, Object?>{'token': 'doc-5', 'count': 2};
      });

      final document = await PlatformPdfPageRenderer().open(bytes);

      expect(
        await document!.renderPage(2, targetWidth: 800, maxPixels: 1024),
        isNull,
      );
      expect(
        await document.renderPage(-1, targetWidth: 800, maxPixels: 1024),
        isNull,
      );
      expect(methods, equals(<String>['open']));
    },
  );

  test('close invokes the channel once and is idempotent', () async {
    var closes = 0;
    answerWith((MethodCall call) async {
      if (call.method == 'open') {
        return <String, Object?>{'token': 'doc-9', 'count': 1};
      }
      expect(call.method, equals('close'));
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(arguments.keys, equals(<String>['token']));
      expect(arguments['token'], equals('doc-9'));
      closes++;
      return null;
    });

    final document = await PlatformPdfPageRenderer().open(bytes);
    await document!.close();
    await document.close();

    expect(closes, equals(1));
  });

  test('renderPage after close answers null without a host call', () async {
    final methods = <String>[];
    answerWith((MethodCall call) async {
      methods.add(call.method);
      return <String, Object?>{'token': 'doc-6', 'count': 1};
    });

    final document = await PlatformPdfPageRenderer().open(bytes);
    await document!.close();

    expect(
      await document.renderPage(0, targetWidth: 800, maxPixels: 1024),
      isNull,
    );
    expect(methods, equals(<String>['open', 'close']));
  });

  test('close without a host answers without throwing', () async {
    answerWith(
      (MethodCall call) async => <String, Object?>{
        'token': 'doc-4',
        'count': 1,
      },
    );

    final document = await PlatformPdfPageRenderer().open(bytes);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    await document!.close();
  });
}
