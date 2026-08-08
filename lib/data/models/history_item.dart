enum MediaType { photo, video }

class HistoryItem {
  final String id;
  final MediaType type;
  final String originalPath;
  final String enhancedPath;
  final DateTime createdAt;

  HistoryItem({
    required this.id,
    required this.type,
    required this.originalPath,
    required this.enhancedPath,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'originalPath': originalPath,
        'enhancedPath': enhancedPath,
        'createdAt': createdAt.toIso8601String(),
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        id: json['id'] as String,
        type: MediaType.values.firstWhere((e) => e.name == json['type']),
        originalPath: json['originalPath'] as String,
        enhancedPath: json['enhancedPath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
