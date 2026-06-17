import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'face_profile.dart';
import 'face_recognition_util.dart';

/// Persistent store of enrolled [FaceProfile]s.
///
/// Profiles are kept in memory and written to a single JSON file in the app
/// documents directory; face photos are written as JPEGs alongside and
/// referenced by absolute path. Call [load] once before reading.
///
/// This is intentionally instance-based (rather than the static singleton the
/// original app used) so apps can keep separate stores, test against temp
/// directories, and avoid global state.
class FaceProfileStore {
  /// Upper bound on stored templates per person, so repeated re-enrollment
  /// doesn't grow a profile without limit. Oldest templates are dropped first.
  static const int maxTemplatesPerProfile = 12;

  /// Name of the JSON file under the app documents directory.
  final String fileName;

  List<FaceProfile> _cache = <FaceProfile>[];
  bool _loaded = false;

  FaceProfileStore({this.fileName = 'face_profiles.json'});

  Future<File> _storeFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  /// Loads persisted profiles into memory. Safe to call more than once.
  Future<void> load() async {
    try {
      final f = await _storeFile();
      if (!f.existsSync()) {
        _cache = <FaceProfile>[];
      } else {
        final raw = await f.readAsString();
        if (raw.trim().isEmpty) {
          _cache = <FaceProfile>[];
        } else {
          final decoded = jsonDecode(raw) as List;
          _cache = decoded
              .map((e) => FaceProfile.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {
      _cache = <FaceProfile>[];
    }
    _loaded = true;
  }

  /// All enrolled people. Empty when nothing is enrolled.
  List<FaceProfile> get all => List<FaceProfile>.unmodifiable(_cache);

  bool get isEmpty => _cache.isEmpty;

  int get count => _cache.length;

  /// Returns the enrolled profile with [id], or null.
  FaceProfile? byId(String id) {
    for (final p in _cache) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Appends [profile] and persists.
  Future<void> add(FaceProfile profile) async {
    _cache.add(profile);
    await _persist();
  }

  /// Replaces the profile with the same id (or appends if not found) and
  /// persists.
  Future<void> update(FaceProfile profile) async {
    final idx = _cache.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      _cache[idx] = profile;
    } else {
      _cache.add(profile);
    }
    await _persist();
  }

  /// Returns the already-enrolled person whose closest template matches any of
  /// [probes] at or above [threshold] (the best such match), or null if this is
  /// a new face. Used to detect re-enrollment of the same person.
  FaceProfile? findDuplicate(
    List<List<double>> probes,
    double threshold,
  ) {
    FaceProfile? best;
    double bestSim = -1;
    for (final profile in _cache) {
      for (final probe in probes) {
        final s = FaceRecognitionUtil.bestSimilarity(probe, profile.templates);
        if (s > bestSim) {
          bestSim = s;
          best = profile;
        }
      }
    }
    return (best != null && bestSim >= threshold) ? best : null;
  }

  /// Merges [newTemplates] (and optionally a new [photoPath]) into [existing],
  /// capping the template count, persists, and returns the updated profile.
  Future<FaceProfile> mergeInto(
    FaceProfile existing, {
    required List<List<double>> newTemplates,
    String? photoPath,
  }) async {
    final merged = [...existing.templates, ...newTemplates];
    final capped = merged.length > maxTemplatesPerProfile
        ? merged.sublist(merged.length - maxTemplatesPerProfile)
        : merged;
    final updated = existing.copyWith(
      photoPath: photoPath ?? existing.photoPath,
      templates: capped,
    );
    await update(updated);
    return updated;
  }

  /// Removes the profile with [id] (and deletes its photo file) and persists.
  Future<void> removeById(String id) async {
    final removed = _cache.where((p) => p.id == id).toList();
    _cache.removeWhere((p) => p.id == id);
    for (final p in removed) {
      _deletePhoto(p.photoPath);
    }
    await _persist();
  }

  /// Removes every profile (and their photos) and persists the empty state.
  Future<void> clear() async {
    for (final p in _cache) {
      _deletePhoto(p.photoPath);
    }
    _cache = <FaceProfile>[];
    await _persist();
  }

  Future<void> _persist() async {
    final f = await _storeFile();
    await f.writeAsString(
      jsonEncode(_cache.map((p) => p.toJson()).toList()),
    );
  }

  void _deletePhoto(String path) {
    if (path.isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Saves [image] as a JPEG under the app's documents `faces/` folder and
  /// returns the absolute path.
  static Future<String> savePhoto(img.Image image, String id) async {
    final dir = await getApplicationDocumentsDirectory();
    final facesDir = Directory('${dir.path}/faces');
    if (!facesDir.existsSync()) facesDir.createSync(recursive: true);
    final path = '${facesDir.path}/$id.jpg';
    File(path).writeAsBytesSync(img.encodeJpg(image, quality: 90));
    return path;
  }

  /// Whether [load] has completed at least once.
  bool get isLoaded => _loaded;
}
