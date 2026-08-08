import 'dart:io';

/// Reports progress (0.0 - 1.0) while a photo/video is being enhanced.
typedef ProgressCallback = void Function(double progress);

/// Contract every screen talks to. Both the photo and video enhancer
/// screens depend only on this interface — never on a concrete engine —
/// so the underlying AI/processing implementation can be swapped or
/// upgraded (e.g. a different model, a cloud fallback, GPU delegate
/// tuning) without touching any UI code.
abstract class AIEnhancementService {
  Future<File> enhancePhoto(File input, {ProgressCallback? onProgress});

  Future<File> enhanceVideo(File input, {ProgressCallback? onProgress});
}
