import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/gradient_card.dart';
import '../history/history_screen.dart';
import '../photo_enhancer/photo_enhancer_screen.dart';
import '../settings/settings_screen.dart';
import '../video_enhancer/video_enhancer_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: AppGradients.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text(AppConstants.appName),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'What would you like\nto enhance today?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
              ),
              const SizedBox(height: 40),
              GradientCard(
                title: 'Enhance Photo',
                subtitle: 'Sharper, clearer, more vivid — instantly',
                icon: Icons.photo_camera_back_rounded,
                gradient: AppGradients.photo,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PhotoEnhancerScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GradientCard(
                title: 'Enhance Video',
                subtitle: 'Crisp, stabilized, upgraded quality',
                icon: Icons.video_camera_back_rounded,
                gradient: AppGradients.video,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const VideoEnhancerScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
