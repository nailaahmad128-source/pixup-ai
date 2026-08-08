import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionLabel('Appearance'),
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: Icon(Icons.dark_mode_rounded, color: scheme.primary),
                title: const Text('Dark Mode'),
                subtitle: const Text('Switch between light and dark theme'),
                value: themeProvider.isDarkMode,
                onChanged: (value) => themeProvider.setDarkMode(value),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionLabel('Support PixUp AI'),
          _SettingsCard(
            children: [
              ListTile(
                leading: Icon(Icons.star_rounded, color: scheme.primary),
                title: const Text('Rate App'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openUrl(AppConstants.playStoreUrl),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.share_rounded, color: scheme.primary),
                title: const Text('Share App'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Share.share(
                  'Check out ${AppConstants.appName} — an amazing AI photo & video enhancer!\n${AppConstants.playStoreUrl}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionLabel('About'),
          _SettingsCard(
            children: [
              ListTile(
                leading: Icon(Icons.privacy_tip_rounded, color: scheme.primary),
                title: const Text('Privacy Policy'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openUrl(AppConstants.privacyPolicyUrl),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.info_rounded, color: scheme.primary),
                title: const Text('About'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showAbout(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '${AppConstants.appName} v1.0.0',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: AppGradients.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
      ),
      children: const [
        SizedBox(height: 12),
        Text(
          'PixUp AI helps you instantly improve the quality of your '
          'photos and videos using on-device AI enhancement — no '
          'clutter, no distractions, just better looking media.',
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
