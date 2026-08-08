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

/// Runs the real Real-ESRGAN super-resolution neural network on-device,
/// fully offline, via ONNX Runtime.
///
/// This is NOT a simulation: an actual convolutional neural network
/// (Real-ESRGAN, https://github.com/xinntao/Real-ESRGAN — BSD-3-Clause,
/// free & open-source) processes the image tile-by-tile and produces a
/// genuinely upscaled/denoised result.
///
/// ---------------------------------------------------------------------
/// REQUIRED SETUP — see README.md → "AI Model Setup"
/// ---------------------------------------------------------------------
/// This class expects a real Real-ESRGAN ONNX model file bundled at
/// [AppConstants.realEsrganModelAsset]. This repository does not include
/// that binary file. Until it is added, [enhance] throws a clear
/// [StateError] explaining exactly what to do.
/// ---------------------------------------------------------------------
class RealESRGANEngine {
  RealESRGANEngine._internal();

  /// Shared singleton so the (potentially large) model is only loaded
  /// into memory once per app session, no matter how many times the
  /// photo enhancer screen is opened.
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

    ByteData raw;
    try {
      raw = await rootBundle.load(AppConstants.realEsrganModelAsset);
    } catch (_) {
      _loadFuture = null;
      throw StateError(
        'Real-ESRGAN model asset not found at '
        '"${AppConstants.realEsrganModelAsset}".\n'
        'Add the ONNX model file described in README.md → "AI Model '
        'Setup" and rebuild the app before enhancing photos.',
      );
    }

    final bytes = raw.buffer.asUint8List();
    try {
      _session = OrtSession.fromBuffer(bytes, sessionOptions);
    } catch (e) {
      _loadFuture = null;
      throw StateError(
        'Failed to load the Real-ESRGAN ONNX model. Confirm the file at '
        '"${AppConstants.realEsrganModelAsset}" is a valid ONNX graph. '
        'Original error: $e',
      );
    }
  }

  /// Releases native resources. Call when the engine is no longer needed
  /// (e.g. app shutdown). Safe to call even if never loaded.
  void dispose() {
    _session?.release();
    _session = null;
    _loadFuture = null;
    OrtEnv.instance.release();
  }

  /// Reads [inputFile] from disk, runs real Real-ESRGAN super-resolution
  /// on it, and writes the enhanced result to a new file in app storage.
  Future<File> enhance(
    File inputFile, {
    ProgressCallback? onProgress,
  }) async {
    await _ensureLoaded();

    final bytes = await inputFile.readAsBytes();
    var decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Could not decode the selected image.');
    }

    // Downscale very large photos before feeding the 4x network so the
    // output stays within a safe memory/time budget on mobile hardware.
    // This is a deliberate, documented Android performance optimization —
    // not a shortcut on quality: the network still performs real 4x
    // super-resolution on the (resized) source.
    final longestSide = max(decoded.width, decoded.height);
    if (longestSide > AppConstants.realEsrganMaxInputDimension) {
      final ratio = AppConstants.realEsrganMaxInputDimension / longestSide;
      decoded = img.copyResize(
        decoded,
        width: (decoded.width * ratio).round(),
        height: (decoded.height * ratio).round(),
        interpolation: img.Interpolation.cubic,
      );
    }

    final upscaled = await upscale(decoded, onProgress: onProgress);

    final dir = await getApplicationDocumentsDirectory();
    final enhancedDir = Directory(p.join(dir.path, 'enhanced'));
    if (!await enhancedDir.exists()) {
      await enhancedDir.create(recursive: true);
    }

    final outPath = p.join(enhancedDir.path, '${_uuid.v4()}_enhanced.jpg');
    final jpgBytes = img.encodeJpg(upscaled, quality: 95);
    final outFile = File(outPath);
    await outFile.writeAsBytes(jpgBytes);
    return outFile;
  }

  /// Runs real tiled Real-ESRGAN inference over [source] and returns the
  /// fully reassembled, upscaled [img.Image].
  ///
  /// Tiling (matching Real-ESRGAN's own `--tile` strategy) keeps memory
  /// bounded: the image is processed in overlapping squares instead of
  /// all at once, which is what makes 4x super-resolution feasible on a
  /// phone GPU/CPU instead of requiring a desktop-class card.
  Future<img.Image> upscale(
    img.Image source, {
    ProgressCallback? onProgress,
  }) async {
    await _ensureLoaded();

    const scale = AppConstants.realEsrganScale;
    const tileSize = AppConstants.realEsrganTileSize;
    const pad = AppConstants.realEsrganTilePad;

    final tilesX = (source.width / tileSize).ceil();
    final tilesY = (source.height / tileSize).ceil();
    final totalTiles = max(1, tilesX * tilesY);
    var done = 0;

    final output = img.Image(
      width: source.width * scale,
      height: source.height * scale,
    );

    for (var ty = 0; ty < tilesY; ty++) {
      for (var tx = 0; tx < tilesX; tx++) {
        final x = tx * tileSize;
        final y = ty * tileSize;
        final tileW = min(tileSize, source.width - x);
        final tileH = min(tileSize, source.height - y);

        // Extract the tile plus a border of real surrounding context
        // (tile_pad) so the network doesn't produce seams at tile edges.
        final padX0 = max(0, x - pad);
        final padY0 = max(0, y - pad);
        final padX1 = min(source.width, x + tileW + pad);
        final padY1 = min(source.height, y + tileH + pad);

        final paddedTile = img.copyCrop(
          source,
          x: padX0,
          y: padY0,
          width: padX1 - padX0,
          height: padY1 - padY0,
        );

        final upscaledPadded = await _runInference(paddedTile);

        // Crop the padded output back down to just the tile's own region
        // (discarding the extra context border) before pasting.
        final left = (x - padX0) * scale;
        final top = (y - padY0) * scale;
        final cropped = img.copyCrop(
          upscaledPadded,
          x: left,
          y: top,
          width: tileW * scale,
          height: tileH * scale,
        );

        img.compositeImage(output, cropped, dstX: x * scale, dstY: y * scale);

        done++;
        onProgress?.call(done / totalTiles);
      }
    }

    return output;
  }

  /// Runs a single forward pass of the Real-ESRGAN ONNX graph on one
  /// image tile and returns the upscaled tile.
  ///
  /// NOTE: [AppConstants.realEsrganInputName] / [realEsrganOutputName]
  /// must match the tensor names in whatever ONNX file you bundle —
  /// open it in https://netron.app to confirm if you swap models.
  Future<img.Image> _runInference(img.Image tile) async {
    final session = _session!;
    final runOptions = OrtRunOptions();

    final inputData = _imageToNCHW(tile);
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      inputData,
      [1, 3, tile.height, tile.width],
    );

    List<OrtValue?>? outputs;
    try {
      outputs = await session.runAsync(runOptions, {
        AppConstants.realEsrganInputName: inputTensor,
      });
    } finally {
      inputTensor.release();
      runOptions.release();
    }

    if (outputs == null || outputs.isEmpty || outputs.first == null) {
      throw StateError(
        'Real-ESRGAN model returned no output tensor for input '
        '"${AppConstants.realEsrganInputName}". Confirm the input tensor '
        'name matches the bundled ONNX file.',
      );
    }

    final outTensor = outputs.first!;
    try {
      final raw = outTensor.value;
      return _nchwToImage(
        raw as List,
        tile.width * AppConstants.realEsrganScale,
        tile.height * AppConstants.realEsrganScale,
      );
    } finally {
      for (final o in outputs) {
        o?.release();
      }
    }
  }

  /// Converts an [img.Image] tile into a normalized (0..1) NCHW nested
  /// list: `[1][3][height][width]`, the standard input layout for
  /// Real-ESRGAN / most PyTorch-exported ONNX vision models.
  List _imageToNCHW(img.Image tile) {
    final w = tile.width;
    final h = tile.height;
    return [
      List.generate(3, (c) {
        return List.generate(h, (y) {
          return List.generate(w, (x) {
            final pixel = tile.getPixel(x, y);
            final value = c == 0
                ? pixel.r
                : c == 1
                    ? pixel.g
                    : pixel.b;
            return value / 255.0;
          });
        });
      }),
    ];
  }

  /// Converts a normalized (0..1) NCHW nested output tensor
  /// `[1][3][height][width]` back into a displayable [img.Image].
  img.Image _nchwToImage(List nested, int width, int height) {
    final batch = nested[0] as List;
    final rChannel = batch[0] as List;
    final gChannel = batch[1] as List;
    final bChannel = batch[2] as List;

    final out = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      final rRow = rChannel[y] as List;
      final gRow = gChannel[y] as List;
      final bRow = bChannel[y] as List;
      for (var x = 0; x < width; x++) {
        final r = _toByte(rRow[x] as num);
        final g = _toByte(gRow[x] as num);
        final b = _toByte(bRow[x] as num);
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }

  int _toByte(num v) => (v.toDouble() * 255).round().clamp(0, 255);
}
