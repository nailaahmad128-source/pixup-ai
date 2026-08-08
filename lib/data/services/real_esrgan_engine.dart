import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import 'ai_enhancement_types.dart';

class RealESRGANEngine {
  RealESRGANEngine._internal();

  static final RealESRGANEngine instance = RealESRGANEngine._internal();

  OrtSession? _session;
  Future<void>? _loadFuture;
  final _uuid = const Uuid();

  Future<void> _ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    OrtEnv.instance.init();

    final sessionOptions = OrtSessionOptions();

    try {
      final raw = await rootBundle.load(
        AppConstants.realEsrganModelAsset,
      );

      final bytes = raw.buffer.asUint8List();

      _session = OrtSession.fromBuffer(
        bytes,
        sessionOptions,
      );
    } catch (e) {
      _loadFuture = null;

      throw StateError(
        'Failed to load Real-ESRGAN model: $e',
      );
    }
  }

  void dispose() {
    _session?.release();
    _session = null;
    _loadFuture = null;
    OrtEnv.instance.release();
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

    if (longestSide > AppConstants.realEsrganMaxInputDimension) {
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

    const tileSize = 256;
    const scale = 4;

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
    final session = _session!;

    final inputData =
        List.generate(1, (_) {
      return List.generate(
        tile.height,
        (y) {
          return List.generate(
            tile.width,
            (x) {
              final pixel =
                  tile.getPixel(x, y);

              return <int>[
                pixel.r.toInt(),
                pixel.g.toInt(),
                pixel.b.toInt(),
              ];
            },
          );
        },
      );
    });

    final inputTensor =
        OrtValueTensor.createTensorWithDataList(
      inputData,
      [
        1,
        tile.height,
        tile.width,
        3,
      ],
    );

    final runOptions = OrtRunOptions();

    List<OrtValue?>? outputs;

    try {
      outputs = await session.runAsync(
        runOptions,
        {
          AppConstants.realEsrganInputName:
              inputTensor,
        },
      );
    } finally {
      inputTensor.release();
      runOptions.release();
    }

    if (outputs == null ||
        outputs.isEmpty ||
        outputs.first == null) {
      throw StateError(
        'Real-ESRGAN returned no output.',
      );
    }

    final outputTensor = outputs.first!;

    try {
      final raw = outputTensor.value;

      return _outputToImage(
        raw as List,
      );
    } finally {
      for (final output in outputs) {
        output?.release();
      }
    }
  }

  img.Image _outputToImage(
    List nested,
  ) {
    final batch = nested[0] as List;

    final height = batch.length;
    final width =
        (batch[0] as List).length;

    final result = img.Image(
      width: width,
      height: height,
    );

    for (var y = 0; y < height; y++) {
      final row = batch[y] as List;

      for (var x = 0; x < width; x++) {
        final pixel = row[x] as List;

        final r = _toByte(
          pixel[0] as num,
        );

        final g = _toByte(
          pixel[1] as num,
        );

        final b = _toByte(
          pixel[2] as num,
        );

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

  int _toByte(num value) {
    return (value
            .toDouble()
            .clamp(0.0, 1.0) *
        255)
        .round();
  }
}
