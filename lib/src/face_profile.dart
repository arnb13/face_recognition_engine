/// One enrolled person: a name, an optional saved face photo and one or more
/// angle embeddings ("templates") used for matching.
class FaceProfile {
  /// Stable unique id for this person.
  final String id;

  /// Display name.
  final String name;

  /// Absolute path to the saved JPEG face photo (may be empty).
  final String photoPath;

  /// Multi-angle embeddings for this person.
  final List<List<double>> templates;

  const FaceProfile({
    required this.id,
    required this.name,
    required this.photoPath,
    required this.templates,
  });

  FaceProfile copyWith({
    String? id,
    String? name,
    String? photoPath,
    List<List<double>>? templates,
  }) {
    return FaceProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      photoPath: photoPath ?? this.photoPath,
      templates: templates ?? this.templates,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'photoPath': photoPath,
        'templates': templates,
      };

  factory FaceProfile.fromJson(Map<String, dynamic> json) {
    final rawTemplates = (json['templates'] as List?) ?? const [];
    return FaceProfile(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Unknown',
      photoPath: (json['photoPath'] as String?) ?? '',
      templates: rawTemplates
          .map<List<double>>((e) =>
              (e as List).map<double>((n) => (n as num).toDouble()).toList())
          .toList(),
    );
  }
}
