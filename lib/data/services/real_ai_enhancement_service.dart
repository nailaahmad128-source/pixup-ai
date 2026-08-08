import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ai_enhancement_types.dart';

class RealAIEnhancementService implements AIEnhancementService {
  static const _apiBase = 'https://api.replicate.com/v1';
  static const _model = 'google/nano-banana-2-lite';

  static const _token =
      String.fromEnvironment('REPLICATE_API_TOKEN');

  static const _defaultPrompt = '''
Restore and clean this exact photograph.

Remove blur, digital noise, compression artifacts, dust,
scratches and mild haze.

Improve natural sharpness, fine details, exposure and clarity
while keeping the photograph realistic.

Preserve the exact person's identity, facial structure, age,
skin texture, expression, hairstyle, clothing, pose, colors,
objects and background.

Do not invent, replace, beautify, reshape or change the face.
Do not add or remove people or objects.
Do not change the composition.

This is a photo restoration and enhancement task,
not a creative re-generation.

Return a natural, high-quality cleaned version
of the original photograph.
''';

  final HttpClient _client = HttpClient();

  @override
  Future<File> enhancePhoto(
    File input, {
    ProgressCallback? onProgress,
  }) async {
    if (_token.isEmpty) {
      throw StateError(
        'REPLICATE_API_TOKEN is missing. '
        'Build with --dart-define=REPLICATE_API_TOKEN=YOUR_TOKEN',
      );
    }

    onProgress?.call(0.05);

    final dataUri = await _makeSmallDataUri(input);

    onProgress?.call(0.15);

    final request = await _client.postUrl(
      Uri.parse(
        '$_apiBase/models/$_model/predictions',
      ),
    );

    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $_token',
    );

    request.headers.contentType = ContentType.json;

    request.headers.set(
      'Prefer',
      'wait=60',
    );

    request.write(
      jsonEncode({
        'input': {
          'prompt': _defaultPrompt,
          'image_input': [dataUri],
          'aspect_ratio': 'match_input_image',
          'output_format': 'jpg',
        },
      }),
    );

    final response = await request.close();

    final body =
        await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw StateError(
        'Replicate ${response.statusCode}: $body',
      );
    }

    var prediction =
        jsonDecode(body) as Map<String, dynamic>;

    onProgress?.call(0.35);

    var status =
        prediction['status']?.toString() ?? '';

    final id =
        prediction['id']?.toString();

    if (id == null || id.isEmpty) {
      throw StateError(
        'Replicate returned no prediction id.',
      );
    }

    for (
      var i = 0;
      i < 60 && status != 'succeeded';
      i++
    ) {
      if (status == 'failed' ||
          status == 'canceled') {
        throw StateError(
          'AI enhancement $status: '
          '${prediction['error'] ?? 'unknown error'}',
        );
      }

      await Future<void>.delayed(
        const Duration(seconds: 2),
      );

      final poll = await _client.getUrl(
        Uri.parse(
          '$_apiBase/predictions/$id',
        ),
      );

      poll.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $_token',
      );

      final pollResponse =
          await poll.close();

      final pollBody =
          await pollResponse
              .transform(utf8.decoder)
              .join();

      if (pollResponse.statusCode < 200 ||
          pollResponse.statusCode >= 300) {
        throw StateError(
          'Replicate poll '
          '${pollResponse.statusCode}: '
          '$pollBody',
        );
      }

      prediction =
          jsonDecode(pollBody)
              as Map<String, dynamic>;

      status =
          prediction['status']?.toString() ?? '';

      onProgress?.call(
        0.35 +
            min(
              0.5,
              (i + 1) / 60 * 0.5,
            ),
      );
    }

    if (status != 'succeeded') {
      throw StateError(
        'AI enhancement timed out. '
        'Last status: $status',
      );
    }

    final output =
        prediction['output'];

    final outputUrl =
        output is String
            ? output
            : output is List &&
                    output.isNotEmpty
                ? output.first.toString()
                : null;

    if (outputUrl == null ||
        outputUrl.isEmpty) {
      throw StateError(
        'Replicate returned no output image.',
      );
    }

    onProgress?.call(0.9);

    final download =
        await _client.getUrl(
      Uri.parse(outputUrl),
    );

    final downloadResponse =
        await download.close();

    final bytes =
        await downloadResponse.fold<List<int>>(
      <int>[],
      (buffer, chunk) =>
          buffer..addAll(chunk),
    );

    if (downloadResponse.statusCode < 200 ||
        downloadResponse.statusCode >= 300) {
      throw StateError(
        'Could not download AI result '
        '(${downloadResponse.statusCode}).',
      );
    }

    final dir =
        await getApplicationDocumentsDirectory();

    final enhancedDir =
        Directory(
      p.join(
        dir.path,
        'enhanced',
      ),
    );

    if (!await enhancedDir.exists()) {
      await enhancedDir.create(
        recursive: true,
      );
    }

    final out =
        File(
      p.join(
        enhancedDir.path,
        'ai_clean_${DateTime.now().microsecondsSinceEpoch}.jpg',
      ),
    );

    await out.writeAsBytes(
      bytes,
      flush: true,
    );

    onProgress?.call(1.0);

    return out;
  }

  Future<String> _makeSmallDataUri(
    File input,
  ) async {
    final original =
        await input.readAsBytes();

    final decoded =
        img.decodeImage(original);

    if (decoded == null) {
      throw const FormatException(
        'Could not decode the selected image.',
      );
    }

    img.Image work = decoded;

    final longest =
        max(
      work.width,
      work.height,
    );

    if (longest > 1536) {
      final ratio =
          1536 / longest;

      work =
          img.copyResize(
        work,
        width:
            max(
          1,
          (work.width * ratio).round(),
        ),
        height:
            max(
          1,
          (work.height * ratio).round(),
        ),
        interpolation:
            img.Interpolation.cubic,
      );
    }

    for (final quality in [
      88,
      82,
      76,
      70,
      64,
    ]) {
      final bytes =
          img.encodeJpg(
        work,
        quality: quality,
      );

      if (bytes.length <=
          900 * 1024) {
        return
            'data:image/jpeg;base64,'
            '${base64Encode(bytes)}';
      }
    }

    final bytes =
        img.encodeJpg(
      work,
      quality: 55,
    );

    return
        'data:image/jpeg;base64,'
        '${base64Encode(bytes)}';
  }

  void dispose() {
    _client.close(
      force: true,
    );
  }
}
