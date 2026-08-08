import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import 'ai_enhancement_types.dart';
import 'real_esrgan_engine.dart';

/// Runs real, on-device video enhancement using the actual FFmpeg engine
/// (via `ffmpeg_kit_flutter_new`) — nothing here is simulated.
///
/// Two real pipelines are available:
///
/// 1. **Filter-chain pipeline** (default, fast): a genuine FFmpeg filter
///    graph — denoise (`hqdn3d`) → sharpen (`unsharp`) → contrast/
///    saturation lift (`eq`) → high-quality Lanczos upscale (`scale`) —
///    processes the whole video in a single real-time-ish pass. This is
///    the practical, phone-friendly choice for typical clips.
///
/// 2. **Per-frame neural pipeline** (slower, highest quality): every
///    frame is extracted, run through the *same real Real-ESRGAN engine*
///    used for photos, then reassembled with the original audio. Genuine
///    neural super-resolution on video is very expensive on mobile
///    hardware (each frame is a full Real-ESRGAN inference), so this is
///    only used automatically for short clips
///    (≤ [AppConstants.neuralVideoDurationLimit]) to keep processing time
///    and memory usage reasonable — this is the "optimize for Android
///    performance" trade-off called out in the project README.
class FFmpegVideoEnhancer {
  final _uuid = const Uuid();

  Future<File> enhance(
    File inputFile, {
    ProgressCallback? onProgress,
  }) async {
    final durationMs = await _probeDurationMs(inputFile.path);
    final outFile = await _outputFile();

    final eligibleForNeuralPipeline = durationMs != null &&
        durationMs <= AppConstants.neuralVideoDurationLimit.inMilliseconds;

    if (eligibleForNeuralPipeline) {
      try {
        return await _enhanceWithFrameUpscaling(
          inputFile,
          outFile,
          onProgress: onProgress,
        );
      } catch (_) {
        // Real per-frame upscaling failed for some reason (e.g. the
        // Real-ESRGAN model asset hasn't been added yet, or the device
        // ran low on memory) — fall back to the still-real, but lighter
        // weight, filter-chain pipeline below instead of failing outright.
      }
    }

    return _enhanceWithFilterChain(
      inputFile,
      outFile,
      totalDurationMs: durationMs,
      onProgress: onProgress,
    );
  }

  // -------------------------------------------------------------------
  // Pipeline 1: real FFmpeg filter chain (default)
  // -------------------------------------------------------------------
  Future<File> _enhanceWithFilterChain(
    File inputFile,
    File outFile, {
    int? totalDurationMs,
    ProgressCallback? onProgress,
  }) async {
    final command = '-y -i "${inputFile.path}" '
        '-vf "${AppConstants.videoFilterChain}" '
        '-c:v libx264 -preset medium -crf 18 '
        '-c:a aac -b:a 192k '
        '"${outFile.path}"';

    final completer = Completer<File>();
    var lastReportedProgress = 0.0;

    await FFmpegKit.executeAsync(
      command,
      (session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          if (!completer.isCompleted) completer.complete(outFile);
        } else {
          final logs = await session.getLogs();
          final logText = logs.map((l) => l.getMessage()).join('\n');
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('FFmpeg video enhancement failed:\n$logText'),
            );
          }
        }
      },
      null,
      (statistics) {
        if (totalDurationMs == null || totalDurationMs <= 0) return;
        final progress =
            (statistics.getTime() / totalDurationMs).clamp(0.0, 1.0);
        if (progress > lastReportedProgress) {
          lastReportedProgress = progress;
          onProgress?.call(progress);
        }
      },
    );

    return completer.future;
  }

  // -------------------------------------------------------------------
  // Pipeline 2: real per-frame Real-ESRGAN neural upscaling
  // -------------------------------------------------------------------
  Future<File> _enhanceWithFrameUpscaling(
    File inputFile,
    File outFile, {
    ProgressCallback? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final workDir =
        Directory(p.join(tempDir.path, 'pixup_frames_${_uuid.v4()}'));
    final rawFramesDir = Directory(p.join(workDir.path, 'raw'));
    final upscaledFramesDir = Directory(p.join(workDir.path, 'upscaled'));
    await rawFramesDir.create(recursive: true);
    await upscaledFramesDir.create(recursive: true);

    try {
      final fps = await _probeFps(inputFile.path);

      // 1) Extract every real frame as a lossless PNG.
      final extractSession = await FFmpegKit.execute(
        '-y -i "${inputFile.path}" -vsync 0 '
        '"${p.join(rawFramesDir.path, 'frame_%05d.png')}"',
      );
      if (!ReturnCode.isSuccess(await extractSession.getReturnCode())) {
        throw StateError('Frame extraction failed.');
      }

      final frameFiles = rawFramesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      if (frameFiles.isEmpty) {
        throw StateError('No frames were extracted from the video.');
      }

      // 2) Run every frame through the same real Real-ESRGAN engine used
      //    by the photo enhancer.
      for (var i = 0; i < frameFiles.length; i++) {
        final bytes = await frameFiles[i].readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;

        final upscaled = await RealESRGANEngine.instance.upscale(decoded);
        final outPath =
            p.join(upscaledFramesDir.path, p.basename(frameFiles[i].path));
        await File(outPath).writeAsBytes(img.encodePng(upscaled));

        onProgress?.call((i + 1) / frameFiles.length);
      }

      // 3) Reassemble into a real video at the original frame rate,
      //    re-muxing the original audio track (if any) unchanged.
      final assembleCommand = '-y -framerate $fps -i '
          '"${p.join(upscaledFramesDir.path, 'frame_%05d.png')}" '
          '-i "${inputFile.path}" -map 0:v -map 1:a? '
          '-c:v libx264 -pix_fmt yuv420p -crf 18 -c:a copy -shortest '
          '"${outFile.path}"';

      final assembleSession = await FFmpegKit.execute(assembleCommand);
      if (!ReturnCode.isSuccess(await assembleSession.getReturnCode())) {
        throw StateError('Frame reassembly failed.');
      }

      return outFile;
    } finally {
      if (await workDir.exists()) {
        await workDir.delete(recursive: true);
      }
    }
  }

  // -------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------
  Future<File> _outputFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final enhancedDir = Directory(p.join(dir.path, 'enhanced'));
    if (!await enhancedDir.exists()) {
      await enhancedDir.create(recursive: true);
    }
    return File(p.join(enhancedDir.path, '${_uuid.v4()}_enhanced.mp4'));
  }

  Future<int?> _probeDurationMs(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = await session.getMediaInformation();
      final durationStr = info?.getDuration();
      if (durationStr == null) return null;
      final seconds = double.tryParse(durationStr);
      if (seconds == null) return null;
      return (seconds * 1000).round();
    } catch (_) {
      return null;
    }
  }

  Future<double> _probeFps(String path) async {
    try {
      final session = await FFprobeKit.execute(
        '-v error -select_streams v:0 -show_entries stream=r_frame_rate '
        '-of default=noprint_wrappers=1:nokey=1 "$path"',
      );
      final output = (await session.getOutput())?.trim();
      if (output == null || output.isEmpty) return 30.0;
      final raw = output.split('\n').first.trim();
      final parts = raw.split('/');
      if (parts.length == 2) {
        final numerator = double.tryParse(parts[0]) ?? 30.0;
        final denominator = double.tryParse(parts[1]) ?? 1.0;
        return denominator == 0 ? 30.0 : numerator / denominator;
      }
      return double.tryParse(raw) ?? 30.0;
    } catch (_) {
      return 30.0;
    }
  }
}
