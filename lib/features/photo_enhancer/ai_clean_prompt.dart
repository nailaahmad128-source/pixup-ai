class AICleanPrompt {
  static const defaultPrompt =
      'Clean and enhance this photo. Remove noise and blur, '
      'improve sharpness, clarity, lighting and fine details, '
      'preserve the original face, identity, colors and natural appearance. '
      'Do not change the person or add new objects.';

  static String build(String userPrompt) {
    final custom = userPrompt.trim();

    if (custom.isEmpty) {
      return defaultPrompt;
    }

    return '$defaultPrompt $custom';
  }
}
