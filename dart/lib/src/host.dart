import 'dart:async';
import 'dart:convert';

typedef JsonMap = Map<String, dynamic>;

bool validApiName(String value) =>
    value.length <= 128 &&
    RegExp(r'^[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)*$').hasMatch(value);

bool validCapability(Object? value) =>
    value is String &&
    (const {'network', 'terminal_read', 'terminal_write'}.contains(value) ||
        (value.startsWith('api:') && validApiName(value.substring(4))));

String effectCapability(JsonMap effect) {
  final method = effect['method'];
  final String required;
  switch (method) {
    case 'network.fetch':
      required = 'network';
    case 'terminal.read':
      required = 'terminal_read';
    case 'terminal.write':
      required = 'terminal_write';
    case 'host.call':
      final args = effect['arguments'];
      final api = args is Map ? args['api'] : null;
      if (api is! String || !validApiName(api)) {
        throw const FormatException('Invalid host API name');
      }
      required = 'api:$api';
    default:
      throw UnsupportedError('Unsupported extension effect: $method');
  }
  if (effect['capability'] != required) {
    throw StateError('Extension effect capability does not match its method');
  }
  if (effect['arguments'] != null && effect['arguments'] is! Map) {
    throw const FormatException('Invalid extension effect arguments');
  }
  return required;
}

Object? freezeJson(Object? value, {int depth = 0}) {
  if (depth > 64) throw const FormatException('Extension JSON is too deep');
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map((key, child) {
        if (key is! String) throw const FormatException('Invalid JSON key');
        return MapEntry(key, freezeJson(child, depth: depth + 1));
      }),
    );
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(
      value.map((child) => freezeJson(child, depth: depth + 1)),
    );
  }
  if (value == null ||
      value is String ||
      value is bool ||
      (value is num && value.isFinite)) return value;
  throw const FormatException('Invalid extension JSON');
}

/// The host executes this original immutable batch after review. Guest code is
/// never rerun to obtain "confirmed" replacement effects.
class VibeEffectBatch {
  VibeEffectBatch(List<dynamic> effects)
      : effects = List<JsonMap>.unmodifiable(
          (freezeJson(effects) as List).map((e) => e as JsonMap),
        ) {
    if (effects.length > 32 ||
        utf8.encode(jsonEncode(effects)).length > 1024 * 1024) {
      throw const FormatException('Extension effect limit exceeded');
    }
    final ids = <String>{};
    for (final effect in this.effects) {
      final id = effect['id'];
      if (id is! String || id.isEmpty || id.length > 128 || !ids.add(id)) {
        throw const FormatException('Invalid or duplicate effect ID');
      }
      effectCapability(effect);
    }
  }
  final List<JsonMap> effects;
}

/// A deliberately bounded subset of JSON Schema. Unsupported keywords fail
/// registration instead of being silently ignored. App-specific resource
/// admission belongs in the handler as well as these structural checks.
class VibeSchema {
  static const _keywords = {
    'type',
    'properties',
    'required',
    'additionalProperties',
    'items',
    'enum',
    'minimum',
    'maximum',
    'minLength',
    'maxLength',
    'maxItems',
    'description',
  };
  static void check(JsonMap schema, [int depth = 0]) {
    if (depth > 16 || schema.keys.any((k) => !_keywords.contains(k))) {
      throw const FormatException('Unsupported host API schema');
    }
    if (!const {
      'object',
      'array',
      'string',
      'number',
      'integer',
      'boolean',
      'null',
    }.contains(schema['type'])) {
      throw const FormatException('Host API schema requires a supported type');
    }

    for (final key in ['minLength', 'maxLength', 'maxItems']) {
      if (schema[key] != null &&
          (schema[key] is! int || (schema[key] as int) < 0)) {
        throw const FormatException('Invalid schema limit');
      }
    }
    for (final key in ['minimum', 'maximum']) {
      if (schema[key] != null &&
          (schema[key] is! num || !(schema[key] as num).isFinite)) {
        throw const FormatException('Invalid numeric limit');
      }
    }
    if (schema['enum'] != null &&
        (schema['enum'] is! List ||
            (schema['enum'] as List).isEmpty ||
            (schema['enum'] as List).length > 256)) {
      throw const FormatException('Invalid API enum');
    }
    if (schema['properties'] != null) {
      if (schema['type'] != 'object' || schema['properties'] is! Map)
        throw const FormatException('Invalid API properties');
      for (final child in (schema['properties'] as Map).values) {
        check(Map<String, dynamic>.from(child as Map), depth + 1);
      }
    }
    if (schema['items'] != null)
      check(Map<String, dynamic>.from(schema['items'] as Map), depth + 1);
    if (schema['required'] != null &&
        (schema['required'] is! List ||
            !(schema['required'] as List).every(
              (key) =>
                  key is String &&
                  (schema['properties'] as Map? ?? {}).containsKey(key),
            ))) {
      throw const FormatException('Invalid required API properties');
    }
    if (schema['additionalProperties'] != null &&
        schema['additionalProperties'] is! bool) {
      throw const FormatException('additionalProperties must be boolean');
    }
  }

  static void validate(Object? value, JsonMap schema, [int depth = 0]) {
    if (depth > 32) throw const FormatException('API value is too deep');
    final type = schema['type'];
    final valid = switch (type) {
      'object' => value is Map<String, dynamic>,
      'array' => value is List,
      'string' => value is String,
      'number' => value is num && value.isFinite,
      'integer' => value is int && value.abs() <= 9007199254740991,
      'boolean' => value is bool,
      'null' => value == null,
      _ => false,
    };
    if (!valid ||
        (schema['enum'] is List && !(schema['enum'] as List).contains(value))) {
      throw FormatException('API value does not match $type');
    }
    if (value is Map<String, dynamic>) {
      final properties = schema['properties'] as Map? ?? {};
      for (final key in schema['required'] as List? ?? []) {
        if (!value.containsKey(key))
          throw FormatException('Missing API field: $key');
      }
      for (final entry in value.entries) {
        if (!properties.containsKey(entry.key)) {
          if (schema['additionalProperties'] != true)
            throw FormatException('Unknown API field: ${entry.key}');
        } else {
          validate(
            entry.value,
            Map<String, dynamic>.from(properties[entry.key] as Map),
            depth + 1,
          );
        }
      }
    }
    if (value is List) {
      if (value.length > (schema['maxItems'] as num? ?? 1024))
        throw const FormatException('API array exceeds limit');
      if (schema['items'] is Map) {
        for (final item in value) {
          validate(
            item,
            Map<String, dynamic>.from(schema['items'] as Map),
            depth + 1,
          );
        }
      }
    }
    if (value is String &&
        (value.length < (schema['minLength'] as num? ?? 0) ||
            value.length > (schema['maxLength'] as num? ?? 64000))) {
      throw const FormatException('API string exceeds limit');
    }
    if (value is num &&
        (value < (schema['minimum'] as num? ?? double.negativeInfinity) ||
            value > (schema['maximum'] as num? ?? double.infinity))) {
      throw const FormatException('API number exceeds limit');
    }
  }
}

class VibeCallContext {
  VibeCallContext({
    required this.pluginId,
    required this.revision,
    required this.assertCurrent,
    this.resources = const {},
  });
  final String pluginId, revision;
  final JsonMap resources;
  final Future<void> Function() assertCurrent;
  bool _closed = false;
  Future<void> check() async {
    if (_closed) throw StateError('Host API invocation ended');
    await assertCurrent();
    if (_closed) throw StateError('Host API invocation ended');
  }
}

class VibeHostApi {
  VibeHostApi({
    required this.name,
    required this.version,
    required this.title,
    required this.description,
    required JsonMap inputSchema,
    required JsonMap outputSchema,
    required this.readOnly,
    required this.handler,
  })  : inputSchema = freezeJson(inputSchema) as JsonMap,
        outputSchema = freezeJson(outputSchema) as JsonMap {
    if (inputSchema['type'] != 'object')
      throw ArgumentError('API input must be an object');
    if (!validApiName(name) || version < 1)
      throw ArgumentError('Invalid host API');
    VibeSchema.check(inputSchema);
    VibeSchema.check(outputSchema);
  }
  final String name, title, description;
  final int version;
  final JsonMap inputSchema, outputSchema;
  final bool readOnly;
  final FutureOr<Object?> Function(JsonMap input, VibeCallContext context)
      handler;
  JsonMap get descriptor => {
        'name': name,
        'version': version,
        'title': title,
        'description': description,
        'capability': 'api:$name',
        'read_only': readOnly,
        'input_schema': inputSchema,
        'output_schema': outputSchema,
      };
}

class VibeHostRegistry {
  final Map<String, VibeHostApi> _apis = {};
  int _generation = 0;
  int get generation => _generation;
  void register(VibeHostApi api) {
    if (_apis.containsKey(api.name))
      throw StateError('Host API already registered');
    _apis[api.name] = api;
    _generation++;
  }

  void unregister(String name) {
    if (_apis.remove(name) != null) _generation++;
  }

  bool supports(String capability) =>
      capability.startsWith('api:') &&
      _apis.containsKey(capability.substring(4));
  List<JsonMap> get catalog =>
      _apis.values.map((api) => api.descriptor).toList(growable: false);
  VibeHostApi require(JsonMap args) {
    final api = _apis[args['api']];
    if (api == null || args['version'] != api.version)
      throw UnsupportedError('Host API or version unavailable');
    return api;
  }

  Future<Object?> call(
    JsonMap effect,
    Set<String> grants,
    VibeCallContext context, {
    Future<bool> Function(JsonMap)? approve,
  }) async {
    effect = VibeEffectBatch([effect]).effects.single;
    final capability = effectCapability(effect);
    if (!grants.contains(capability))
      throw StateError('Host API permission denied');
    final args = Map<String, dynamic>.from(effect['arguments'] as Map);
    final api = require(args), generation = _generation;
    final input = freezeJson(args['input'] ?? {}) as JsonMap;
    VibeSchema.validate(input, api.inputSchema);
    await context.check();
    try {
      if (!api.readOnly && (approve == null || !await approve(effect))) {
        throw StateError('Host API effect not approved');
      }
      await context.check();
      if (_generation != generation) throw StateError('Host API changed');
      final output = await Future.sync(() => api.handler(input, context))
          .timeout(const Duration(seconds: 20));
      await context.check();
      if (_generation != generation || !identical(_apis[api.name], api))
        throw StateError('Host API changed');
      if (utf8.encode(jsonEncode(output)).length > 1024 * 1024)
        throw const FormatException('API output exceeds limit');
      VibeSchema.validate(output, api.outputSchema);
      return freezeJson(output);
    } finally {
      context._closed = true;
    }
  }
}
