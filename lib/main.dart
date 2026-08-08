import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'data/services/history_service.dart';
import 'data/services/settings_service.dart';
import 'providers/history_provider.dart';
import 'providers/theme_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // The release build ships with zero INTERNET permission (see
  // android/app/src/main/AndroidManifest.xml) so the app stays fully
  // offline. google_fonts otherwise tries to download the Inter font
  // from Google's CDN at runtime on first use; without network access
  // that call would just fail silently on every launch. Disabling
  // runtime fetching makes the fallback to the platform system font
  // immediate and deterministic instead.
  GoogleFonts.config.allowRuntimeFetching = false;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(SettingsService()),
        ),
        ChangeNotifierProvider(
          create: (_) => HistoryProvider(HistoryService()),
        ),
      ],
      child: const PixUpApp(),
    ),
  );
}
