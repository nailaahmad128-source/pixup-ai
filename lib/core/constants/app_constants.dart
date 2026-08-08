/// Centralized, easy-to-edit constants for the whole app.
/// Update store links / policy URLs here once you publish the app.
class AppConstants {
  AppConstants._();

  static const String appName = 'PixUp AI';
  static const String appTagline = 'AI Photo & Video Enhancer';

  // Matches applicationId in android/app/build.gradle.kts. Update both
  // together if you ever rename the package before publishing.
  static const String playStorePackageId = 'com.pixupai.app';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=$playStorePackageId';

  // Must resolve to a real, publicly reachable privacy policy page —
  // required by the Play Console "App content" section before the
  // store listing can go live.
  static const String privacyPolicyUrl = 'https://pixupai.app/privacy-policy';

  static const String supportEmail = 'support@pixupai.app';

  // Local storage keys
  static const String prefsDarkMode = 'pref_dark_mode';
  static const String prefsHistory = 'pref_history_items';

  // ------------------------------------------------------------------
  // Real-ESRGAN (photo) engine configuration
  // ------------------------------------------------------------------
  // Path of the bundled ONNX model asset. Download a real, free,
  // open-source Real-ESRGAN ONNX export and place it here — see
  // README.md → "AI Model Setup". The app performs real neural
  // super-resolution inference; nothing here is simulated.
  static const String realEsrganModelAsset = 'assets/models/ESRGAN.tflite';

  // These MUST match the tensor names baked into whatever ONNX file you
  // bundle (open the .onnx in https://netron.app to confirm). Defaults
  // below match the most common community Real-ESRGAN → ONNX exports.
  static const String realEsrganInputName = 'input.1';
  static const String realEsrganOutputName = 'output';

  // Native upscale factor of the bundled model (Real-ESRGAN is typically
  // trained/exported for a fixed 4x factor).
  static const int realEsrganScale = 4;

  // Tiling keeps memory bounded on mobile GPUs/CPUs — the image is cut
  // into tileSize x tileSize squares (with tilePad pixels of surrounding
  // context) instead of run through the network all at once.
  static const int realEsrganTileSize = 128;
  static const int realEsrganTilePad = 10;

  // Very large photos are downsized (preserving aspect ratio) before
  // being fed to the 4x network, so a 4x output stays within a mobile
  // device's memory/time budget. Increase for higher quality on
  // powerful devices; decrease for older/low-RAM phones.
  static const int realEsrganMaxInputDimension = 1280;

  // ------------------------------------------------------------------
  // FFmpeg (video) engine configuration
  // ------------------------------------------------------------------
  // Real FFmpeg filter chain applied to every enhanced video:
  //  - hqdn3d   : real denoising (removes sensor/compression noise)
  //  - unsharp  : real detail/edge sharpening
  //  - eq       : mild contrast & saturation lift
  //  - scale    : real upscale using high-quality Lanczos resampling
  static const String videoFilterChain =
      'hqdn3d=1.5:1.5:6:6,'
      'unsharp=5:5:0.8:5:5:0.4,'
      'eq=contrast=1.05:saturation=1.12,'
      'scale=trunc(iw*1.5/2)*2:trunc(ih*1.5/2)*2:flags=lanczos';

  // Videos at or under this duration are additionally eligible for the
  // (slower, higher quality) per-frame neural upscaling pipeline, which
  // runs every extracted frame through the same Real-ESRGAN engine used
  // for photos, then re-encodes with the original audio. Above this
  // duration the fast filter-chain pipeline above is used instead, to
  // keep processing time and memory usage reasonable on mobile hardware.
  static const Duration neuralVideoDurationLimit = Duration(seconds: 8);
}
