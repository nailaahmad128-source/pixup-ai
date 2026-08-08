import 'dart:io';
import 'ai_enhancement_types.dart';
import 'ffmpeg_video_enhancer.dart';
import 'real_esrgan_engine.dart';

/// The app's real, on-device AI enhancement engine.
///
/// - Photos are enhanced by [RealESRGANEngine] — a genuine Real-ESRGAN
///   neural network run entirely on-device via ONNX Runtime.
/// - Videos are enhanced by [FFmpegVideoEnhancer] — a real FFmpeg
///   pipeline, optionally combined with the same Real-ESRGAN engine for
///   frame-by-frame neural upscaling on short clips.
///
/// Both engines process real files with real algorithms; nothing in this
/// class simulates or fakes a result. Screens depend only on the
/// [AIEnhancementService] interface, so this class (or a future
/// alternative implementation) is a drop-in swap.
class RealAIEnhancementService implements AIEnhancementService {
  RealAIEnhancementService({
    RealESRGANEngine? photoEngine,
    FFmpegVideoEnhancer? videoEngine,
  })  : _photoEngine = photoEngine ?? RealESRGANEngine.instance,
        _videoEngine = videoEngine ?? FFmpegVideoEnhancer();

  final RealESRGANEngine _photoEngine;
  final FFmpegVideoEnhancer _videoEngine;

  @override
  Future<File> enhancePhoto(File input, {ProgressCallback? onProgress}) {
    return _photoEngine.enhance(input, onProgress: onProgress);
  }

  @override
  Future<File> enhanceVideo(File input, {ProgressCallback? onProgress}) {
    return _videoEngine.enhance(input, onProgress: onProgress);
  }
}
