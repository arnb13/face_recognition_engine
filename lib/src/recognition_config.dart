/// Immutable configuration for face recognition and the liveness /
/// anti-spoofing checks.
///
/// Unlike the original app (which persisted each value with `shared_value`),
/// this is a plain immutable value object: the package stays free of any
/// storage dependency, and your app persists/restores it however it likes
/// (`shared_preferences`, a settings file, a backend, …) using [toJson] /
/// [fromJson].
///
/// Create a tweaked copy with [copyWith]:
///
/// ```dart
/// const base = RecognitionConfig();
/// final strict = base.copyWith(matchThreshold: 0.85, requireBlink: true);
/// ```
class RecognitionConfig {
  // ── Recognition ──────────────────────────────────────────────────────────

  /// Minimum cosine similarity for a probe to be accepted as a known person.
  final double matchThreshold;

  // ── Enrollment (guided multi-angle capture) ──────────────────────────────

  /// Number of angle samples to capture during guided enrollment. The default
  /// of 3 (front, right, left) relies only on yaw (`headEulerAngleY`), which is
  /// available on all devices; 4–5 add up/down, which need pitch support.
  final int enrollSamples;

  /// Minimum face width as a fraction of the frame width — a quality gate so
  /// distant/tiny faces are not captured or matched.
  final double minFaceWidthFraction;

  // ── Active liveness / anti-spoofing ──────────────────────────────────────

  /// Master switch for active liveness challenges.
  final bool livenessEnabled;

  /// When true, one challenge is chosen at random per attempt from the enabled
  /// pool (instead of requiring all enabled challenges).
  final bool randomizeLiveness;

  /// Require a blink to pass liveness.
  final bool requireBlink;

  /// Require a head turn to pass liveness.
  final bool requireHeadTurn;

  /// Require a smile to pass liveness.
  final bool requireSmile;

  /// `eyeOpenProbability` at or below this counts the eye as closed.
  final double eyeClosedThreshold;

  /// `eyeOpenProbability` at or above this counts the eye as open.
  final double eyeOpenThreshold;

  /// Absolute head yaw (`headEulerAngleY`, degrees) needed for a head turn.
  final double headTurnThreshold;

  /// `smilingProbability` at or above this counts as a smile.
  final double smileThreshold;

  /// Seconds allowed to complete all liveness challenges before failing.
  final int livenessTimeoutSec;

  // ── Passive (texture/CNN) anti-spoofing ──────────────────────────────────

  /// Enable the passive texture model gate. Requires a model wired into
  /// [SpoofDetector]; off by default.
  final bool passiveSpoofEnabled;

  /// Minimum P(live) from the texture model to accept the frame as real.
  /// Higher = stricter.
  final double spoofLiveThreshold;

  const RecognitionConfig({
    this.matchThreshold = 0.8,
    this.enrollSamples = 3,
    this.minFaceWidthFraction = 0.18,
    this.livenessEnabled = true,
    this.randomizeLiveness = true,
    this.requireBlink = true,
    this.requireHeadTurn = false,
    this.requireSmile = true,
    this.eyeClosedThreshold = 0.35,
    this.eyeOpenThreshold = 0.65,
    this.headTurnThreshold = 20.0,
    this.smileThreshold = 0.7,
    this.livenessTimeoutSec = 20,
    this.passiveSpoofEnabled = false,
    this.spoofLiveThreshold = 0.5,
  });

  RecognitionConfig copyWith({
    double? matchThreshold,
    int? enrollSamples,
    double? minFaceWidthFraction,
    bool? livenessEnabled,
    bool? randomizeLiveness,
    bool? requireBlink,
    bool? requireHeadTurn,
    bool? requireSmile,
    double? eyeClosedThreshold,
    double? eyeOpenThreshold,
    double? headTurnThreshold,
    double? smileThreshold,
    int? livenessTimeoutSec,
    bool? passiveSpoofEnabled,
    double? spoofLiveThreshold,
  }) {
    return RecognitionConfig(
      matchThreshold: matchThreshold ?? this.matchThreshold,
      enrollSamples: enrollSamples ?? this.enrollSamples,
      minFaceWidthFraction: minFaceWidthFraction ?? this.minFaceWidthFraction,
      livenessEnabled: livenessEnabled ?? this.livenessEnabled,
      randomizeLiveness: randomizeLiveness ?? this.randomizeLiveness,
      requireBlink: requireBlink ?? this.requireBlink,
      requireHeadTurn: requireHeadTurn ?? this.requireHeadTurn,
      requireSmile: requireSmile ?? this.requireSmile,
      eyeClosedThreshold: eyeClosedThreshold ?? this.eyeClosedThreshold,
      eyeOpenThreshold: eyeOpenThreshold ?? this.eyeOpenThreshold,
      headTurnThreshold: headTurnThreshold ?? this.headTurnThreshold,
      smileThreshold: smileThreshold ?? this.smileThreshold,
      livenessTimeoutSec: livenessTimeoutSec ?? this.livenessTimeoutSec,
      passiveSpoofEnabled: passiveSpoofEnabled ?? this.passiveSpoofEnabled,
      spoofLiveThreshold: spoofLiveThreshold ?? this.spoofLiveThreshold,
    );
  }

  Map<String, dynamic> toJson() => {
        'matchThreshold': matchThreshold,
        'enrollSamples': enrollSamples,
        'minFaceWidthFraction': minFaceWidthFraction,
        'livenessEnabled': livenessEnabled,
        'randomizeLiveness': randomizeLiveness,
        'requireBlink': requireBlink,
        'requireHeadTurn': requireHeadTurn,
        'requireSmile': requireSmile,
        'eyeClosedThreshold': eyeClosedThreshold,
        'eyeOpenThreshold': eyeOpenThreshold,
        'headTurnThreshold': headTurnThreshold,
        'smileThreshold': smileThreshold,
        'livenessTimeoutSec': livenessTimeoutSec,
        'passiveSpoofEnabled': passiveSpoofEnabled,
        'spoofLiveThreshold': spoofLiveThreshold,
      };

  factory RecognitionConfig.fromJson(Map<String, dynamic> json) {
    const d = RecognitionConfig();
    double dbl(String k, double fallback) =>
        (json[k] as num?)?.toDouble() ?? fallback;
    int intg(String k, int fallback) => (json[k] as num?)?.toInt() ?? fallback;
    bool bln(String k, bool fallback) => (json[k] as bool?) ?? fallback;
    return RecognitionConfig(
      matchThreshold: dbl('matchThreshold', d.matchThreshold),
      enrollSamples: intg('enrollSamples', d.enrollSamples),
      minFaceWidthFraction:
          dbl('minFaceWidthFraction', d.minFaceWidthFraction),
      livenessEnabled: bln('livenessEnabled', d.livenessEnabled),
      randomizeLiveness: bln('randomizeLiveness', d.randomizeLiveness),
      requireBlink: bln('requireBlink', d.requireBlink),
      requireHeadTurn: bln('requireHeadTurn', d.requireHeadTurn),
      requireSmile: bln('requireSmile', d.requireSmile),
      eyeClosedThreshold: dbl('eyeClosedThreshold', d.eyeClosedThreshold),
      eyeOpenThreshold: dbl('eyeOpenThreshold', d.eyeOpenThreshold),
      headTurnThreshold: dbl('headTurnThreshold', d.headTurnThreshold),
      smileThreshold: dbl('smileThreshold', d.smileThreshold),
      livenessTimeoutSec: intg('livenessTimeoutSec', d.livenessTimeoutSec),
      passiveSpoofEnabled: bln('passiveSpoofEnabled', d.passiveSpoofEnabled),
      spoofLiveThreshold: dbl('spoofLiveThreshold', d.spoofLiveThreshold),
    );
  }
}
