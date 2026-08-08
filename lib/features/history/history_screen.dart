import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/history_item.dart';
import '../../data/services/media_service.dart';
import '../../providers/history_provider.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Consumer<HistoryProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.items.isEmpty) {
            return const EmptyState(
              icon: Icons.history_rounded,
              title: 'No history yet',
              message:
                  'Photos and videos you enhance will show up here for quick access.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: provider.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = provider.items[index];
              return _HistoryTile(item: item);
            },
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({super.key, required this.item});
  final HistoryItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPhoto = item.type == MediaType.photo;
    final file = File(item.enhancedPath);
    final dateLabel = DateFormat('MMM d, yyyy • h:mm a').format(item.createdAt);

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openViewer(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: isPhoto
                      ? Image.file(file, fit: BoxFit.cover)
                      : Container(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.videocam_rounded,
                            color: scheme.primary,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isPhoto
                              ? Icons.photo_rounded
                              : Icons.video_camera_back_rounded,
                          size: 15,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isPhoto ? 'Enhanced Photo' : 'Enhanced Video',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) => _handleMenu(context, value),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'open', child: Text('Open')),
                  PopupMenuItem(value: 'share', child: Text('Share')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleMenu(BuildContext context, String value) {
    switch (value) {
      case 'open':
        _openViewer(context);
        break;
      case 'share':
        MediaService().shareFile(File(item.enhancedPath));
        break;
      case 'delete':
        _confirmDelete(context);
        break;
    }
  }

  void _openViewer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _HistoryViewerScreen(item: item)),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete item?'),
        content: const Text(
          'This will remove it from your history. The original file on your device will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<HistoryProvider>().delete(item.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _HistoryViewerScreen extends StatelessWidget {
  const _HistoryViewerScreen({super.key, required this.item});
  final HistoryItem item;

  @override
  Widget build(BuildContext context) {
    final isPhoto = item.type == MediaType.photo;
    final file = File(item.enhancedPath);

    return Scaffold(
      appBar: AppBar(
        title: Text(isPhoto ? 'Enhanced Photo' : 'Enhanced Video'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => MediaService().shareFile(file),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: isPhoto
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.file(file, fit: BoxFit.contain),
                  )
                : _SimpleVideoPlayer(file: file),
          ),
        ),
      ),
    );
  }
}

class _SimpleVideoPlayer extends StatefulWidget {
  const _SimpleVideoPlayer({super.key, required this.file});
  final File file;

  @override
  State<_SimpleVideoPlayer> createState() => _SimpleVideoPlayerState();
}

class _SimpleVideoPlayerState extends State<_SimpleVideoPlayer> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const CircularProgressIndicator();
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: GestureDetector(
          onTap: () => setState(() {
            _controller.value.isPlaying
                ? _controller.pause()
                : _controller.play();
          }),
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}
