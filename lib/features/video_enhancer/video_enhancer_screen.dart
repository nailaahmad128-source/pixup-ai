import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/loading_overlay.dart';
import '../../core/widgets/primary_gradient_button.dart';
import '../../data/models/history_item.dart';
import '../../data/services/ai_enhancement_types.dart';
import '../../data/services/media_service.dart';
import '../../data/services/real_ai_enhancement_service.dart';
import '../../providers/history_provider.dart';

enum _Stage { pick, preview, done }

class VideoEnhancerScreen extends StatefulWidget {
  const VideoEnhancerScreen({super.key});

  @override
  State<VideoEnhancerScreen> createState() => _VideoEnhancerScreenState();
}

class _VideoEnhancerScreenState extends State<VideoEnhancerScreen> {
  final _mediaService = MediaService();
  final AIEnhancementService _aiService = RealAIEnhancementService();

  _Stage _stage = _Stage.pick;
  File? _original;
  File? _enhanced;
  bool _isProcessing = false;
  double _progress = 0;

  Future<void> _pickVideo() async {
    final file = await _mediaService.pickVideo();
    if (file == null) return;
    setState(() {
      _original = file;
      _enhanced = null;
      _stage = _Stage.preview;
    });
  }

  Future<void> _enhance() async {
    if (_original == null) return;
    setState(() {
      _isProcessing = true;
      _progress = 0;
    });

    try {
      final result = await _aiService.enhanceVideo(
        _original!,
        onProgress: (p) => setState(() => _progress = p),
      );

      if (!mounted) return;
      setState(() {
        _enhanced = result;
        _isProcessing = false;
        _stage = _Stage.done;
      });

      await context.read<HistoryProvider>().add(
            HistoryItem(
              id: const Uuid().v4(),
              type: MediaType.video,
              originalPath: _original!.path,
              enhancedPath: result.path,
              createdAt: DateTime.now(),
            ),
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enhancement failed: $e')),
      );
    }
  }

  Future<void> _save() async {
    if (_enhanced == null) return;
    try {
      await _mediaService.saveVideoToGallery(_enhanced!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to gallery')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save video')),
      );
    }
  }

  Future<void> _share() async {
    if (_enhanced == null) return;
    await _mediaService.shareFile(
      _enhanced!,
      text: 'Enhanced with PixUp AI ✨',
    );
  }

  void _reset() {
    setState(() {
      _original = null;
      _enhanced = null;
      _stage = _Stage.pick;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enhance Video'),
        actions: [
          if (_stage != _Stage.pick)
            IconButton(
              tooltip: 'Start over',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _reset,
            ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(child: _buildBody(context)),
          if (_isProcessing)
            LoadingOverlay(
              message: 'Enhancing your video…',
              subMessage: '${(_progress * 100).round()}% complete',
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_stage) {
      case _Stage.pick:
        return _PickPrompt(onPick: _pickVideo);
      case _Stage.preview:
        return _PreviewBody(
          key: ValueKey(_original!.path),
          video: _original!,
          onEnhance: _enhance,
          isProcessing: _isProcessing,
        );
      case _Stage.done:
        return _ResultBody(
          before: _original!,
          after: _enhanced!,
          onSave: _save,
          onShare: _share,
        );
    }
  }
}

class _PickPrompt extends StatelessWidget {
  const _PickPrompt({super.key, required this.onPick});
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                gradient: AppGradients.video,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.video_library_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Select a video to enhance',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'PixUp AI will improve clarity, sharpness\nand overall video quality.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PrimaryGradientButton(
                label: 'Choose from Gallery',
                icon: Icons.video_library_outlined,
                gradient: AppGradients.video,
                onPressed: onPick,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared video preview player used by both the "preview" and
/// "result" stages of the video enhancer flow.
class _VideoPreview extends StatefulWidget {
  const _VideoPreview({super.key, required this.file});
  final File file;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
      });
  }

  @override
  void didUpdateWidget(covariant _VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      final oldController = _controller;
      setState(() => _ready = false);
      _controller = VideoPlayerController.file(widget.file)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() => _ready = true);
        });
      oldController.dispose();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _controller.value.isPlaying
                ? _controller.pause()
                : _controller.play();
          });
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: _controller.value.aspectRatio == 0
                  ? 16 / 9
                  : _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
            if (!_controller.value.isPlaying)
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({
    super.key,
    required this.video,
    required this.onEnhance,
    required this.isProcessing,
  });

  final File video;
  final VoidCallback onEnhance;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Expanded(child: Center(child: _VideoPreview(file: video))),
          const SizedBox(height: 20),
          PrimaryGradientButton(
            label: 'AI Enhance',
            icon: Icons.auto_awesome_rounded,
            gradient: AppGradients.video,
            isLoading: isProcessing,
            onPressed: onEnhance,
          ),
        ],
      ),
    );
  }
}

class _ResultBody extends StatefulWidget {
  const _ResultBody({
    super.key,
    required this.before,
    required this.after,
    required this.onSave,
    required this.onShare,
  });

  final File before;
  final File after;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  State<_ResultBody> createState() => _ResultBodyState();
}

class _ResultBodyState extends State<_ResultBody> {
  bool _showingAfter = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeFile = _showingAfter ? widget.after : widget.before;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _ToggleTab(
                  label: 'Before',
                  selected: !_showingAfter,
                  onTap: () => setState(() => _showingAfter = false),
                ),
                _ToggleTab(
                  label: 'After',
                  selected: _showingAfter,
                  onTap: () => setState(() => _showingAfter = true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: _VideoPreview(key: ValueKey(activeFile.path), file: activeFile),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onShare,
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: PrimaryGradientButton(
                  label: 'Save',
                  icon: Icons.download_rounded,
                  gradient: AppGradients.video,
                  onPressed: widget.onSave,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  const _ToggleTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
