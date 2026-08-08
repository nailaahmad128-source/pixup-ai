import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
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

      print('REAL-ESRGAN INPUT NAMES: ${_session!.inputNames}');
      print('REAL-ESRGAN OUTPUT NAMES: ${_session!.outputNames}');
      print('REAL-ESRGAN INPUT COUNT: ${_session!.inputCount}');
      print('REAL-ESRGAN OUTPUT COUNT: ${_session!.outputCount}');
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

    final tileSize = AppConstants.realEsrganTileSize;
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

    // Real-ESRGAN: NCHW Float32, normalized 0..1
    final total = 1 * 3 * tile.height * tile.width;
    final data = Float32List(total);

    var index = 0;

    // R channel
    for (var y = 0; y < tile.height; y++) {
      for (var x = 0; x < tile.width; x++) {
        final pixel = tile.getPixel(x, y);
        data[index++] = pixel.r.toDouble() / 255.0;
      }
    }

    // G channel
    for (var y = 0; y < tile.height; y++) {
      for (var x = 0; x < tile.width; x++) {
        final pixel = tile.getPixel(x, y);
        data[index++] = pixel.g.toDouble() / 255.0;
      }
    }

    // B channel
    for (var y = 0; y < tile.height; y++) {
      for (var x = 0; x < tile.width; x++) {
        final pixel = tile.getPixel(x, y);
        data[index++] = pixel.b.toDouble() / 255.0;
      }
    }

    final inputTensor =
        OrtValueTensor.createTensorWithDataList(
      data,
      [
        1,
        3,
        tile.height,
        tile.width,
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
    // Real-ESRGAN output:
    // [1, 3, height, width]

    final batch = nested[0] as List;

    final red = batch[0] as List;
    final green = batch[1] as List;
    final blue = batch[2] as List;

    final height = red.length;
    final width = (red[0] as List).length;

    final result = img.Image(
      width: width,
      height: height,
    );

    for (var y = 0; y < height; y++) {
      final redRow = red[y] as List;
      final greenRow = green[y] as List;
      final blueRow = blue[y] as List;

      for (var x = 0; x < width; x++) {
        final r = _toByte(redRow[x] as num);
        final g = _toByte(greenRow[x] as num);
        final b = _toByte(blueRow[x] as num);

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
