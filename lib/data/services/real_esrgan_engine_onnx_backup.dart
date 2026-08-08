import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import 'ai_enhancement_types.dart';

class RealESRGANEngine {
  RealESRGANEngine._internal();

  static final RealESRGANEngine instance =
      RealESRGANEngine._internal();

  Interpreter? _interpreter;
  Future<void>? _loadFuture;

  final _uuid = const Uuid();

  Future<void> _ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        AppConstants.realEsrganModelAsset,
      );

      final input = _interpreter!.getInputTensor(0);
      final output = _interpreter!.getOutputTensor(0);

      print('REAL-ESRGAN TFLITE LOADED');
      print('INPUT SHAPE: ${input.shape}');
      print('INPUT TYPE: ${input.type}');
      print('OUTPUT SHAPE: ${output.shape}');
      print('OUTPUT TYPE: ${output.type}');
    } catch (e) {
      _loadFuture = null;
      throw StateError(
        'Failed to load Real-ESRGAN TFLite model: $e',
      );
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _loadFuture = null;
  }

  Future<File> enhance(
    File inputFile, {
    ProgressCallback? onProgress,
  }) async {
    await _ensureLoaded();

    final bytes = await inputFile.readAsBytes();

    var decoded = img.decodeImage(bytes);

    if (decoded == null) {
      throw const FormatException(
        'Could not decode the selected image.',
      );
    }

    final longestSide = max(
      decoded.width,
      decoded.height,
    );

    if (longestSide >
        AppConstants.realEsrganMaxInputDimension) {
      final ratio =
          AppConstants.realEsrganMaxInputDimension /
          longestSide;

      decoded = img.copyResize(
        decoded,
        width: (decoded.width * ratio).round(),
        height: (decoded.height * ratio).round(),
        interpolation: img.Interpolation.cubic,
      );
    }

    final result = await upscale(
      decoded,
      onProgress: onProgress,
    );

    final dir = await getApplicationDocumentsDirectory();

    final enhancedDir = Directory(
      p.join(dir.path, 'enhanced'),
    );

    if (!await enhancedDir.exists()) {
      await enhancedDir.create(recursive: true);
    }

    final outPath = p.join(
      enhancedDir.path,
      '${_uuid.v4()}_enhanced.jpg',
    );

    final outputBytes = img.encodeJpg(
      result,
      quality: 95,
    );

    final outFile = File(outPath);

    await outFile.writeAsBytes(outputBytes);

    return outFile;
  }

  Future<img.Image> upscale(
    img.Image source, {
    ProgressCallback? onProgress,
  }) async {
    await _ensureLoaded();

    final interpreter = _interpreter!;

    final inputShape =
        interpreter.getInputTensor(0).shape;

    final outputShape =
        interpreter.getOutputTensor(0).shape;

    if (inputShape.length != 4 ||
        outputShape.length != 4) {
      throw StateError(
        'Unexpected ESRGAN tensor shape. '
        'Input=$inputShape Output=$outputShape',
      );
    }

    // Official ESRGAN TFLite model:
    // Input  = [1, 50, 50, 3]
    // Output = [1, 200, 200, 3]
    final tileH = inputShape[1];
    final tileW = inputShape[2];

    final outputH = outputShape[1];
    final outputW = outputShape[2];

    final scaleX = outputW ~/ tileW;
    final scaleY = outputH ~/ tileH;

    if (inputShape[0] != 1 ||
        inputShape[3] != 3 ||
        outputShape[0] != 1 ||
        outputShape[3] != 3 ||
        scaleX != 4 ||
        scaleY != 4) {
      throw StateError(
        'Unsupported ESRGAN model shape. '
        'Input=$inputShape Output=$outputShape',
      );
    }

    final tilesX =
        (source.width / tileW).ceil();

    final tilesY =
        (source.height / tileH).ceil();

    final totalTiles =
        max(1, tilesX * tilesY);

    var done = 0;

    final output = img.Image(
      width: source.width * 4,
      height: source.height * 4,
    );

    for (var ty = 0; ty < tilesY; ty++) {
      for (var tx = 0; tx < tilesX; tx++) {
        final x = tx * tileW;
        final y = ty * tileH;

        final actualW = min(
          tileW,
          source.width - x,
        );

        final actualH = min(
          tileH,
          source.height - y,
        );

        // NHWC input:
        // [1, height, width, RGB]
        //
        // The model requires exactly 50x50.
        // For edge tiles we repeat the edge pixels.
        final input = List.generate(
          1,
          (_) => List.generate(
            tileH,
            (py) => List.generate(
              tileW,
              (px) {
                final sx =
                    min(px, actualW - 1);
                final sy =
                    min(py, actualH - 1);

                final pixel =
                    source.getPixel(
                  x + sx,
                  y + sy,
                );

                return <double>[
                  pixel.r.toDouble(),
                  pixel.g.toDouble(),
                  pixel.b.toDouble(),
                ];
              },
            ),
          ),
        );

        final outputBuffer = List.generate(
          1,
          (_) => List.generate(
            outputH,
            (_) => List.generate(
              outputW,
              (_) => List<double>.filled(3, 0.0),
            ),
          ),
        );

        interpreter.run(
          input,
          outputBuffer,
        );

        final enhanced =
            _outputToImage(
          outputBuffer,
          outputH,
          outputW,
        );

        final cropped = img.copyCrop(
          enhanced,
          x: 0,
          y: 0,
          width: actualW * 4,
          height: actualH * 4,
        );

        img.compositeImage(
          output,
          cropped,
          dstX: x * 4,
          dstY: y * 4,
        );

        done++;

        onProgress?.call(
          done / totalTiles,
        );
      }
    }

    return output;
  }

  img.Image _outputToImage(
    dynamic raw,
    int height,
    int width,
  ) {
    final batch = raw[0];

    final result = img.Image(
      width: width,
      height: height,
    );

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = batch[y][x];

        final r =
            _toByte(pixel[0]);
        final g =
            _toByte(pixel[1]);
        final b =
            _toByte(pixel[2]);

        result.setPixelRgb(
          x,
          y,
          r,
          g,
          b,
        );
      }
    }

    return result;
  }

  int _toByte(dynamic value) {
    final v = (value as num).toDouble();

    return v
        .clamp(0.0, 255.0)
        .round();
  }
}
