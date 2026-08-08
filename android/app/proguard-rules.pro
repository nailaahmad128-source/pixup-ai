# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# ONNX Runtime — native methods are resolved via JNI by class/method name,
# so they must survive minification/obfuscation.
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# ffmpeg_kit_flutter_new — same JNI-bridge concern. The fork kept the
# original com.arthenica.ffmpegkit native namespace; double-check this
# against the version actually resolved in your pub-cache if it differs.
-keep class com.arthenica.ffmpegkit.** { *; }
-dontwarn com.arthenica.ffmpegkit.**

# Keep model classes serialized via reflection (history JSON round-trip
# already uses manual toJson/fromJson, but keep enums safe regardless).
-keepclassmembers enum * { *; }
