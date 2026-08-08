import 'dart:io';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

/// Wraps gallery picking, saving and sharing so screens stay simple.
class MediaService {
  final ImagePicker _picker = ImagePicker();

  Future<File?> pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  Future<File?> pickVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return null;
    return File(picked.path);
  }

  Future<void> saveImageToGallery(File file) async {
    await Gal.putImage(file.path, album: 'PixUp AI');
  }

  Future<void> saveVideoToGallery(File file) async {
    await Gal.putVideo(file.path, album: 'PixUp AI');
  }

  Future<void> shareFile(File file, {String? text}) async {
    // `share_plus: ^10.0.0` (see pubspec.yaml) predates the SharePlus /
    // ShareParams instance API introduced in share_plus 11 — on 10.x the
    // static `Share.shareXFiles` is the correct entry point.
    await Share.shareXFiles([XFile(file.path)], text: text);
  }
}
