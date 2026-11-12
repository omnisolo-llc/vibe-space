import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'compatibility_adapter.dart';

/// Maximum UTF-8 byte length for a share token (`#vibe=...`).
const int kMaxVibeShareBytes = 32 * 1024;

/// Maximum UTF-8 byte length for sandbox invocation JSON output.
const int kMaxVibeOutputBytes = 64 * 1024;

/// Maximum persisted history snapshots per installed vibe record.
const int kMaxVibeHistoryEntries = 10;

/// Maximum length for host-only custom card titles.
const int kMaxVibeTitleLength = 120;

/// Maximum length for host-only custom card notes.
const int kMaxVibeNoteLength = 280;

final RegExp _kVibeIdRegex = RegExp(r'^[a-z0-9-]{1,40}$');
final RegExp _kBase64UrlRegex = RegExp(r'^[A-Za-z0-9_-]+$');
final Random _secureRandom = Random.secure();

String _randomHex(int byteCount) {
  final buf = StringBuffer();
  for (var i = 0; i < byteCount; i++) {
    final b = _secureRandom.nextInt(256);
    buf.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

Object? _deepCloneJson(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is VibeSealedHandle) {
    return value.toJson();
  }
  if (value is List) {
    return <Object?>[for (final item in value) _deepCloneJson(item)];
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _deepCloneJson(entry.value),
    };
  }
  return jsonDecode(jsonEncode(value));
}

String _canonicalJsonString(Object? value) {
  if (value == null) return 'null';
  if (value is bool || value is num || value is String) {
    return jsonEncode(value);
  }
  if (value is VibeSealedHandle) {
    return _canonicalJsonString(value.toJson());
  }
  if (value is List) {
    final parts = <String>[
      for (final item in value) _canonicalJsonString(item),
    ];
    return '[${parts.join(',')}]';
  }
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    final parts = <String>[];
    for (final k in keys) {
      if (value[k] != null || value.containsKey(k)) {
        parts.add('${jsonEncode(k)}:${_canonicalJsonString(value[k])}');
      }
    }
    return '{${parts.join(',')}}';
  }
  return jsonEncode(value);
}

void _assertJsonSafe(Object? value, [Set<Object>? seen]) {
  if (value == null || value is bool || value is String) return;
  if (value is num) {
    if (!value.isFinite) {
      throw const FormatException('Value must not contain NaN or Infinity');
    }
    return;
  }
  if (value is VibeSealedHandle) return;
  final visited = seen ?? Set<Object>.identity();
  if (value is List) {
    if (!visited.add(value)) {
      throw const FormatException('Value must not contain circular references');
    }
    for (final item in value) {
      _assertJsonSafe(item, visited);
    }
    visited.remove(value);
    return;
  }
  if (value is Map) {
    if (!visited.add(value)) {
      throw const FormatException('Value must not contain circular references');
    }
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('Map keys must be strings');
      }
      _assertJsonSafe(entry.value, visited);
    }
    visited.remove(value);
    return;
  }
  throw FormatException('Value is not JSON-safe (${value.runtimeType})');
}

String _truncateRunes(String value, int maxRunes) {
  final runes = value.runes;
  if (runes.length <= maxRunes) return value;
  return String.fromCharCodes(runes.take(maxRunes));
}

String _normalizeTitle(String? raw, String fallback) {
  if (raw == null) return fallback;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return fallback;
  return _truncateRunes(trimmed, kMaxVibeTitleLength);
}

String _normalizeNote(String? raw) {
  if (raw == null) return '';
  return _truncateRunes(raw, kMaxVibeNoteLength);
}

/// Opaque handle representing a sealed host value inside a sandboxed vibe.
class VibeSealedHandle {
  const VibeSealedHandle(this.sealed);

  final String sealed;

  Map<String, Object?> toJson() => <String, Object?>{'sealed': sealed};

  /// Parses `{ 'sealed': '<non-empty string>' }` and rejects any other shape.
  static VibeSealedHandle? tryParse(Object? raw) {
    if (raw is VibeSealedHandle) return raw;
    if (raw is Map && raw.length == 1 && raw.containsKey('sealed')) {
      final val = raw['sealed'];
      if (val is String && val.isNotEmpty) {
        return VibeSealedHandle(val);
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeSealedHandle && other.sealed == sealed;

  @override
  int get hashCode => sealed.hashCode;

  @override
  String toString() => 'VibeSealedHandle($sealed)';
}

/// Availability state for a vibe's data sources or active run.
enum VibeSourceMode {
  live('live'),
  sample('sample'),
  offline('offline'),
  revoked('revoked'),
  missing('missing');

  const VibeSourceMode(this.wireName);

  final String wireName;

  static VibeSourceMode fromWireName(String? raw) {
    final norm = raw?.trim().toLowerCase();
    for (final mode in VibeSourceMode.values) {
      if (mode.wireName == norm) return mode;
    }
    return VibeSourceMode.offline;
  }
}

/// Status returned by a [VibeCapability.status] check or [VibeCapability.read].
class VibeSourceStatus {
  const VibeSourceStatus({
    required this.available,
    required this.mode,
    this.reason,
  });

  const VibeSourceStatus.live()
      : available = true,
        mode = VibeSourceMode.live,
        reason = null;

  const VibeSourceStatus.offline([this.reason])
      : available = false,
        mode = VibeSourceMode.offline;

  const VibeSourceStatus.revoked([this.reason])
      : available = false,
        mode = VibeSourceMode.revoked;

  const VibeSourceStatus.missing([this.reason])
      : available = false,
        mode = VibeSourceMode.missing;

  final bool available;
  final VibeSourceMode mode;
  final String? reason;

  /// Interprets a [VibeSourceStatus] or `{'available': false, ...}` map returned
  /// by `capability.read()`.
  static VibeSourceStatus? tryFromReadResult(Object? raw) {
    if (raw is VibeSourceStatus) return raw;
    if (raw is Map && raw['available'] == false) {
      final modeStr = raw['mode']?.toString();
      final mode = switch (modeStr) {
        'revoked' => VibeSourceMode.revoked,
        'missing' => VibeSourceMode.missing,
        _ => VibeSourceMode.offline,
      };
      final reason = raw['reason'] is String ? raw['reason'] as String : null;
      return VibeSourceStatus(available: false, mode: mode, reason: reason);
    }
    return null;
  }
}

/// Host-declared data capability exposed to vibes.
class VibeCapability {
  const VibeCapability({
    required this.name,
    required this.title,
    required this.fields,
    this.sealedNote,
    this.sealedCannot,
    this.status,
    required this.read,
    this.sample = const <Map<String, Object?>>[],
  });

  final String name;
  final String title;

  /// Field visibility map: `'public'` or `'sealed'`.
  final Map<String, String> fields;
  final String? sealedNote;
  final String? sealedCannot;
  final VibeSourceStatus Function()? status;
  final FutureOr<Object?> Function() read;
  final List<Map<String, Object?>> sample;

  Map<String, Object?> toManifestJson() => <String, Object?>{
        'name': name,
        'title': title,
        'fields': Map<String, String>.from(fields),
        'sample': _deepCloneJson(sample),
      };
}

/// Result of checking whether a [VibeProtocolHost] offers all capabilities
/// required by a [VibeSpec].
class VibeCheckResult {
  const VibeCheckResult({
    required this.ok,
    this.missing = const <String>[],
  });

  final bool ok;
  final List<String> missing;
}

/// Plain-language permission label derived from a vibe's `needs` and the host manifest.
class VibePermissionLabel {
  const VibePermissionLabel({
    required this.reads,
    required this.shows,
    required this.cannot,
  });

  final List<String> reads;
  final List<String> shows;
  final List<String> cannot;
}

/// JSON-safe VibePackage definition (`id`, `name`, `wish`, `version`, `needs`, `refresh`, `source`).
class VibeSpec {
  const VibeSpec({
    required this.id,
    required this.name,
    this.wish = '',
    required this.version,
    this.needs = const <String>[],
    this.refreshMs,
    required this.source,
  });

  final String id;
  final String name;
  final String wish;
  final int version;
  final List<String> needs;
  final int? refreshMs;
  final String source;

  /// Validates package constraints and throws [FormatException] on violation.
  void validate() {
    if (!_kVibeIdRegex.hasMatch(id)) {
      throw const FormatException('Vibe id must match ^[a-z0-9-]{1,40}\$');
    }
    if (name.trim().isEmpty || name.length > 120) {
      throw const FormatException('Vibe name must be 1..120 characters');
    }
    if (version < 1) {
      throw const FormatException('Vibe version must be an integer >= 1');
    }
    for (final cap in needs) {
      if (cap.trim().isEmpty || cap.length > 120) {
        throw const FormatException('Each capability in needs must be non-empty');
      }
    }
    if (refreshMs != null && refreshMs! < 500) {
      throw const FormatException('Vibe refreshMs must be >= 500 ms');
    }
    if (source.trim().isEmpty) {
      throw const FormatException('Vibe source must be a non-empty string');
    }
    if (utf8.encode(source).length > kMaxVibeOutputBytes) {
      throw const FormatException('Vibe source exceeds 64 kB limit');
    }
  }

  VibeSpec copyWith({
    String? id,
    String? name,
    String? wish,
    int? version,
    List<String>? needs,
    int? refreshMs,
    bool clearRefreshMs = false,
    String? source,
  }) {
    return VibeSpec(
      id: id ?? this.id,
      name: name ?? this.name,
      wish: wish ?? this.wish,
      version: version ?? this.version,
      needs: List<String>.unmodifiable(needs ?? this.needs),
      refreshMs: clearRefreshMs ? null : (refreshMs ?? this.refreshMs),
      source: source ?? this.source,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'wish': wish,
        'version': version,
        'needs': List<String>.from(needs),
        if (refreshMs != null) 'refresh': refreshMs,
        'source': source,
      };

  /// Parses and validates a [VibeSpec] from JSON, stripping any extraneous keys
  /// (such as host-only `title` or `note`).
  factory VibeSpec.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final wish = json['wish'];
    final version = json['version'];
    final rawNeeds = json['needs'];
    final rawRefresh = json.containsKey('refresh')
        ? json['refresh']
        : json['refreshMs'];
    final source = json['source'];

    if (id is! String) {
      throw const FormatException('Vibe id must be a string');
    }
    if (name is! String) {
      throw const FormatException('Vibe name must be a string');
    }
    if (wish != null && wish is! String) {
      throw const FormatException('Vibe wish must be a string');
    }
    if (version is! int) {
      throw const FormatException('Vibe version must be an integer');
    }
    if (rawNeeds is! List || !rawNeeds.every((e) => e is String)) {
      throw const FormatException('Vibe needs must be a list of strings');
    }
    int? parsedRefresh;
    if (rawRefresh != null) {
      if (rawRefresh is! int) {
        throw const FormatException('Vibe refresh must be an integer >= 500');
      }
      parsedRefresh = rawRefresh;
    }
    if (source is! String) {
      throw const FormatException('Vibe source must be a string');
    }

    final spec = VibeSpec(
      id: id,
      name: name,
      wish: (wish as String?) ?? '',
      version: version,
      needs: List<String>.unmodifiable(rawNeeds.cast<String>()),
      refreshMs: parsedRefresh,
      source: source,
    );
    spec.validate();
    return spec;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeSpec &&
          other.id == id &&
          other.name == name &&
          other.wish == wish &&
          other.version == version &&
          _canonicalJsonString(other.needs) == _canonicalJsonString(needs) &&
          other.refreshMs == refreshMs &&
          other.source == source;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        wish,
        version,
        _canonicalJsonString(needs),
        refreshMs,
        source,
      );
}

/// Share link encoder/decoder (`#vibe=<token>`). Never encodes `title`, `note`,
/// `args`, or host grants.
class VibeShareCodec {
  const VibeShareCodec._();

  static String encode(VibeSpec vibe) {
    vibe.validate();
    final jsonStr = jsonEncode(vibe.toJson());
    final encoded = base64Url.encode(utf8.encode(jsonStr)).replaceAll('=', '');
    if (utf8.encode(encoded).length > kMaxVibeShareBytes) {
      throw const FormatException('Encoded vibe exceeds 32 kB share limit');
    }
    return encoded;
  }

  static VibeSpec decode(String rawOrUrl) {
    var token = rawOrUrl.trim();
    final hashIdx = token.indexOf('#vibe=');
    if (hashIdx >= 0) {
      token = token.substring(hashIdx + '#vibe='.length);
      final ampIdx = token.indexOf('&');
      if (ampIdx >= 0) {
        token = token.substring(0, ampIdx);
      }
    } else if (token.startsWith('vibe=')) {
      token = token.substring('vibe='.length);
    }

    if (token.isEmpty || !_kBase64UrlRegex.hasMatch(token)) {
      throw const FormatException('Invalid share link payload');
    }
    if (utf8.encode(token).length > kMaxVibeShareBytes) {
      throw const FormatException('Share payload exceeds 32 kB limit');
    }

    final padLen = (4 - (token.length % 4)) % 4;
    final padded = token + ('=' * padLen);
    final decodedBytes = base64Url.decode(padded);
    final jsonStr = utf8.decode(decodedBytes);
    final parsed = jsonDecode(jsonStr);
    if (parsed is! Map) {
      throw const FormatException('Share link payload must decode to an object');
    }
    return VibeSpec.fromJson(
      parsed.map((k, v) => MapEntry(k.toString(), v)),
    );
  }
}

/// Historical version snapshot stored on a [VibeInstalledRecord].
class VibeVersionSnapshot {
  const VibeVersionSnapshot({
    required this.vibe,
    required this.savedAtMs,
  });

  final VibeSpec vibe;
  final int savedAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
        'vibe': vibe.toJson(),
        'savedAtMs': savedAtMs,
      };

  factory VibeVersionSnapshot.fromJson(Map<String, Object?> json) {
    final rawVibe = json['vibe'];
    if (rawVibe is! Map) {
      throw const FormatException('History snapshot missing vibe');
    }
    final rawSaved = json['savedAtMs'] ?? json['savedAt'];
    final savedAtMs = rawSaved is int ? rawSaved : 0;
    return VibeVersionSnapshot(
      vibe: VibeSpec.fromJson(
        rawVibe.map((k, v) => MapEntry(k.toString(), v)),
      ),
      savedAtMs: savedAtMs,
    );
  }
}

const Set<String> _kValidOrigins = <String>{
  'yours',
  'shared',
  'gallery',
  'agent',
};

/// Installed vibe record persisted in host storage.
class VibeInstalledRecord {
  const VibeInstalledRecord({
    required this.instanceId,
    required this.vibe,
    this.origin = 'yours',
    this.args,
    required this.title,
    this.note = '',
    this.pinned = false,
    this.paused = false,
    this.collapsed = false,
    this.order = 0,
    required this.installedAtMs,
    required this.updatedAtMs,
    this.history = const <VibeVersionSnapshot>[],
  });

  final String instanceId;
  final VibeSpec vibe;
  final String origin;
  final Map<String, Object?>? args;

  /// Host-only display title; never sent into sandbox `input` or share links.
  final String title;

  /// Host-only note; never sent into sandbox `input` or share links.
  final String note;
  final bool pinned;
  final bool paused;
  final bool collapsed;
  final int order;
  final int installedAtMs;
  final int updatedAtMs;
  final List<VibeVersionSnapshot> history;

  VibeInstalledRecord copyWith({
    String? instanceId,
    VibeSpec? vibe,
    String? origin,
    Map<String, Object?>? args,
    bool clearArgs = false,
    String? title,
    String? note,
    bool? pinned,
    bool? paused,
    bool? collapsed,
    int? order,
    int? installedAtMs,
    int? updatedAtMs,
    List<VibeVersionSnapshot>? history,
  }) {
    return VibeInstalledRecord(
      instanceId: instanceId ?? this.instanceId,
      vibe: vibe ?? this.vibe,
      origin: origin ?? this.origin,
      args: clearArgs
          ? null
          : (args != null
              ? (_deepCloneJson(args) as Map<String, Object?>)
              : (this.args != null
                  ? (_deepCloneJson(this.args) as Map<String, Object?>)
                  : null)),
      title: title ?? this.title,
      note: note ?? this.note,
      pinned: pinned ?? this.pinned,
      paused: paused ?? this.paused,
      collapsed: collapsed ?? this.collapsed,
      order: order ?? this.order,
      installedAtMs: installedAtMs ?? this.installedAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      history: List<VibeVersionSnapshot>.unmodifiable(history ?? this.history),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'instanceId': instanceId,
        'vibe': vibe.toJson(),
        'origin': origin,
        'args': args != null ? _deepCloneJson(args) : null,
        'title': title,
        'note': note,
        'pinned': pinned,
        'paused': paused,
        'collapsed': collapsed,
        'order': order,
        'installedAtMs': installedAtMs,
        'updatedAtMs': updatedAtMs,
        'history': <Map<String, Object?>>[
          for (final h in history) h.toJson(),
        ],
      };

  factory VibeInstalledRecord.fromJson(Map<String, Object?> json) {
    final rawVibe = json['vibe'];
    if (rawVibe is! Map) {
      throw const FormatException('Installed record missing vibe');
    }
    final spec = VibeSpec.fromJson(
      rawVibe.map((k, v) => MapEntry(k.toString(), v)),
    );
    final rawInst = json['instanceId'];
    final instanceId =
        rawInst is String && rawInst.trim().isNotEmpty
            ? rawInst.trim()
            : 'inst_${_randomHex(8)}';
    final rawOrigin = json['origin']?.toString();
    final origin =
        rawOrigin != null && _kValidOrigins.contains(rawOrigin)
            ? rawOrigin
            : 'yours';
    final rawArgs = json['args'];
    Map<String, Object?>? args;
    if (rawArgs is Map) {
      args = _deepCloneJson(rawArgs) as Map<String, Object?>;
      _assertJsonSafe(args);
    }
    final rawInstalledAt = json['installedAtMs'] ?? json['installedAt'];
    final installedAtMs =
        rawInstalledAt is int ? rawInstalledAt : DateTime.now().millisecondsSinceEpoch;
    final rawUpdatedAt = json['updatedAtMs'] ?? json['updatedAt'];
    final updatedAtMs = rawUpdatedAt is int ? rawUpdatedAt : installedAtMs;

    final rawHistory = json['history'];
    final history = <VibeVersionSnapshot>[];
    if (rawHistory is List) {
      for (final item in rawHistory) {
        if (history.length >= kMaxVibeHistoryEntries) break;
        if (item is Map) {
          try {
            history.add(
              VibeVersionSnapshot.fromJson(
                item.map((k, v) => MapEntry(k.toString(), v)),
              ),
            );
          } on Object {
            // Skip malformed history snapshot
          }
        }
      }
    }

    return VibeInstalledRecord(
      instanceId: instanceId,
      vibe: spec,
      origin: origin,
      args: args,
      title: _normalizeTitle(json['title'] as String?, spec.name),
      note: _normalizeNote(json['note'] as String?),
      pinned: json['pinned'] == true,
      paused: json['paused'] == true,
      collapsed: json['collapsed'] == true,
      order: json['order'] is int ? json['order'] as int : 0,
      installedAtMs: installedAtMs,
      updatedAtMs: updatedAtMs,
      history: List<VibeVersionSnapshot>.unmodifiable(history),
    );
  }
}

/// Persistence interface for per-host vibe records and sealed handle tables.
abstract class VibeStorageAdapter {
  String? read(String key);
  FutureOr<void> write(String key, String value);
}

/// Default in-memory [VibeStorageAdapter] for tests and ephemeral hosts.
class InMemoryVibeStorage implements VibeStorageAdapter {
  final Map<String, String> _data = <String, String>{};

  @override
  String? read(String key) => _data[key];

  @override
  void write(String key, String value) {
    _data[key] = value;
  }
}

/// Describes a single unavailable capability for a mounted vibe run.
class VibeSourceIssue {
  const VibeSourceIssue({
    required this.capability,
    required this.title,
    required this.mode,
    required this.reason,
    required this.hasSample,
  });

  final String capability;
  final String title;
  final VibeSourceMode mode;
  final String reason;
  final bool hasSample;
}

/// Current data-source health of a [VibeRunController].
class VibeRunHealth {
  const VibeRunHealth({
    required this.state,
    this.issues = const <VibeSourceIssue>[],
    this.lastGoodAtMs,
    this.usingSampleFallback = false,
  });

  final VibeSourceMode state;
  final List<VibeSourceIssue> issues;
  final int? lastGoodAtMs;
  final bool usingSampleFallback;

  bool get isStale =>
      !usingSampleFallback &&
      lastGoodAtMs != null &&
      (state == VibeSourceMode.offline ||
          state == VibeSourceMode.revoked ||
          state == VibeSourceMode.missing);
}

/// Read/effect ledger exposed in the Inspect pane.
class VibeReadLedger {
  const VibeReadLedger({
    this.reads = const <String, int>{},
    this.sent = 0,
    this.changed = 0,
    this.calls = 0,
    this.lastError,
  });

  final Map<String, int> reads;
  final int sent;
  final int changed;
  final int calls;
  final String? lastError;
}

/// Snapshot of the latest invocation input, output, and ledger.
class VibeInspectSnapshot {
  const VibeInspectSnapshot({
    required this.input,
    this.output,
    required this.ledger,
  });

  final Map<String, Object?> input;
  final Map<String, Object?>? output;
  final VibeReadLedger ledger;
}

/// Pre-authored wish suggestion (or remix preset) displayed in Vibe Space.
class VibeWishPreset {
  const VibeWishPreset({
    required this.text,
    required this.vibe,
    this.remixOf,
  });

  final String text;
  final VibeSpec vibe;
  final String? remixOf;
}

/// Built-in portable 25-minute Focus timer (`needs: []`).
const VibeSpec kPortableFocusTimerVibe = VibeSpec(
  id: 'focus-timer',
  name: 'Focus timer',
  wish: 'Give me a 25-minute focus timer',
  version: 1,
  needs: <String>[],
  refreshMs: 1000,
  source: '''function invoke(input) {
  var DURATION_MIN = 25;
  var DURATION = DURATION_MIN * 60 * 1000;
  var st = input.state;
  if (!st || typeof st !== 'object') {
    st = { running: false, paused: false, remainingMs: DURATION, endAt: null };
  }
  var now = typeof input.now === 'number' ? input.now : Date.now();
  var cmd = input.command;
  if (cmd === 'start') {
    if (!st.running) {
      var base = typeof st.remainingMs === 'number' && st.remainingMs > 0 ? st.remainingMs : DURATION;
      st = { running: true, paused: false, remainingMs: base, endAt: now + base };
    }
  } else if (cmd === 'pause') {
    if (st.running && typeof st.endAt === 'number') {
      st = { running: false, paused: true, remainingMs: Math.max(0, st.endAt - now), endAt: null };
    }
  } else if (cmd === 'reset') {
    st = { running: false, paused: false, remainingMs: DURATION, endAt: null };
  } else if (st.running && typeof st.endAt === 'number') {
    var left = Math.max(0, st.endAt - now);
    st = left === 0 ? { running: false, paused: false, remainingMs: 0, endAt: null } : { running: true, paused: false, remainingMs: left, endAt: st.endAt };
  }
  var rem = typeof st.remainingMs === 'number' ? st.remainingMs : DURATION;
  var totalSeconds = rem <= 0 ? 0 : (rem < 1000 ? 1 : Math.floor(rem / 1000));
  var mins = Math.floor(totalSeconds / 60);
  var secs = totalSeconds % 60;
  var timeText = (mins < 10 ? '0' + mins : String(mins)) + ':' + (secs < 10 ? '0' + secs : String(secs));
  var elapsed = Math.max(0, Math.min(DURATION, DURATION - rem));
  var minsLeft = Math.ceil(rem / 60000);
  var isPaused = st.paused === true || (!st.running && rem > 0 && rem < DURATION);
  var statusText = st.running ? 'Running' : (rem === 0 ? 'Done' : (isPaused ? 'Paused' : 'Ready'));
  var tone = rem === 0 ? 'ok' : (st.running ? (rem <= 5 * 60 * 1000 ? 'warn' : 'ok') : 'default');
  var btns = [];
  if (st.running) {
    btns.push({ type: 'button', text: 'Pause', command: 'pause', tone: 'warn' });
  } else if (rem > 0) {
    btns.push({ type: 'button', text: isPaused ? 'Resume' : 'Start', command: 'start', tone: 'ok' });
  }
  btns.push({ type: 'button', text: 'Reset', command: 'reset', tone: 'default' });
  return {
    state: st,
    view: {
      type: 'column',
      children: [
        { type: 'row', children: [{ type: 'stat', label: 'Time left', value: timeText, tone: tone }, { type: 'badge', text: statusText, tone: tone }] },
        { type: 'bar', label: DURATION_MIN + '-minute session', value: elapsed, max: DURATION, caption: rem === 0 ? 'Done' : minsLeft + ' min left', tone: tone },
        { type: 'row', children: btns }
      ]
    }
  };
}''',
);

/// Pure deterministic evaluator for JSON program specs and JS-style `invoke(input)`
/// vibe sources. Enforces the 64 kB UTF-8 JSON output cap and `{ state, view }` contract.
class VibeSandboxEvaluator {
  const VibeSandboxEvaluator._();

  static final RegExp _kInfiniteLoopRegex = RegExp(
    r'\bwhile\s*\(\s*true\s*\)|\bfor\s*\(\s*;\s*;\s*\)',
  );
  static final RegExp _kInvokeDeclRegex = RegExp(
    r'\bfunction\s+invoke\s*\(|\b(?:var|let|const)\s+invoke\s*=',
  );

  static FutureOr<Map<String, Object?>> evaluate(
    VibeSpec vibe,
    Map<String, Object?> input, {
    FutureOr<Map<String, Object?>> Function(
      VibeSpec vibe,
      Map<String, Object?> input,
    )? customRunner,
  }) {
    final clonedInput = _deepCloneJson(input) as Map<String, Object?>;

    if (customRunner != null) {
      final res = customRunner(vibe, clonedInput);
      if (res is Future<Map<String, Object?>>) {
        return res.then(_validateAndFreezeOutput);
      }
      return _validateAndFreezeOutput(res);
    }

    final result = _evaluateBuiltIn(vibe, clonedInput);
    return _validateAndFreezeOutput(result);
  }

  static Map<String, Object?> _validateAndFreezeOutput(
    Map<String, Object?> raw,
  ) {
    if (!raw.containsKey('state') ||
        !raw.containsKey('view') ||
        raw.length != 2) {
      throw const FormatException('Vibe output must have exact keys { state, view }');
    }
    final adaptedView = VibeUiCompatibilityAdapter.adapt(raw['view']);
    final normalized = <String, Object?>{
      'state': _deepCloneJson(raw['state']),
      'view': _deepCloneJson(adaptedView),
    };
    _assertJsonSafe(normalized);
    final encoded = jsonEncode(normalized);
    if (utf8.encode(encoded).length > kMaxVibeOutputBytes) {
      throw const FormatException('Vibe output exceeds 64 kB limit');
    }
    return normalized;
  }

  static Map<String, Object?> _evaluateBuiltIn(
    VibeSpec vibe,
    Map<String, Object?> input,
  ) {
    final trimmed = vibe.source.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Vibe source is empty');
    }
    if (_kInfiniteLoopRegex.hasMatch(trimmed)) {
      throw const FormatException('Vibe timed out after 1000 ms');
    }

    if (trimmed.startsWith('{')) {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        throw const FormatException('JSON vibe source must be an object');
      }
      final spec = decoded.map((k, v) => MapEntry(k.toString(), v));
      return _evalJsonSpec(spec, vibe, input);
    }

    if (!_kInvokeDeclRegex.hasMatch(trimmed)) {
      throw const FormatException('Vibe source must define function invoke(input)');
    }
    if (!_hasBalancedDelimiters(trimmed)) {
      throw const FormatException('SyntaxError in vibe source');
    }
    final throwMatch = RegExp(r'''throw\s+new\s+Error\(\s*['"]([^'"]+)['"]\s*\)''').firstMatch(trimmed);
    if (throwMatch != null && !trimmed.contains('try')) {
      throw FormatException(throwMatch.group(1) ?? 'Vibe threw an error');
    }

    final durationMin = _parseDurationMinutes(trimmed);
    if (vibe.id == 'focus-timer' ||
        trimmed.contains('DURATION_MIN') ||
        trimmed.contains('remainingMs')) {
      return _evalCountdownTimer(
        durationMin: durationMin ?? 25,
        heading: _parseHeadingLiteral(trimmed),
        input: input,
      );
    }

    if (vibe.needs.contains('telemetry.disk') ||
        vibe.id.startsWith('disk-watch')) {
      final limit = _parseTopLimit(trimmed);
      final threshold = _parsePrimaryThreshold(trimmed) ??
          (trimmed.contains('above 90%') || trimmed.contains('0.9') ? 0.9 : 0.8);
      final warn = _parseNamedNumber(trimmed, 'WARN_LEVEL') ?? 0.6;
      return _evalDiskWatch(
        threshold: threshold,
        warn: warn,
        limit: limit,
        heading: _parseHeadingLiteral(trimmed),
        input: input,
      );
    }

    if (vibe.needs.contains('telemetry.load') ||
        vibe.id.startsWith('server-load')) {
      return _evalServerLoad(
        heading: _parseHeadingLiteral(trimmed),
        input: input,
      );
    }

    final data = input['data'];
    if (vibe.needs.isNotEmpty && data is Map) {
      final capName = vibe.needs.first;
      final rows = data[capName];
      if (rows is List) {
        return _evalMetricBars(
          capability: capName,
          heading: _parseHeadingLiteral(trimmed) ?? vibe.name,
          limit: _parseTopLimit(trimmed),
          input: input,
        );
      }
    }

    final literalOut = _tryEvalStaticReturnLiteral(trimmed);
    if (literalOut != null) {
      return literalOut;
    }

    throw const FormatException(
      'Unable to evaluate JS vibe source in native evaluator',
    );
  }

  static Map<String, Object?> _evalJsonSpec(
    Map<String, Object?> spec,
    VibeSpec vibe,
    Map<String, Object?> input,
  ) {
    final kind = spec['kind']?.toString();
    switch (kind) {
      case 'disk_watch':
        return _evalDiskWatch(
          threshold: (spec['threshold'] as num?)?.toDouble() ?? 0.8,
          warn: (spec['warn'] as num?)?.toDouble() ?? 0.6,
          limit: spec['limit'] is int ? spec['limit'] as int : null,
          heading: spec['heading'] as String?,
          input: input,
        );
      case 'server_load':
        return _evalServerLoad(
          heading: spec['heading'] as String?,
          input: input,
        );
      case 'metric_bars':
      case 'sessions_overview':
        final capName = spec['capability']?.toString() ??
            (vibe.needs.isNotEmpty ? vibe.needs.first : '');
        return _evalMetricBars(
          capability: capName,
          heading: spec['heading'] as String? ?? vibe.name,
          labelField: spec['labelField'] as String?,
          valueField: spec['valueField'] as String?,
          limit: spec['limit'] is int ? spec['limit'] as int : null,
          maxVal: (spec['max'] as num?)?.toDouble(),
          input: input,
        );
      case 'countdown_timer':
        return _evalCountdownTimer(
          durationMin: spec['durationMin'] is int
              ? (spec['durationMin'] as int).clamp(1, 240)
              : 25,
          heading: spec['heading'] as String?,
          input: input,
        );
      case 'static_view':
        final view = spec['view'];
        if (view is! Map && view is! List && view is! String) {
          throw const FormatException('static_view requires a view payload');
        }
        return <String, Object?>{
          'state': input['state'],
          'view': _deepCloneJson(view),
        };
      default:
        throw FormatException('Unsupported JSON vibe kind: $kind');
    }
  }

  static Map<String, Object?> _evalDiskWatch({
    required double threshold,
    required double warn,
    int? limit,
    String? heading,
    required Map<String, Object?> input,
  }) {
    final data = input['data'] as Map? ?? const <String, Object?>{};
    final rawRows = data['telemetry.disk'];
    final rows = rawRows is List
        ? rawRows.whereType<Map>().map((m) => Map<String, Object?>.from(m)).toList()
        : <Map<String, Object?>>[];

    rows.sort((a, b) {
      final ua = (a['usedFraction'] as num?)?.toDouble() ?? 0.0;
      final ub = (b['usedFraction'] as num?)?.toDouble() ?? 0.0;
      return ub.compareTo(ua);
    });

    final thresholdPct = (threshold * 100).round();
    var overCount = 0;
    for (final r in rows) {
      final used = (r['usedFraction'] as num?)?.toDouble() ?? 0.0;
      if (used >= threshold) overCount++;
    }

    final displayRows =
        limit != null && limit > 0 ? rows.take(limit).toList() : rows;
    final resolvedHeading = heading ??
        (limit != null && limit > 0
            ? 'Disk usage · worst $limit'
            : 'Disk usage');

    final children = <Map<String, Object?>>[
      <String, Object?>{'type': 'heading', 'text': resolvedHeading},
    ];

    if (rows.isEmpty) {
      children.add(<String, Object?>{
        'type': 'text',
        'text': 'No volumes reporting',
        'tone': 'warn',
      });
    } else {
      children.add(<String, Object?>{
        'type': 'text',
        'text': '$overCount of ${rows.length} volumes above $thresholdPct%',
        'tone': overCount > 0 ? 'danger' : 'ok',
      });
      for (final row in displayRows) {
        final used = (row['usedFraction'] as num?)?.toDouble() ?? 0.0;
        final pct = (used * 100).round();
        final mount = row['mount']?.toString() ?? '/';
        final sizeGb = row['sizeGb'] ?? 0;
        final tone = used >= threshold
            ? 'danger'
            : (used >= warn ? 'warn' : 'ok');
        children.add(<String, Object?>{
          'type': 'bar',
          'label': row['server'] ?? 'unknown',
          'caption': '$mount · $pct% of $sizeGb GB',
          'value': used,
          'max': 1,
          'tone': tone,
        });
      }
    }

    return <String, Object?>{
      'state': null,
      'view': <String, Object?>{
        'type': 'column',
        'children': children,
      },
    };
  }

  static Map<String, Object?> _evalServerLoad({
    String? heading,
    required Map<String, Object?> input,
  }) {
    String toneFor(double val) {
      if (val >= 0.8) return 'danger';
      if (val >= 0.6) return 'warn';
      return 'ok';
    }

    final data = input['data'] as Map? ?? const <String, Object?>{};
    final rawRows = data['telemetry.load'];
    final rows = rawRows is List
        ? rawRows.whereType<Map>().map((m) => Map<String, Object?>.from(m)).toList()
        : <Map<String, Object?>>[];

    final prevState = input['state'] is Map
        ? Map<String, Object?>.from(input['state'] as Map)
        : <String, Object?>{};
    var showAll = prevState['showAll'] == true;
    final command = input['command']?.toString() ?? 'open';
    if (command == 'clear-target') {
      showAll = true;
    } else if (command == 'restore-target') {
      showAll = false;
    }

    final args = input['args'];
    final targetHandle =
        (args is Map ? VibeSealedHandle.tryParse(args['server']) : null) ??
        VibeSealedHandle.tryParse(prevState['targetServer']);

    Map<String, Object?>? matchedRow;
    if (targetHandle != null) {
      for (final row in rows) {
        final rowHandle = VibeSealedHandle.tryParse(row['server']);
        if (rowHandle != null && rowHandle.sealed == targetHandle.sealed) {
          matchedRow = row;
          break;
        }
      }
    }

    var lastReading = prevState['lastReading'] is Map
        ? Map<String, Object?>.from(prevState['lastReading'] as Map)
        : null;
    if (matchedRow != null) {
      lastReading = <String, Object?>{
        'cpu': matchedRow['cpu'],
        'mem': matchedRow['mem'],
        'cpuHistory': matchedRow['cpuHistory'],
        'memHistory': matchedRow['memHistory'],
      };
    }

    final nextState = <String, Object?>{
      'showAll': showAll,
      if (targetHandle != null) 'targetServer': targetHandle.toJson(),
      if (lastReading != null) 'lastReading': lastReading,
    };

    if (targetHandle != null && !showAll) {
      if (matchedRow != null) {
        final cpu = (matchedRow['cpu'] as num?)?.toDouble() ?? 0.0;
        final mem = (matchedRow['mem'] as num?)?.toDouble() ?? 0.0;
        return <String, Object?>{
          'state': nextState,
          'view': <String, Object?>{
            'type': 'column',
            'children': <Map<String, Object?>>[
              <String, Object?>{'type': 'heading', 'text': targetHandle.toJson()},
              <String, Object?>{
                'type': 'row',
                'children': <Map<String, Object?>>[
                  <String, Object?>{
                    'type': 'stat',
                    'label': 'CPU',
                    'value': '${(cpu * 100).round()}%',
                    'tone': toneFor(cpu),
                  },
                  <String, Object?>{
                    'type': 'stat',
                    'label': 'Memory',
                    'value': '${(mem * 100).round()}%',
                    'tone': toneFor(mem),
                  },
                ],
              },
              <String, Object?>{'type': 'text', 'text': 'CPU, last minute'},
              <String, Object?>{
                'type': 'sparkline',
                'values': matchedRow['cpuHistory'] ?? const <num>[],
                'tone': toneFor(cpu),
              },
              <String, Object?>{'type': 'text', 'text': 'Memory, last minute'},
              <String, Object?>{
                'type': 'sparkline',
                'values': matchedRow['memHistory'] ?? const <num>[],
                'tone': toneFor(mem),
              },
            ],
          },
        };
      }

      final offlineChildren = <Map<String, Object?>>[
        <String, Object?>{'type': 'heading', 'text': targetHandle.toJson()},
        <String, Object?>{
          'type': 'badge',
          'text': 'Target server offline',
          'tone': 'warn',
        },
      ];
      if (lastReading != null) {
        final lastCpu = (lastReading['cpu'] as num?)?.toDouble() ?? 0.0;
        final lastMem = (lastReading['mem'] as num?)?.toDouble() ?? 0.0;
        offlineChildren.add(<String, Object?>{
          'type': 'row',
          'children': <Map<String, Object?>>[
            <String, Object?>{
              'type': 'stat',
              'label': 'Last CPU',
              'value': '${(lastCpu * 100).round()}%',
              'tone': toneFor(lastCpu),
            },
            <String, Object?>{
              'type': 'stat',
              'label': 'Last Memory',
              'value': '${(lastMem * 100).round()}%',
              'tone': toneFor(lastMem),
            },
          ],
        });
      }
      offlineChildren.add(<String, Object?>{
        'type': 'button',
        'text': 'Show all online servers',
        'command': 'clear-target',
      });

      return <String, Object?>{
        'state': nextState,
        'view': <String, Object?>{
          'type': 'column',
          'children': offlineChildren,
        },
      };
    }

    rows.sort((a, b) {
      final ca = (a['cpu'] as num?)?.toDouble() ?? 0.0;
      final cb = (b['cpu'] as num?)?.toDouble() ?? 0.0;
      return cb.compareTo(ca);
    });

    final children = <Map<String, Object?>>[
      <String, Object?>{
        'type': 'heading',
        'text': heading ?? 'CPU and memory',
      },
    ];
    if (rows.isEmpty) {
      children.add(<String, Object?>{
        'type': 'text',
        'text': 'No servers reporting',
        'tone': 'warn',
      });
    } else {
      for (final row in rows) {
        final cpu = (row['cpu'] as num?)?.toDouble() ?? 0.0;
        final mem = (row['mem'] as num?)?.toDouble() ?? 0.0;
        children.add(<String, Object?>{
          'type': 'bar',
          'label': row['server'] ?? 'unknown',
          'caption': 'CPU ${(cpu * 100).round()}% · Mem ${(mem * 100).round()}%',
          'value': cpu,
          'max': 1,
          'tone': toneFor(cpu),
        });
      }
    }
    if (targetHandle != null) {
      children.add(<String, Object?>{
        'type': 'button',
        'text': 'Back to target server',
        'command': 'restore-target',
      });
    }

    return <String, Object?>{
      'state': nextState,
      'view': <String, Object?>{
        'type': 'column',
        'children': children,
      },
    };
  }

  static Map<String, Object?> _evalMetricBars({
    required String capability,
    required String heading,
    String? labelField,
    String? valueField,
    int? limit,
    double? maxVal,
    required Map<String, Object?> input,
  }) {
    final data = input['data'] as Map? ?? const <String, Object?>{};
    final rawRows = data[capability];
    final rows = rawRows is List
        ? rawRows.whereType<Map>().map((m) => Map<String, Object?>.from(m)).toList()
        : <Map<String, Object?>>[];

    final children = <Map<String, Object?>>[
      <String, Object?>{'type': 'heading', 'text': heading},
    ];

    if (rows.isEmpty) {
      children.add(<String, Object?>{
        'type': 'text',
        'text': 'No rows reporting',
        'tone': 'warn',
      });
      return <String, Object?>{
        'state': input['state'],
        'view': <String, Object?>{'type': 'column', 'children': children},
      };
    }

    final sampleRow = rows.first;
    final resolvedLabelField = labelField ??
        sampleRow.keys.firstWhere(
          (k) => sampleRow[k] is String || VibeSealedHandle.tryParse(sampleRow[k]) != null,
          orElse: () => sampleRow.keys.first,
        );
    final resolvedValueField = valueField ??
        sampleRow.keys.firstWhere(
          (k) => sampleRow[k] is num,
          orElse: () => '',
        );

    if (resolvedValueField.isNotEmpty) {
      rows.sort((a, b) {
        final va = (a[resolvedValueField] as num?)?.toDouble() ?? 0.0;
        final vb = (b[resolvedValueField] as num?)?.toDouble() ?? 0.0;
        return vb.compareTo(va);
      });
    }

    final displayRows =
        limit != null && limit > 0 ? rows.take(limit).toList() : rows;

    var computedMax = maxVal ?? 1.0;
    if (maxVal == null && resolvedValueField.isNotEmpty) {
      var top = 1.0;
      for (final r in displayRows) {
        final v = (r[resolvedValueField] as num?)?.toDouble() ?? 0.0;
        if (v > top) top = v;
      }
      computedMax = top <= 1.0 ? 1.0 : top;
    }

    for (final row in displayRows) {
      final lbl = row[resolvedLabelField] ?? 'item';
      final val = resolvedValueField.isNotEmpty
          ? (row[resolvedValueField] as num?)?.toDouble() ?? 0.0
          : 1.0;
      final caption = resolvedValueField.isNotEmpty
          ? (computedMax == 1.0 && val <= 1.0
              ? '${(val * 100).round()}%'
              : '${val is int || val == val.roundToDouble() ? val.round() : val}')
          : (row['status']?.toString() ?? '');
      children.add(<String, Object?>{
        'type': 'bar',
        'label': lbl,
        if (caption.isNotEmpty) 'caption': caption,
        'value': val,
        'max': computedMax,
      });
    }

    return <String, Object?>{
      'state': input['state'],
      'view': <String, Object?>{'type': 'column', 'children': children},
    };
  }

  static Map<String, Object?> _evalCountdownTimer({
    required int durationMin,
    String? heading,
    required Map<String, Object?> input,
  }) {
    final duration = durationMin * 60 * 1000;
    var st = input['state'] is Map
        ? Map<String, Object?>.from(input['state'] as Map)
        : <String, Object?>{
            'running': false,
            'paused': false,
            'remainingMs': duration,
            'endAt': null,
          };

    final now = input['now'] is int
        ? input['now'] as int
        : DateTime.now().millisecondsSinceEpoch;
    final cmd = input['command']?.toString() ?? 'open';

    if (cmd == 'start') {
      if (st['running'] != true) {
        final rem = (st['remainingMs'] as num?)?.toInt() ?? duration;
        final base = rem > 0 ? rem : duration;
        st = <String, Object?>{
          'running': true,
          'paused': false,
          'remainingMs': base,
          'endAt': now + base,
        };
      }
    } else if (cmd == 'pause') {
      if (st['running'] == true && st['endAt'] is num) {
        final left = max(0, (st['endAt'] as num).toInt() - now);
        st = <String, Object?>{
          'running': false,
          'paused': true,
          'remainingMs': left,
          'endAt': null,
        };
      }
    } else if (cmd == 'reset') {
      st = <String, Object?>{
        'running': false,
        'paused': false,
        'remainingMs': duration,
        'endAt': null,
      };
    } else if (st['running'] == true && st['endAt'] is num) {
      final left = max(0, (st['endAt'] as num).toInt() - now);
      st = left == 0
          ? <String, Object?>{
              'running': false,
              'paused': false,
              'remainingMs': 0,
              'endAt': null,
            }
          : <String, Object?>{
              'running': true,
              'paused': false,
              'remainingMs': left,
              'endAt': st['endAt'],
            };
    }

    final rem = (st['remainingMs'] as num?)?.toInt() ?? duration;
    final totalSeconds = rem <= 0 ? 0 : (rem < 1000 ? 1 : rem ~/ 1000);
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    final timeText =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    final elapsed = (duration - rem).clamp(0, duration);
    final minsLeft = (rem / 60000).ceil();
    final running = st['running'] == true;
    final isPaused = st['paused'] == true || (!running && rem > 0 && rem < duration);
    final statusText =
        running ? 'Running' : (rem == 0 ? 'Done' : (isPaused ? 'Paused' : 'Ready'));
    final tone = rem == 0
        ? 'ok'
        : (running ? (rem <= 5 * 60 * 1000 ? 'warn' : 'ok') : 'default');

    final buttons = <Map<String, Object?>>[];
    if (running) {
      buttons.add(<String, Object?>{
        'type': 'button',
        'text': 'Pause',
        'command': 'pause',
        'tone': 'warn',
      });
    } else if (rem > 0) {
      buttons.add(<String, Object?>{
        'type': 'button',
        'text': isPaused ? 'Resume' : 'Start',
        'command': 'start',
        'tone': 'ok',
      });
    }
    buttons.add(<String, Object?>{
      'type': 'button',
      'text': 'Reset',
      'command': 'reset',
      'tone': 'default',
    });

    return <String, Object?>{
      'state': st,
      'view': <String, Object?>{
        'type': 'column',
        'children': <Map<String, Object?>>[
          if (heading != null && heading.isNotEmpty)
            <String, Object?>{'type': 'heading', 'text': heading},
          <String, Object?>{
            'type': 'row',
            'children': <Map<String, Object?>>[
              <String, Object?>{
                'type': 'stat',
                'label': 'Time left',
                'value': timeText,
                'tone': tone,
              },
              <String, Object?>{
                'type': 'badge',
                'text': statusText,
                'tone': tone,
              },
            ],
          },
          <String, Object?>{
            'type': 'bar',
            'label': '$durationMin-minute session',
            'value': elapsed,
            'max': duration,
            'caption': rem == 0 ? 'Done' : '$minsLeft min left',
            'tone': tone,
          },
          <String, Object?>{
            'type': 'row',
            'children': buttons,
          },
        ],
      },
    };
  }

  static double? _parseNamedNumber(String source, String name) {
    final m = RegExp('\\b$name\\s*=\\s*([0-9]+(?:\\.[0-9]+)?)').firstMatch(source);
    return m != null ? double.tryParse(m.group(1)!) : null;
  }

  static double? _parsePrimaryThreshold(String source) {
    final explicit =
        _parseNamedNumber(source, 'THRESHOLD') ??
        _parseNamedNumber(source, 'DANGER_LEVEL');
    if (explicit != null) {
      return explicit > 1.0 ? (explicit / 100.0).clamp(0.01, 1.0) : explicit;
    }
    final cmp = RegExp(r'usedFraction\s*>=\s*(0\.[0-9]+)').firstMatch(source);
    if (cmp != null) return double.tryParse(cmp.group(1)!);
    return null;
  }

  static int? _parseTopLimit(String source) {
    final explicit = _parseNamedNumber(source, 'TOP_LIMIT');
    if (explicit != null && explicit >= 1) return explicit.round();
    final slice = RegExp(r'\.slice\(\s*0\s*,\s*([0-9]+)\s*\)').firstMatch(source);
    if (slice != null) return int.tryParse(slice.group(1)!);
    return null;
  }

  static int? _parseDurationMinutes(String source) {
    final explicit = _parseNamedNumber(source, 'DURATION_MIN');
    if (explicit != null && explicit >= 1) return explicit.round();
    final prod = RegExp(r'DURATION\s*=\s*([0-9]+)\s*\*\s*60\s*\*\s*1000').firstMatch(source);
    if (prod != null) return int.tryParse(prod.group(1)!);
    return null;
  }

  static String? _parseHeadingLiteral(String source) {
    final m = RegExp(
      r'''type\s*:\s*['"]heading['"]\s*,\s*text\s*:\s*(['"])((?:\\.|(?!\1).)*)\1''',
    ).firstMatch(source);
    if (m != null) {
      return m.group(2)?.replaceAll(r'\u00b7', '·');
    }
    return null;
  }

  static bool _hasBalancedDelimiters(String source) {
    var braces = 0;
    var parens = 0;
    var brackets = 0;
    String? quote;
    var escaped = false;
    for (var i = 0; i < source.length; i++) {
      final ch = source[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (quote != null) {
        if (ch == r'\') {
          escaped = true;
        } else if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == "'" || ch == '"' || ch == '`') {
        quote = ch;
        continue;
      }
      if (ch == '{') braces++;
      else if (ch == '}') {
        braces--;
        if (braces < 0) return false;
      } else if (ch == '(') parens++;
      else if (ch == ')') {
        parens--;
        if (parens < 0) return false;
      } else if (ch == '[') brackets++;
      else if (ch == ']') {
        brackets--;
        if (brackets < 0) return false;
      }
    }
    return quote == null && braces == 0 && parens == 0 && brackets == 0;
  }

  static Map<String, Object?>? _tryEvalStaticReturnLiteral(String source) {
    final retIdx = source.lastIndexOf('return');
    if (retIdx < 0) return null;
    final braceStart = source.indexOf('{', retIdx);
    if (braceStart < 0) return null;
    var depth = 0;
    String? quote;
    var escaped = false;
    var braceEnd = -1;
    for (var i = braceStart; i < source.length; i++) {
      final ch = source[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (quote != null) {
        if (ch == r'\') escaped = true;
        else if (ch == quote) quote = null;
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
        continue;
      }
      if (ch == '{') depth++;
      else if (ch == '}') {
        depth--;
        if (depth == 0) {
          braceEnd = i;
          break;
        }
      }
    }
    if (braceEnd <= braceStart) return null;
    final rawObj = source.substring(braceStart, braceEnd + 1);
    final jsonCandidate = _jsLiteralToJson(rawObj);
    try {
      final decoded = jsonDecode(jsonCandidate);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } on Object {
      return null;
    }
    return null;
  }

  static String _jsLiteralToJson(String raw) {
    final out = StringBuffer();
    var i = 0;
    while (i < raw.length) {
      final ch = raw[i];
      if (ch == "'" || ch == '"') {
        final q = ch;
        out.write('"');
        i++;
        while (i < raw.length && raw[i] != q) {
          if (raw[i] == r'\' && i + 1 < raw.length) {
            final next = raw[i + 1];
            if (next == "'") {
              out.write("'");
            } else {
              out.write(r'\');
              out.write(next);
            }
            i += 2;
            continue;
          }
          if (raw[i] == '"') {
            out.write(r'\"');
          } else {
            out.write(raw[i]);
          }
          i++;
        }
        out.write('"');
        i++;
        continue;
      }
      if (_isIdentStart(ch)) {
        final start = i;
        while (i < raw.length && _isIdentPart(raw[i])) {
          i++;
        }
        final word = raw.substring(start, i);
        var look = i;
        while (look < raw.length && (raw[look] == ' ' || raw[look] == '\t' || raw[look] == '\n' || raw[look] == '\r')) {
          look++;
        }
        if (look < raw.length && raw[look] == ':') {
          out.write('"');
          out.write(word);
          out.write('"');
        } else if (word == 'undefined') {
          out.write('null');
        } else {
          out.write(word);
        }
        continue;
      }
      out.write(ch);
      i++;
    }
    return out.toString().replaceAllMapped(
      RegExp(r',(\s*[}\]])'),
      (m) => m[1]!,
    );
  }

  static bool _isIdentStart(String ch) => RegExp(r'[A-Za-z_$]').hasMatch(ch);
  static bool _isIdentPart(String ch) => RegExp(r'[A-Za-z0-9_$]').hasMatch(ch);
}

/// Applies wish-based parameter remixes to an existing [VibeSpec].
class VibeWishRemixer {
  const VibeWishRemixer._();

  static ({bool ok, VibeSpec? vibe, String? message}) apply(
    VibeSpec base,
    String wishText, {
    List<VibeWishPreset> presets = const <VibeWishPreset>[],
  }) {
    final trimmed = wishText.trim();
    if (trimmed.isEmpty) {
      return (ok: false, vibe: null, message: 'Enter a change wish first.');
    }
    final lower = trimmed.toLowerCase();

    for (final preset in presets) {
      if (preset.remixOf == base.id &&
          preset.text.trim().toLowerCase() == lower) {
        return (
          ok: true,
          vibe: preset.vibe.copyWith(
            version: base.version + 1,
            wish: trimmed,
          ),
          message: 'Remixed to v${base.version + 1}.',
        );
      }
    }

    var nextSource = base.source;
    var changed = false;

    final pctMatch = RegExp(
      r'(?:red|warn|alert|above|over|threshold|阈值|超过|红色|警告|임계값|umbral|seuil|schwellenwert|حد)?\s*(\d{1,3})\s*[%％]',
    ).firstMatch(lower);
    if (pctMatch != null) {
      final pct = int.parse(pctMatch.group(1)!).clamp(1, 99);
      final frac = (pct / 100.0).toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      if (nextSource.trimLeft().startsWith('{')) {
        try {
          final decoded = jsonDecode(nextSource);
          if (decoded is Map && decoded.containsKey('threshold')) {
            decoded['threshold'] = pct / 100.0;
            nextSource = jsonEncode(decoded);
            changed = true;
          }
        } on Object {
          // ignore
        }
      } else {
        if (RegExp(r'\bTHRESHOLD\s*=\s*[0-9.]+').hasMatch(nextSource)) {
          nextSource = nextSource.replaceFirstMapped(
            RegExp(r'(\bTHRESHOLD\s*=\s*)[0-9.]+'),
            (m) => '${m[1]}$frac',
          );
          changed = true;
        } else if (RegExp(r'\bDANGER_LEVEL\s*=\s*[0-9.]+').hasMatch(nextSource)) {
          nextSource = nextSource.replaceFirstMapped(
            RegExp(r'(\bDANGER_LEVEL\s*=\s*)[0-9.]+'),
            (m) => '${m[1]}$frac',
          );
          changed = true;
        } else if (nextSource.contains('usedFraction')) {
          nextSource = nextSource
              .replaceFirstMapped(
                RegExp(r'(usedFraction\s*>=\s*)0\.(?:8|80|9|90|7|70|75|85|95)'),
                (m) => '${m[1]}$frac',
              )
              .replaceFirstMapped(
                RegExp(r'(usedFraction\s*>=\s*)0\.(?:8|80|9|90|7|70|75|85|95)'),
                (m) => '${m[1]}$frac',
              )
              .replaceAll(
                RegExp(r'above \d{1,3}%'),
                'above $pct%',
              );
          changed = true;
        }
      }
    }

    final countMatch = RegExp(
      r'(?:(?:top|worst|best|first|only(?:\s+the)?(?:\s+worst|\s+top)?|peores|primeros|mejores|pires|premiers|meilleurs|schlechtesten|ersten)\s+|(?:最差|前|最多|最悪|上位|상위|أسوأ|أول)\s*)(\d+|two|three|four|five|six|eight|ten|两|三|四|五|六|八|十)(?=\s|$|个|台|件|項目|개)',
    ).firstMatch(lower);
    if (countMatch != null) {
      final count = _parseWordOrInt(countMatch.group(1)!);
      if (count != null && count >= 1 && count <= 50) {
        if (nextSource.trimLeft().startsWith('{')) {
          try {
            final decoded = jsonDecode(nextSource);
            if (decoded is Map) {
              decoded['limit'] = count;
              nextSource = jsonEncode(decoded);
              changed = true;
            }
          } on Object {
            // ignore
          }
        } else if (RegExp(r'\bTOP_LIMIT\s*=\s*\d+').hasMatch(nextSource)) {
          nextSource = nextSource.replaceFirstMapped(
            RegExp(r'(\bTOP_LIMIT\s*=\s*)\d+'),
            (m) => '${m[1]}$count',
          );
          changed = true;
        } else if (RegExp(r'\.slice\(\s*0\s*,\s*\d+\s*\)').hasMatch(nextSource)) {
          nextSource = nextSource.replaceFirstMapped(
            RegExp(r'(\.slice\(\s*0\s*,\s*)\d+(\s*\))'),
            (m) => '${m[1]}$count${m[2]}',
          );
          changed = true;
        } else if (nextSource.contains('sorted')) {
          nextSource = nextSource.replaceFirst(
            'var sorted = rows.slice()',
            'var TOP_LIMIT = $count;\nvar sorted = rows.slice()',
          );
          changed = true;
        }
      }
    }

    final daysMatch = RegExp(
      r'(?:^|[^\d])(\d{1,3})\s*(?:days?|d[ií]as?|jours?|tage?|天|日|일|أيام|يوم)(?=$|\s|[.,!?，。])',
    ).firstMatch(lower);
    if (daysMatch != null) {
      final days = int.parse(daysMatch.group(1)!).clamp(1, 365);
      if (RegExp(r'\bWINDOW_DAYS\s*=\s*\d+').hasMatch(nextSource)) {
        nextSource = nextSource.replaceFirstMapped(
          RegExp(r'(\bWINDOW_DAYS\s*=\s*)\d+'),
          (m) => '${m[1]}$days',
        );
        changed = true;
      } else if (RegExp(r'\b\d+\s*\*\s*dayMs\b').hasMatch(nextSource)) {
        nextSource = nextSource.replaceFirstMapped(
          RegExp(r'\b\d+(\s*\*\s*dayMs\b)'),
          (m) => '$days${m[1]}',
        );
        changed = true;
      }
    }

    final minMatch = RegExp(
      r'(?:^|[^\d])(\d{1,3})[\s-]*(?:minutes?|mins?|minutos?|minuten?|分钟|分|분|دقائق|دقيقة)(?=$|\s|[.,!?，。])',
    ).firstMatch(lower);
    if (minMatch != null) {
      final mins = int.parse(minMatch.group(1)!).clamp(1, 240);
      if (nextSource.trimLeft().startsWith('{')) {
        try {
          final decoded = jsonDecode(nextSource);
          if (decoded is Map && decoded['kind'] == 'countdown_timer') {
            decoded['durationMin'] = mins;
            nextSource = jsonEncode(decoded);
            changed = true;
          }
        } on Object {
          // ignore
        }
      } else if (RegExp(r'\bDURATION_MIN\s*=\s*\d+').hasMatch(nextSource)) {
        nextSource = nextSource.replaceFirstMapped(
          RegExp(r'(\bDURATION_MIN\s*=\s*)\d+'),
          (m) => '${m[1]}$mins',
        );
        changed = true;
      } else if (RegExp(r'\bDURATION\s*=\s*\d+\s*\*\s*60\s*\*\s*1000').hasMatch(nextSource)) {
        nextSource = nextSource.replaceFirstMapped(
          RegExp(r'(\bDURATION\s*=\s*)\d+(\s*\*\s*60\s*\*\s*1000)'),
          (m) => '${m[1]}$mins${m[2]}',
        );
        changed = true;
      }
    }

    if (!changed) {
      return (
        ok: false,
        vibe: null,
        message: 'Try specifying a threshold (e.g. "75%"), count (e.g. "worst 3"), or duration (e.g. "10 minutes"), or switch to Edit code.',
      );
    }

    return (
      ok: true,
      vibe: base.copyWith(
        version: base.version + 1,
        wish: trimmed,
        source: nextSource,
      ),
      message: 'Updated to version ${base.version + 1}.',
    );
  }

  static int? _parseWordOrInt(String raw) {
    final parsed = int.tryParse(raw);
    if (parsed != null) return parsed;
    return switch (raw) {
      'two' || '两' => 2,
      'three' || '三' => 3,
      'four' || '四' => 4,
      'five' || '五' => 5,
      'six' || '六' => 6,
      'eight' || '八' => 8,
      'ten' || '十' => 10,
      _ => null,
    };
  }
}

/// Matches scripted wish presets or compiles natural-language wishes against a
/// [VibeProtocolHost]'s offered capabilities.
class VibeWishCompiler {
  const VibeWishCompiler._();

  static bool _containsAny(String haystack, List<String> needles) {
    for (final needle in needles) {
      if (haystack.contains(needle)) return true;
    }
    return false;
  }

  static VibeSpec? compile(
    String wishText,
    VibeProtocolHost host, {
    List<VibeWishPreset> presets = const <VibeWishPreset>[],
  }) {
    final trimmed = wishText.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();

    for (final preset in presets) {
      if (preset.text.trim().toLowerCase() == lower) {
        return preset.vibe;
      }
    }

    if (_containsAny(lower, const <String>[
      'timer',
      'focus',
      'pomodoro',
      'countdown',
      '专注',
      '计时',
      '倒计时',
      'タイマー',
      '타이머',
      'temporizador',
      'minuteur',
      'مؤقت',
    ])) {
      final remixed = VibeWishRemixer.apply(kPortableFocusTimerVibe, trimmed);
      return remixed.ok && remixed.vibe != null
          ? remixed.vibe!.copyWith(version: 1, wish: trimmed)
          : kPortableFocusTimerVibe.copyWith(wish: trimmed);
    }

    final offered = <String>{for (final c in host.capabilities) c.name};

    if (_containsAny(lower, const <String>[
          'disk',
          'volume',
          'storage',
          '磁盘',
          '硬盘',
          '存储',
          'ディスク',
          '디스크',
          'disco',
          'disque',
          'festplatte',
          'قرص',
        ]) &&
        offered.contains('telemetry.disk')) {
      final base = VibeSpec(
        id: 'disk-watch',
        name: 'Disk Watch',
        wish: trimmed,
        version: 1,
        needs: const <String>['telemetry.disk'],
        refreshMs: 2000,
        source: jsonEncode(<String, Object?>{
          'kind': 'disk_watch',
          'threshold': 0.8,
          'warn': 0.6,
          'heading': 'Disk usage',
        }),
      );
      final remixed = VibeWishRemixer.apply(base, trimmed);
      return remixed.ok && remixed.vibe != null
          ? remixed.vibe!.copyWith(version: 1, wish: trimmed)
          : base;
    }

    if (_containsAny(lower, const <String>[
          'cpu',
          'memory',
          'mem',
          'load',
          'slow',
          '内存',
          '负载',
          '处理器',
          'メモリ',
          '메모리',
          'memoria',
          'mémoire',
          'speicher',
          'ذاكرة',
        ]) &&
        offered.contains('telemetry.load')) {
      return VibeSpec(
        id: 'server-load',
        name: 'CPU and memory',
        wish: trimmed,
        version: 1,
        needs: const <String>['telemetry.load'],
        refreshMs: 2000,
        source: jsonEncode(<String, Object?>{
          'kind': 'server_load',
          'heading': 'CPU and memory',
        }),
      );
    }

    if (host.capabilities.isNotEmpty) {
      final cap = host.capabilities.firstWhere(
        (c) => lower.contains(c.name.split('.').first),
        orElse: () => host.capabilities.first,
      );
      if (_containsAny(lower, const <String>[
        'session',
        'server',
        'active',
        'show',
        'top',
        '会话',
        '服务器',
        '显示',
        'セッション',
        '세션',
        'sesión',
        'servidor',
        'sitzung',
        'جلسة',
      ])) {
        return VibeSpec(
          id: 'custom-view',
          name: cap.title,
          wish: trimmed,
          version: 1,
          needs: <String>[cap.name],
          refreshMs: 2000,
          source: jsonEncode(<String, Object?>{
            'kind': 'metric_bars',
            'capability': cap.name,
            'heading': cap.title,
          }),
        );
      }
    }

    return null;
  }
}

/// Host capability broker, sealed handle table, lifecycle store, and mount manager.
class VibeProtocolHost {
  VibeProtocolHost({
    required this.id,
    required this.name,
    required List<VibeCapability> capabilities,
    List<String> notOffered = const <String>[],
    VibeStorageAdapter? storage,
    FutureOr<Map<String, Object?>> Function(
      VibeSpec vibe,
      Map<String, Object?> input,
    )? customRunner,
  })  : _capabilities = List<VibeCapability>.unmodifiable(capabilities),
        _notOffered = List<String>.unmodifiable(notOffered),
        _storage = storage ?? InMemoryVibeStorage(),
        _customRunner = customRunner {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Host id must be non-empty');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Host name must be non-empty');
    }
    for (final cap in _capabilities) {
      if (cap.name.trim().isEmpty) {
        throw ArgumentError('Each capability must have a non-empty name');
      }
      _capByName[cap.name] = cap;
    }
    _loadHandles();
  }

  final String id;
  final String name;
  final List<VibeCapability> _capabilities;
  final List<String> _notOffered;
  final VibeStorageAdapter _storage;
  final FutureOr<Map<String, Object?>> Function(
    VibeSpec vibe,
    Map<String, Object?> input,
  )? _customRunner;

  final Map<String, VibeCapability> _capByName = <String, VibeCapability>{};
  final Map<String, String> _valueToHandle = <String, String>{};
  final Map<String, String> _handleToValue = <String, String>{};
  final Set<void Function()> _changeListeners = <void Function()>{};
  final Set<VibeRunController> _activeRuns = <VibeRunController>{};
  bool _disposed = false;

  String get _handlesKey => 'vibekit:$id:handles';
  String get _installsKey => 'vibekit:$id';

  List<VibeCapability> get capabilities => _capabilities;
  List<String> get notOffered => _notOffered;

  void _loadHandles() {
    final raw = _storage.read(_handlesKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map && parsed['entries'] is List) {
        for (final item in parsed['entries'] as List) {
          if (item is List && item.length == 2) {
            final real = item[0]?.toString();
            final handle = item[1]?.toString();
            if (real != null && handle != null && handle.isNotEmpty) {
              _valueToHandle.putIfAbsent(real, () => handle);
              _handleToValue.putIfAbsent(handle, () => real);
            }
          }
        }
      }
    } on Object {
      // Ignore corrupted persisted handles
    }
  }

  void _saveHandles() {
    final entries = <List<String>>[
      for (final entry in _valueToHandle.entries) <String>[entry.key, entry.value],
    ];
    _storage.write(
      _handlesKey,
      jsonEncode(<String, Object?>{'v': 1, 'entries': entries}),
    );
  }

  /// Deterministically seals [realValue] to a host-specific opaque handle
  /// (`h_<16 lower hex>`), persisted in storage under `vibekit:<hostId>:handles`.
  VibeSealedHandle seal(String realValue) {
    final existing = _valueToHandle[realValue];
    if (existing != null) return VibeSealedHandle(existing);

    _loadHandles();
    final reloaded = _valueToHandle[realValue];
    if (reloaded != null) return VibeSealedHandle(reloaded);

    String handle;
    do {
      handle = 'h_${_randomHex(8)}';
    } while (_handleToValue.containsKey(handle));

    _valueToHandle[realValue] = handle;
    _handleToValue[handle] = realValue;
    _saveHandles();
    return VibeSealedHandle(handle);
  }

  /// Resolves a sealed handle or handle ID for draw-time rendering.
  /// Returns `null` for forged, unknown, or malformed handles.
  String? resolveSealed(Object? handleOrId) {
    String? handleId;
    if (handleOrId is VibeSealedHandle) {
      handleId = handleOrId.sealed;
    } else if (handleOrId is Map) {
      handleId = VibeSealedHandle.tryParse(handleOrId)?.sealed;
    } else if (handleOrId is String && handleOrId.isNotEmpty) {
      handleId = handleOrId;
    }
    if (handleId == null || handleId.isEmpty) return null;
    if (!_handleToValue.containsKey(handleId)) {
      _loadHandles();
    }
    return _handleToValue[handleId];
  }

  Map<String, Object?> _sealRow(
    Map<String, Object?> row,
    Map<String, String> fields,
  ) {
    final copy = _deepCloneJson(row) as Map<String, Object?>;
    for (final entry in fields.entries) {
      if (entry.value == 'sealed' &&
          copy.containsKey(entry.key) &&
          copy[entry.key] != null) {
        copy[entry.key] = seal(copy[entry.key].toString()).toJson();
      }
    }
    return copy;
  }

  List<Map<String, Object?>> _sealRows(
    List<dynamic> rawRows,
    Map<String, String> fields,
  ) {
    final out = <Map<String, Object?>>[];
    for (final item in rawRows) {
      if (item is Map) {
        final typed = item.map((k, v) => MapEntry(k.toString(), v));
        out.add(_sealRow(typed, fields));
      }
    }
    return out;
  }

  Map<String, Object?> manifest() => <String, Object?>{
        'protocol': 'vibeprotocol-demo/0',
        'host': <String, Object?>{'id': id, 'name': name},
        'capabilities': <Map<String, Object?>>[
          for (final c in _capabilities) c.toManifestJson(),
        ],
        'notOffered': List<String>.from(_notOffered),
      };

  VibeCheckResult check(VibeSpec vibe) {
    vibe.validate();
    final missing = <String>[];
    final seen = <String>{};
    for (final capName in vibe.needs) {
      if (!_capByName.containsKey(capName) && seen.add(capName)) {
        missing.add(capName);
      }
    }
    return VibeCheckResult(ok: missing.isEmpty, missing: missing);
  }

  VibePermissionLabel label(VibeSpec vibe) {
    vibe.validate();
    final reads = <String>[];
    final cannot = <String>[];
    final cannotSeen = <String>{};

    if (vibe.needs.isEmpty) {
      reads.add('Nothing from $name');
    } else {
      for (final capName in vibe.needs) {
        final cap = _capByName[capName];
        if (cap == null) {
          reads.add('Missing capability: $capName');
          continue;
        }
        final note = cap.sealedNote;
        if (note != null && note.isNotEmpty) {
          reads.add('${cap.title} ($note)');
        } else {
          reads.add(cap.title);
        }
        final sc = cap.sealedCannot;
        if (sc != null && sc.isNotEmpty && cannotSeen.add(sc)) {
          cannot.add(sc);
        }
      }
    }

    for (final item in _notOffered) {
      if (cannotSeen.add(item)) {
        cannot.add(item);
      }
    }
    final finalCannot = 'Change anything in $name';
    if (cannotSeen.add(finalCannot)) {
      cannot.add(finalCannot);
    }

    return VibePermissionLabel(
      reads: List<String>.unmodifiable(reads),
      shows: const <String>['Only inside its own box'],
      cannot: List<String>.unmodifiable(cannot),
    );
  }

  /// Inspects detailed source issues for [capNames] (or all host capabilities when omitted).
  List<VibeSourceIssue> inspectSources([List<String>? capNames]) {
    final list = capNames ??
        <String>[for (final cap in _capabilities) cap.name];
    final issues = <VibeSourceIssue>[];
    final seen = <String>{};
    for (final capName in list) {
      if (!seen.add(capName)) continue;
      final cap = _capByName[capName];
      if (cap == null) {
        issues.add(
          VibeSourceIssue(
            capability: capName,
            title: capName,
            mode: VibeSourceMode.missing,
            reason: '$name does not offer $capName',
            hasSample: false,
          ),
        );
        continue;
      }
      final hasSample = cap.sample.isNotEmpty;
      final statusFn = cap.status;
      if (statusFn != null) {
        try {
          final st = statusFn();
          if (!st.available) {
            final mode = st.mode == VibeSourceMode.revoked
                ? VibeSourceMode.revoked
                : (st.mode == VibeSourceMode.missing
                    ? VibeSourceMode.missing
                    : VibeSourceMode.offline);
            final reason = (st.reason != null && st.reason!.trim().isNotEmpty)
                ? st.reason!.trim()
                : (mode == VibeSourceMode.revoked
                    ? 'Access to this data source is turned off'
                    : 'Data source is offline');
            issues.add(
              VibeSourceIssue(
                capability: capName,
                title: cap.title,
                mode: mode,
                reason: reason,
                hasSample: hasSample,
              ),
            );
          }
        } on Object catch (err) {
          issues.add(
            VibeSourceIssue(
              capability: capName,
              title: cap.title,
              mode: VibeSourceMode.offline,
              reason: err.toString(),
              hasSample: hasSample,
            ),
          );
        }
      }
    }
    return issues;
  }

  static VibeSourceMode _aggregateMode(List<VibeSourceIssue> issues) {
    if (issues.any((i) => i.mode == VibeSourceMode.missing)) {
      return VibeSourceMode.missing;
    }
    if (issues.any((i) => i.mode == VibeSourceMode.revoked)) {
      return VibeSourceMode.revoked;
    }
    if (issues.any((i) => i.mode == VibeSourceMode.offline)) {
      return VibeSourceMode.offline;
    }
    return VibeSourceMode.live;
  }

  /// Aggregate availability status for [capNames] (or all capabilities on this host).
  VibeSourceStatus sourceStatus([List<String>? capNames]) {
    final issues = inspectSources(capNames);
    if (issues.isEmpty) return const VibeSourceStatus.live();
    final mode = _aggregateMode(issues);
    final reason = issues
        .map((i) => '${i.title}: ${i.reason}')
        .join(' · ');
    return VibeSourceStatus(available: false, mode: mode, reason: reason);
  }

  /// Immediately notifies every active mounted run on this host to re-evaluate
  /// data sources without waiting for its refresh interval.
  void notifySourceChange() {
    final snapshot = List<VibeRunController>.from(_activeRuns);
    for (final run in snapshot) {
      run._onHostSourceChanged();
    }
  }

  List<VibeInstalledRecord> _loadRecords() {
    final raw = _storage.read(_installsKey);
    if (raw == null || raw.isEmpty) return <VibeInstalledRecord>[];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return <VibeInstalledRecord>[];
      final out = <VibeInstalledRecord>[];
      final seenIds = <String>{};
      var migrated = false;
      for (final item in parsed) {
        if (item is! Map) continue;
        try {
          final typed = item.map((k, v) => MapEntry(k.toString(), v));
          if (typed['instanceId'] is! String ||
              (typed['instanceId'] as String).trim().isEmpty ||
              typed['title'] is! String ||
              typed['history'] is! List) {
            migrated = true;
          }
          var rec = VibeInstalledRecord.fromJson(typed);
          if (!seenIds.add(rec.instanceId)) {
            rec = rec.copyWith(instanceId: 'inst_${_randomHex(8)}');
            seenIds.add(rec.instanceId);
            migrated = true;
          }
          out.add(rec);
        } on Object {
          // Skip invalid persisted vibe
        }
      }
      final ordered = _normalizeOrder(out);
      if (migrated) {
        _saveRecords(ordered);
      }
      return ordered;
    } on Object {
      return <VibeInstalledRecord>[];
    }
  }

  void _saveRecords(List<VibeInstalledRecord> records) {
    _storage.write(
      _installsKey,
      jsonEncode(<Map<String, Object?>>[for (final r in records) r.toJson()]),
    );
  }

  List<VibeInstalledRecord> _normalizeOrder(List<VibeInstalledRecord> records) {
    final pinned = <VibeInstalledRecord>[
      for (final r in records)
        if (r.pinned) r,
    ];
    final unpinned = <VibeInstalledRecord>[
      for (final r in records)
        if (!r.pinned) r,
    ];
    final combined = <VibeInstalledRecord>[...pinned, ...unpinned];
    return <VibeInstalledRecord>[
      for (var i = 0; i < combined.length; i++) combined[i].copyWith(order: i),
    ];
  }

  void _insertAtGroupTop(
    List<VibeInstalledRecord> records,
    VibeInstalledRecord record,
  ) {
    if (record.pinned) {
      records.insert(0, record);
    } else {
      var idx = 0;
      while (idx < records.length && records[idx].pinned) {
        idx++;
      }
      records.insert(idx, record);
    }
  }

  int _findRecordIndex(
    List<VibeInstalledRecord> records,
    String idOrInstanceId,
  ) {
    for (var i = 0; i < records.length; i++) {
      if (records[i].instanceId == idOrInstanceId) return i;
    }
    for (var i = 0; i < records.length; i++) {
      if (records[i].vibe.id == idOrInstanceId) return i;
    }
    return -1;
  }

  void _notifyChange() {
    final snapshot = List<void Function()>.from(_changeListeners);
    for (final fn in snapshot) {
      try {
        fn();
      } on Object {
        // Isolate listener failures
      }
    }
  }

  List<VibeInstalledRecord> installed() {
    return List<VibeInstalledRecord>.unmodifiable(
      _loadRecords().map((r) => r.copyWith()),
    );
  }

  bool _vibeChangedForHistory(VibeSpec prev, VibeSpec next) {
    return prev.version != next.version ||
        prev.source != next.source ||
        _canonicalJsonString(prev.needs) != _canonicalJsonString(next.needs);
  }

  VibeInstalledRecord install(
    VibeSpec vibe, {
    String? instanceId,
    String? title,
    String? note,
    String origin = 'yours',
    Map<String, Object?>? args,
    bool? pinned,
    bool? paused,
    bool? collapsed,
  }) {
    vibe.validate();
    final capCheck = check(vibe);
    if (!capCheck.ok) {
      throw StateError(
        'Cannot install vibe; missing capabilities: ${capCheck.missing.join(', ')}',
      );
    }
    final cleanOrigin = _kValidOrigins.contains(origin) ? origin : 'yours';
    final cleanArgs =
        args != null ? (_deepCloneJson(args) as Map<String, Object?>) : null;
    if (cleanArgs != null) _assertJsonSafe(cleanArgs);

    final records = _loadRecords();
    var matchIdx = -1;
    if (instanceId != null && instanceId.trim().isNotEmpty) {
      final target = instanceId.trim();
      matchIdx = records.indexWhere((r) => r.instanceId == target);
    } else {
      final argsKey = _canonicalJsonString(cleanArgs);
      matchIdx = records.indexWhere(
        (r) =>
            r.vibe.id == vibe.id &&
            _canonicalJsonString(r.args) == argsKey,
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    late VibeInstalledRecord record;

    if (matchIdx >= 0) {
      final prev = records[matchIdx];
      final nextHistory = List<VibeVersionSnapshot>.from(prev.history);
      if (_vibeChangedForHistory(prev.vibe, vibe)) {
        nextHistory.insert(
          0,
          VibeVersionSnapshot(
            vibe: prev.vibe,
            savedAtMs: prev.updatedAtMs,
          ),
        );
        if (nextHistory.length > kMaxVibeHistoryEntries) {
          nextHistory.removeRange(kMaxVibeHistoryEntries, nextHistory.length);
        }
      }
      final nextTitle = title != null
          ? _normalizeTitle(title, vibe.name)
          : (prev.title == prev.vibe.name ? vibe.name : prev.title);
      final nextNote = note != null ? _normalizeNote(note) : prev.note;
      final nextPinned = pinned ?? prev.pinned;

      record = prev.copyWith(
        vibe: vibe,
        origin: cleanOrigin,
        args: cleanArgs,
        clearArgs: cleanArgs == null,
        title: nextTitle,
        note: nextNote,
        pinned: nextPinned,
        paused: paused ?? prev.paused,
        collapsed: collapsed ?? prev.collapsed,
        updatedAtMs: now,
        history: nextHistory,
      );

      if (nextPinned != prev.pinned) {
        records.removeAt(matchIdx);
        _insertAtGroupTop(records, record);
      } else {
        records[matchIdx] = record;
      }
    } else {
      record = VibeInstalledRecord(
        instanceId: instanceId != null && instanceId.trim().isNotEmpty
            ? instanceId.trim()
            : 'inst_${_randomHex(8)}',
        vibe: vibe,
        origin: cleanOrigin,
        args: cleanArgs,
        title: _normalizeTitle(title, vibe.name),
        note: _normalizeNote(note),
        pinned: pinned ?? false,
        paused: paused ?? false,
        collapsed: collapsed ?? false,
        installedAtMs: now,
        updatedAtMs: now,
      );
      _insertAtGroupTop(records, record);
    }

    final ordered = _normalizeOrder(records);
    _saveRecords(ordered);
    _notifyChange();
    return ordered
        .firstWhere((r) => r.instanceId == record.instanceId)
        .copyWith();
  }

  VibeInstalledRecord updateRecord(
    String idOrInstanceId, {
    String? title,
    String? note,
    VibeSpec? vibe,
    Map<String, Object?>? args,
    bool clearArgs = false,
    bool? pinned,
    bool? paused,
    bool? collapsed,
  }) {
    final records = _loadRecords();
    final idx = _findRecordIndex(records, idOrInstanceId);
    if (idx < 0) {
      throw StateError('Installed vibe record not found: $idOrInstanceId');
    }

    final prev = records[idx];
    var nextVibe = prev.vibe;
    final nextHistory = List<VibeVersionSnapshot>.from(prev.history);

    if (vibe != null) {
      vibe.validate();
      final capCheck = check(vibe);
      if (!capCheck.ok) {
        throw StateError(
          'Cannot update vibe; missing capabilities: ${capCheck.missing.join(', ')}',
        );
      }
      if (_vibeChangedForHistory(prev.vibe, vibe)) {
        nextHistory.insert(
          0,
          VibeVersionSnapshot(
            vibe: prev.vibe,
            savedAtMs: prev.updatedAtMs,
          ),
        );
        if (nextHistory.length > kMaxVibeHistoryEntries) {
          nextHistory.removeRange(kMaxVibeHistoryEntries, nextHistory.length);
        }
      }
      nextVibe = vibe;
    }

    final nextTitle = title != null
        ? _normalizeTitle(title, nextVibe.name)
        : (vibe != null && prev.title == prev.vibe.name
            ? nextVibe.name
            : prev.title);
    final nextNote = note != null ? _normalizeNote(note) : prev.note;

    Map<String, Object?>? nextArgs = prev.args;
    var shouldClearArgs = false;
    if (clearArgs) {
      nextArgs = null;
      shouldClearArgs = true;
    } else if (args != null) {
      nextArgs = _deepCloneJson(args) as Map<String, Object?>;
      _assertJsonSafe(nextArgs);
    }

    final nextPinned = pinned ?? prev.pinned;
    final pinnedChanged = nextPinned != prev.pinned;
    final updated = prev.copyWith(
      vibe: nextVibe,
      title: nextTitle,
      note: nextNote,
      args: nextArgs,
      clearArgs: shouldClearArgs,
      pinned: nextPinned,
      paused: paused ?? prev.paused,
      collapsed: collapsed ?? prev.collapsed,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      history: nextHistory,
    );

    if (pinnedChanged) {
      records.removeAt(idx);
      _insertAtGroupTop(records, updated);
    } else {
      records[idx] = updated;
    }

    final ordered = _normalizeOrder(records);
    _saveRecords(ordered);
    _notifyChange();
    return ordered
        .firstWhere((r) => r.instanceId == updated.instanceId)
        .copyWith();
  }

  VibeInstalledRecord revertRecord(
    String idOrInstanceId, [
    int historyIndex = 0,
  ]) {
    final records = _loadRecords();
    final idx = _findRecordIndex(records, idOrInstanceId);
    if (idx < 0) {
      throw StateError('Installed vibe record not found: $idOrInstanceId');
    }
    final prev = records[idx];
    if (historyIndex < 0 || historyIndex >= prev.history.length) {
      throw RangeError.index(historyIndex, prev.history, 'historyIndex');
    }

    final snapshot = prev.history[historyIndex];
    snapshot.vibe.validate();
    final capCheck = check(snapshot.vibe);
    if (!capCheck.ok) {
      throw StateError(
        'Cannot revert vibe; missing capabilities: ${capCheck.missing.join(', ')}',
      );
    }

    final nextHistory = List<VibeVersionSnapshot>.from(prev.history);
    nextHistory.removeAt(historyIndex);
    nextHistory.insert(
      0,
      VibeVersionSnapshot(
        vibe: prev.vibe,
        savedAtMs: prev.updatedAtMs,
      ),
    );
    if (nextHistory.length > kMaxVibeHistoryEntries) {
      nextHistory.removeRange(kMaxVibeHistoryEntries, nextHistory.length);
    }

    final updated = prev.copyWith(
      vibe: snapshot.vibe,
      title: prev.title == prev.vibe.name ? snapshot.vibe.name : prev.title,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      history: nextHistory,
    );
    records[idx] = updated;

    final ordered = _normalizeOrder(records);
    _saveRecords(ordered);
    _notifyChange();
    return ordered
        .firstWhere((r) => r.instanceId == updated.instanceId)
        .copyWith();
  }

  List<VibeInstalledRecord> reorder(List<String> orderedInstanceIds) {
    final records = _loadRecords();
    final rank = <String, int>{};
    for (var i = 0; i < orderedInstanceIds.length; i++) {
      rank.putIfAbsent(orderedInstanceIds[i], () => i);
    }

    final indexed = <(VibeInstalledRecord, int)>[
      for (var i = 0; i < records.length; i++) (records[i], i),
    ];
    indexed.sort((a, b) {
      if (a.$1.pinned != b.$1.pinned) {
        return a.$1.pinned ? -1 : 1;
      }
      final ra = rank[a.$1.instanceId];
      final rb = rank[b.$1.instanceId];
      if (ra != null && rb != null) return ra.compareTo(rb);
      if (ra != null) return -1;
      if (rb != null) return 1;
      return a.$2.compareTo(b.$2);
    });

    final ordered = _normalizeOrder(<VibeInstalledRecord>[
      for (final entry in indexed) entry.$1,
    ]);
    _saveRecords(ordered);
    _notifyChange();
    return List<VibeInstalledRecord>.unmodifiable(
      ordered.map((r) => r.copyWith()),
    );
  }

  VibeInstalledRecord? uninstall(String idOrInstanceId) {
    final records = _loadRecords();
    final idx = _findRecordIndex(records, idOrInstanceId);
    if (idx < 0) return null;
    final removed = records.removeAt(idx);
    final ordered = _normalizeOrder(records);
    _saveRecords(ordered);
    _notifyChange();
    return removed.copyWith();
  }

  VibeInstalledRecord restoreRecord(
    VibeInstalledRecord snapshot, [
    int? index,
  ]) {
    snapshot.vibe.validate();
    final records = _loadRecords()
      ..removeWhere((r) => r.instanceId == snapshot.instanceId);
    final pos = index != null ? index.clamp(0, records.length) : 0;
    records.insert(pos, snapshot.copyWith());
    final ordered = _normalizeOrder(records);
    _saveRecords(ordered);
    _notifyChange();
    return ordered
        .firstWhere((r) => r.instanceId == snapshot.instanceId)
        .copyWith();
  }

  void Function() onChange(void Function() listener) {
    _changeListeners.add(listener);
    return () => _changeListeners.remove(listener);
  }

  VibeRunController mount(
    VibeSpec vibe, {
    String dataMode = 'live',
    Map<String, Object?>? args,
  }) {
    if (_disposed) {
      throw StateError('Host $id is disposed');
    }
    if (dataMode != 'live' && dataMode != 'sample') {
      throw ArgumentError.value(dataMode, 'dataMode', "Must be 'live' or 'sample'");
    }
    final cleanArgs =
        args != null ? (_deepCloneJson(args) as Map<String, Object?>) : null;
    if (cleanArgs != null) _assertJsonSafe(cleanArgs);

    final controller = VibeRunController._(
      host: this,
      vibe: vibe,
      initialDataMode: dataMode,
      mountArgs: cleanArgs,
    );
    _activeRuns.add(controller);
    controller._start();
    return controller;
  }

  void dispose() {
    _disposed = true;
    final runs = List<VibeRunController>.from(_activeRuns);
    for (final run in runs) {
      run.stop();
    }
    _activeRuns.clear();
    _changeListeners.clear();
  }
}

/// Active sandboxed mount controller with health tracking, stale preservation,
/// sample fallback, and automatic recovery via [VibeProtocolHost.notifySourceChange].
class VibeRunController {
  VibeRunController._({
    required VibeProtocolHost host,
    required VibeSpec vibe,
    required String initialDataMode,
    required Map<String, Object?>? mountArgs,
  })  : _host = host,
        _vibe = vibe,
        _dataMode = initialDataMode,
        _mountArgs = mountArgs,
        _health = VibeRunHealth(
          state: initialDataMode == 'sample'
              ? VibeSourceMode.sample
              : VibeSourceMode.live,
        ),
        _reads = <String, int>{for (final cap in vibe.needs) cap: 0};

  final VibeProtocolHost _host;
  final VibeSpec _vibe;
  final Map<String, Object?>? _mountArgs;
  final Set<void Function()> _listeners = <void Function()>{};
  final Map<String, int> _reads;

  String _dataMode;
  bool _usingSampleFallback = false;
  bool _stopped = false;
  bool _hasOpened = false;
  bool _showingLiveView = false;
  int _generation = 0;

  Map<String, Object?>? _view;
  String? _lastError;
  String? _unavailableReason;
  VibeRunHealth _health;
  Object? _vibeState;
  Map<String, Object?> _latestInput = const <String, Object?>{};
  Map<String, Object?>? _latestOutput;
  int _calls = 0;
  Timer? _refreshTimer;

  Map<String, Object?>? get view =>
      _view != null ? (_deepCloneJson(_view) as Map<String, Object?>) : null;
  String? get lastError => _lastError;
  String? get unavailableReason => _unavailableReason;

  VibeRunHealth health() => VibeRunHealth(
        state: _health.state,
        issues: List<VibeSourceIssue>.unmodifiable(_health.issues),
        lastGoodAtMs: _health.lastGoodAtMs,
        usingSampleFallback: _health.usingSampleFallback,
      );

  VibeReadLedger ledger() => VibeReadLedger(
        reads: Map<String, int>.unmodifiable(Map<String, int>.from(_reads)),
        sent: 0,
        changed: 0,
        calls: _calls,
        lastError: _lastError,
      );

  VibeInspectSnapshot inspect() => VibeInspectSnapshot(
        input: _deepCloneJson(_latestInput) as Map<String, Object?>,
        output: _latestOutput != null
            ? (_deepCloneJson(_latestOutput) as Map<String, Object?>)
            : null,
        ledger: ledger(),
      );

  void _notifyUpdate() {
    final snapshot = List<void Function()>.from(_listeners);
    for (final fn in snapshot) {
      try {
        fn();
      } on Object {
        // Never leak listener exceptions
      }
    }
  }

  void _start() {
    try {
      _vibe.validate();
    } on Object catch (err) {
      _lastError = err.toString();
      _view = null;
      _stopped = true;
      _host._activeRuns.remove(this);
      _notifyUpdate();
      return;
    }

    _invoke('open', _mountArgs);

    final refreshMs = _vibe.refreshMs;
    if (!_stopped && refreshMs != null) {
      _refreshTimer = Timer.periodic(Duration(milliseconds: refreshMs), (_) {
        if (!_stopped) {
          _invoke(_hasOpened ? 'refresh' : 'open', _mountArgs);
        }
      });
    }
  }

  void _onHostSourceChanged() {
    if (_stopped) return;
    if (_dataMode == 'live') {
      retry();
    } else if (_usingSampleFallback) {
      _health = VibeRunHealth(
        state: VibeSourceMode.sample,
        issues: _host.inspectSources(_vibe.needs),
        lastGoodAtMs: _health.lastGoodAtMs,
        usingSampleFallback: true,
      );
      _notifyUpdate();
    }
  }

  Future<void> dispatch(String command, [Map<String, Object?>? args]) {
    if (_stopped) return Future<void>.value();
    final res = _invoke(command, args);
    return res is Future<void> ? res : Future<void>.value();
  }

  Future<void> retry() {
    if (_stopped) return Future<void>.value();
    final res = _invoke(_hasOpened ? 'refresh' : 'open', _mountArgs);
    return res is Future<void> ? res : Future<void>.value();
  }

  Future<void> setDataMode(String mode) {
    if (mode != 'live' && mode != 'sample') {
      throw ArgumentError.value(mode, 'mode', "Must be 'live' or 'sample'");
    }
    if (_stopped) return Future<void>.value();
    _dataMode = mode;
    _usingSampleFallback = mode == 'sample';
    final res = _invoke(_hasOpened ? 'refresh' : 'open', _mountArgs);
    return res is Future<void> ? res : Future<void>.value();
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _host._activeRuns.remove(this);
    _listeners.clear();
  }

  void Function() onUpdate(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  FutureOr<void> _invoke(String command, Map<String, Object?>? callArgs) {
    if (_stopped) return null;
    final gen = ++_generation;

    if (_dataMode == 'sample') {
      final issues = _host
          .inspectSources(_vibe.needs)
          .where((i) => i.mode == VibeSourceMode.missing)
          .toList();
      if (issues.isNotEmpty) {
        _applyUnavailable(issues);
        _notifyUpdate();
        return null;
      }
      final data = <String, Object?>{};
      for (final capName in _vibe.needs) {
        final cap = _host._capByName[capName]!;
        _reads[capName] = (_reads[capName] ?? 0) + 1;
        data[capName] = _host._sealRows(cap.sample, cap.fields);
      }
      return _runEvaluator(command, callArgs, data, gen);
    }

    final statusIssues = _host.inspectSources(_vibe.needs);
    if (statusIssues.isNotEmpty) {
      _applyUnavailable(statusIssues);
      _notifyUpdate();
      return null;
    }

    final rawByCap = <String, List<dynamic>>{};
    final asyncReads = <String, Future<Object?>>{};

    for (final capName in _vibe.needs) {
      if (rawByCap.containsKey(capName) || asyncReads.containsKey(capName)) {
        continue;
      }
      final cap = _host._capByName[capName]!;
      final hasSample = cap.sample.isNotEmpty;
      try {
        final res = cap.read();
        if (res is Future) {
          asyncReads[capName] = res.then<Object?>((v) => v);
        } else {
          final unavailable = VibeSourceStatus.tryFromReadResult(res);
          if (unavailable != null && !unavailable.available) {
            _applyUnavailable(<VibeSourceIssue>[
              _issueFromStatus(cap, unavailable, hasSample),
            ]);
            _notifyUpdate();
            return null;
          }
          if (res is! List) {
            _applyUnavailable(<VibeSourceIssue>[
              VibeSourceIssue(
                capability: capName,
                title: cap.title,
                mode: VibeSourceMode.offline,
                reason: 'Source returned unavailable data',
                hasSample: hasSample,
              ),
            ]);
            _notifyUpdate();
            return null;
          }
          rawByCap[capName] = res;
        }
      } on Object catch (err) {
        _applyUnavailable(<VibeSourceIssue>[
          VibeSourceIssue(
            capability: capName,
            title: cap.title,
            mode: VibeSourceMode.offline,
            reason: err.toString(),
            hasSample: hasSample,
          ),
        ]);
        _notifyUpdate();
        return null;
      }
    }

    if (asyncReads.isEmpty) {
      return _finishReadsAndEval(command, callArgs, rawByCap, gen);
    }

    return _awaitReadsAndEval(command, callArgs, rawByCap, asyncReads, gen);
  }

  VibeSourceIssue _issueFromStatus(
    VibeCapability cap,
    VibeSourceStatus status,
    bool hasSample,
  ) {
    final reason = (status.reason != null && status.reason!.trim().isNotEmpty)
        ? status.reason!.trim()
        : (status.mode == VibeSourceMode.revoked
            ? 'Access to this data source is turned off'
            : 'Data source is offline');
    return VibeSourceIssue(
      capability: cap.name,
      title: cap.title,
      mode: status.mode,
      reason: reason,
      hasSample: hasSample,
    );
  }

  Future<void> _awaitReadsAndEval(
    String command,
    Map<String, Object?>? callArgs,
    Map<String, List<dynamic>> rawByCap,
    Map<String, Future<Object?>> asyncReads,
    int gen,
  ) async {
    final issues = <VibeSourceIssue>[];
    for (final entry in asyncReads.entries) {
      final cap = _host._capByName[entry.key]!;
      final hasSample = cap.sample.isNotEmpty;
      try {
        final resolved = await entry.value;
        if (_stopped || gen != _generation) return;
        final unavailable = VibeSourceStatus.tryFromReadResult(resolved);
        if (unavailable != null && !unavailable.available) {
          issues.add(_issueFromStatus(cap, unavailable, hasSample));
        } else if (resolved is! List) {
          issues.add(
            VibeSourceIssue(
              capability: cap.name,
              title: cap.title,
              mode: VibeSourceMode.offline,
              reason: 'Source returned unavailable data',
              hasSample: hasSample,
            ),
          );
        } else {
          rawByCap[entry.key] = resolved;
        }
      } on Object catch (err) {
        if (_stopped || gen != _generation) return;
        issues.add(
          VibeSourceIssue(
            capability: cap.name,
            title: cap.title,
            mode: VibeSourceMode.offline,
            reason: err.toString(),
            hasSample: hasSample,
          ),
        );
      }
    }
    if (issues.isNotEmpty) {
      _applyUnavailable(issues);
      _notifyUpdate();
      return;
    }
    final res = _finishReadsAndEval(command, callArgs, rawByCap, gen);
    if (res is Future<void>) await res;
  }

  FutureOr<void> _finishReadsAndEval(
    String command,
    Map<String, Object?>? callArgs,
    Map<String, List<dynamic>> rawByCap,
    int gen,
  ) {
    final data = <String, Object?>{};
    for (final capName in _vibe.needs) {
      final cap = _host._capByName[capName]!;
      _reads[capName] = (_reads[capName] ?? 0) + 1;
      data[capName] = _host._sealRows(rawByCap[capName]!, cap.fields);
    }
    return _runEvaluator(command, callArgs, data, gen);
  }

  void _applyUnavailable(List<VibeSourceIssue> issues) {
    final mode = VibeProtocolHost._aggregateMode(issues);
    _usingSampleFallback = false;
    _lastError = null;
    _health = VibeRunHealth(
      state: mode,
      issues: List<VibeSourceIssue>.unmodifiable(issues),
      lastGoodAtMs: _health.lastGoodAtMs,
      usingSampleFallback: false,
    );
    if (_health.lastGoodAtMs != null && _showingLiveView && _view != null) {
      _unavailableReason = null;
    } else {
      _showingLiveView = false;
      _view = null;
      _unavailableReason = issues
          .map((i) => '${i.title}: ${i.reason}')
          .join(' · ');
    }
  }

  FutureOr<void> _runEvaluator(
    String command,
    Map<String, Object?>? callArgs,
    Map<String, Object?> data,
    int gen,
  ) {
    _calls += 1;
    final input = <String, Object?>{
      'command': command,
      'args': callArgs != null ? _deepCloneJson(callArgs) : null,
      'state': _deepCloneJson(_vibeState),
      'data': data,
      'host': <String, Object?>{'id': _host.id, 'name': _host.name},
      'now': DateTime.now().millisecondsSinceEpoch,
    };
    _latestInput = input;

    try {
      final evalRes = VibeSandboxEvaluator.evaluate(
        _vibe,
        input,
        customRunner: _host._customRunner,
      );
      if (evalRes is Future<Map<String, Object?>>) {
        return evalRes.then(
          (output) => _applyOutput(output, gen),
          onError: (Object err) => _applyEvalError(err, gen),
        );
      }
      _applyOutput(evalRes, gen);
    } on Object catch (err) {
      _applyEvalError(err, gen);
    }
    return null;
  }

  void _applyOutput(Map<String, Object?> output, int gen) {
    if (_stopped || gen != _generation) return;
    _vibeState = output['state'];
    _latestOutput = output;
    _lastError = null;
    _unavailableReason = null;
    _hasOpened = true;
    _view = output['view'] as Map<String, Object?>;

    if (_dataMode == 'live') {
      _showingLiveView = true;
      _health = VibeRunHealth(
        state: VibeSourceMode.live,
        issues: const <VibeSourceIssue>[],
        lastGoodAtMs: DateTime.now().millisecondsSinceEpoch,
        usingSampleFallback: false,
      );
    } else {
      _showingLiveView = false;
      _health = VibeRunHealth(
        state: VibeSourceMode.sample,
        issues: _usingSampleFallback
            ? _host.inspectSources(_vibe.needs)
            : const <VibeSourceIssue>[],
        lastGoodAtMs: _health.lastGoodAtMs,
        usingSampleFallback: _usingSampleFallback,
      );
    }
    _notifyUpdate();
  }

  void _applyEvalError(Object err, int gen) {
    if (_stopped || gen != _generation) return;
    _showingLiveView = false;
    _view = null;
    _latestOutput = null;
    _lastError = err.toString();
    _unavailableReason = null;
    _notifyUpdate();
  }
}
