import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
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
      final raw = await rootBundle.load(
        AppConstants.realEsrganModelAsset,
      );

      _interpreter = Interpreter.fromBuffer(
        raw.buffer.asUint8List(),
      );

      _interpreter!.allocateTensors();

      final input = _interpreter!.getInputTensor(0);
      final output = _interpreter!.getOutputTensor(0);

      print('REAL-ESRGAN TFLITE INPUT: ${input.shape}');
      print('REAL-ESRGAN TFLITE INPUT TYPE: ${input.type}');
      print('REAL-ESRGAN TFLITE OUTPUT: ${output.shape}');
      print('REAL-ESRGAN TFLITE OUTPUT TYPE: ${output.type}');

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

    const scale = 4;
    final tileSize =
        AppConstants.realEsrganTileSize;

    final tilesX =
        (source.width / tileSize).ceil();

    final tilesY =
        (source.height / tileSize).ceil();

    final totalTiles =
        max(1, tilesX * tilesY);

    var done = 0;

    final output = img.Image(
      width: source.width * scale,
      height: source.height * scale,
    );

    for (var ty = 0; ty < tilesY; ty++) {
      for (var tx = 0; tx < tilesX; tx++) {
        final x = tx * tileSize;
        final y = ty * tileSize;

        final tileW = min(
          tileSize,
          source.width - x,
        );

        final tileH = min(
          tileSize,
          source.height - y,
        );

        final padded = img.Image(
          width: tileSize,
          height: tileSize,
        );

        for (var py = 0; py < tileH; py++) {
          for (var px = 0; px < tileW; px++) {
            final pixel =
                source.getPixel(x + px, y + py);

            padded.setPixelRgb(
              px,
              py,
              pixel.r.toInt(),
              pixel.g.toInt(),
              pixel.b.toInt(),
            );
          }
        }

        final enhanced =
            await _runInference(padded);

        final cropped = img.copyCrop(
          enhanced,
          x: 0,
          y: 0,
          width: tileW * scale,
          height: tileH * scale,
        );

        img.compositeImage(
          output,
          cropped,
          dstX: x * scale,
          dstY: y * scale,
        );

        done++;

        onProgress?.call(
          done / totalTiles,
        );
      }
    }

    return output;
  }

  Future<img.Image> _runInference(
    img.Image tile,
  ) async {
    final interpreter = _interpreter!;

    final inputShape =
        interpreter.getInputTensor(0).shape;

    print(
      'REAL-ESRGAN RUN INPUT SHAPE: $inputShape',
    );

    final height = tile.height;
    final width = tile.width;

    final input = List.generate(
      1,
      (_) => List.generate(
        height,
        (y) => List.generate(
          width,
          (x) {
            final pixel =
                tile.getPixel(x, y);

            return [
              pixel.r.toDouble() / 255.0,
              pixel.g.toDouble() / 255.0,
              pixel.b.toDouble() / 255.0,
            ];
          },
        ),
      ),
    );

    final outputTensor =
        interpreter.getOutputTensor(0);

    final outputShape =
        outputTensor.shape;

    final output = _makeNestedFloatList(
      outputShape,
    );

    interpreter.run(
      input,
      output,
    );

    return _outputToImage(
      output,
      outputShape,
    );
  }

  dynamic _makeNestedFloatList(
    List<int> shape,
  ) {
    if (shape.length == 1) {
      return List<double>.filled(
        shape[0],
        0.0,
      );
    }

    return List.generate(
      shape[0],
      (_) => _makeNestedFloatList(
        shape.sublist(1),
      ),
    );
  }

  img.Image _outputToImage(
    dynamic nested,
    List<int> shape,
  ) {
    if (shape.length != 4) {
      throw StateError(
        'Unexpected Real-ESRGAN output shape: $shape',
      );
    }

    final data = nested[0];

    final channelsFirst =
        shape[1] == 3;

    late int height;
    late int width;

    if (channelsFirst) {
      height = shape[2];
      width = shape[3];
    } else {
      height = shape[1];
      width = shape[2];
    }

    final result = img.Image(
      width: width,
      height: height,
    );

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        double r;
        double g;
        double b;

        if (channelsFirst) {
          r = data[0][y][x].toDouble();
          g = data[1][y][x].toDouble();
          b = data[2][y][x].toDouble();
        } else {
          r = data[y][x][0].toDouble();
          g = data[y][x][1].toDouble();
          b = data[y][x][2].toDouble();
        }

        result.setPixelRgb(
          x,
          y,
          _toByte(r),
          _toByte(g),
          _toByte(b),
        );
      }
    }

    return result;
  }

  int _toByte(double value) {
    return (value.clamp(0.0, 1.0) * 255).round();
  }
}
