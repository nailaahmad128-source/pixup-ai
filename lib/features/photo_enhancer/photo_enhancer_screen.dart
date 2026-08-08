import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/before_after_slider.dart';
import '../../core/widgets/loading_overlay.dart';
import '../../core/widgets/primary_gradient_button.dart';
import '../../data/models/history_item.dart';
import '../../data/services/ai_enhancement_types.dart';
import '../../data/services/media_service.dart';
import '../../data/services/real_ai_enhancement_service.dart';
import '../../providers/history_provider.dart';

enum _Stage { pick, preview, done }

class PhotoEnhancerScreen extends StatefulWidget {
  const PhotoEnhancerScreen({super.key});

  @override
  State<PhotoEnhancerScreen> createState() => _PhotoEnhancerScreenState();
}

class _PhotoEnhancerScreenState extends State<PhotoEnhancerScreen> {
  final _mediaService = MediaService();
  final AIEnhancementService _aiService = RealAIEnhancementService();

  _Stage _stage = _Stage.pick;
  File? _original;
  File? _enhanced;
  bool _isProcessing = false;
  double _progress = 0;

  Future<void> _pickImage() async {
    final file = await _mediaService.pickImage();
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
      final result = await _aiService.enhancePhoto(
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
              type: MediaType.photo,
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
      await _mediaService.saveImageToGallery(_enhanced!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to gallery')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save image')),
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
        title: const Text('Enhance Photo'),
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
              message: 'Enhancing your photo…',
              subMessage: '${(_progress * 100).round()}% complete',
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_stage) {
      case _Stage.pick:
        return _PickPrompt(onPick: _pickImage);
      case _Stage.preview:
        return _PreviewBody(
          image: _original!,
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
                gradient: AppGradients.photo,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.add_photo_alternate_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Select a photo to enhance',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'PixUp AI will sharpen details, boost clarity\nand improve overall quality.',
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
                icon: Icons.photo_library_rounded,
                gradient: AppGradients.photo,
                onPressed: onPick,
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
    required this.image,
    required this.onEnhance,
    required this.isProcessing,
  });

  final File image;
  final VoidCallback onEnhance;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.file(
                image,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 20),
          PrimaryGradientButton(
            label: 'AI Enhance',
            icon: Icons.auto_awesome_rounded,
            gradient: AppGradients.photo,
            isLoading: isProcessing,
            onPressed: onEnhance,
          ),
        ],
      ),
    );
  }
}

class _ResultBody extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Expanded(
            child: BeforeAfterSlider(beforeFile: before, afterFile: after),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: PrimaryGradientButton(
                  label: 'Save',
                  icon: Icons.download_rounded,
                  gradient: AppGradients.photo,
                  onPressed: onSave,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
