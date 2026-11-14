import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'compatibility_adapter.dart';
import 'vibe_runtime_config.dart';

/// Validates a `wasm32` binary module: enforces `<= 16 MiB`, magic header
/// `\x00asm\x01\x00\x00\x00`, zero host/WASI imports, and `<= 32 MiB` memory.
void validateVibeWasmBytes(Uint8List bytes) {
  if (bytes.length < 8) {
    throw const FormatException('Wasm binary is truncated (< 8 bytes)');
  }
  if (bytes.length > kMaxVibeWasmBytes) {
    throw FormatException(
      'Wasm binary exceeds 16 MiB limit (${bytes.length} bytes)',
    );
  }
  if (bytes[0] != 0x00 ||
      bytes[1] != 0x61 ||
      bytes[2] != 0x73 ||
      bytes[3] != 0x6d ||
      bytes[4] != 0x01 ||
      bytes[5] != 0x00 ||
      bytes[6] != 0x00 ||
      bytes[7] != 0x00) {
    throw const FormatException('Invalid Wasm binary header');
  }

  final reader = _WasmReader(bytes, 8);
  while (!reader.isDone) {
    final sectionId = reader.readByte();
    final sectionLen = reader.readU32Leb();
    if (reader.offset + sectionLen > bytes.length) {
      throw const FormatException('Truncated Wasm section');
    }
    final sectionEnd = reader.offset + sectionLen;
    if (sectionId == 2) {
      final importCount = reader.readU32Leb();
      if (importCount > 0) {
        throw const FormatException('Wasm host/WASI imports are denied');
      }
    } else if (sectionId == 5) {
      final memCount = reader.readU32Leb();
      if (memCount > 1) {
        throw const FormatException('Wasm multiple memories denied');
      }
      for (var i = 0; i < memCount; i++) {
        final flags = reader.readU32Leb();
        if (flags != 0 && flags != 1) {
          throw const FormatException('Wasm shared or memory64 denied');
        }
        final initialPages = reader.readU32Leb();
        final maxPages = flags == 1 ? reader.readU32Leb() : 512;
        if (initialPages > 512 || initialPages > maxPages) {
          throw const FormatException('Wasm memory exceeds 32 MiB limit');
        }
      }
    }
    reader.offset = sectionEnd;
  }
}

/// Builds a minimal valid zero-import `wasm32` guest module exporting `memory`,
/// `<prefix>_alloc`, and `<prefix>_invoke` that returns [responseJson] as UTF-8.
Uint8List buildMinimalVibeWasmModule(
  Map<String, Object?> responseJson, {
  String prefix = 'vibe',
}) {
  final responseBytes = utf8.encode(jsonEncode(responseJson));
  List<int> uLeb(BigInt val) {
    final out = <int>[];
    var v = val;
    while (true) {
      final b = (v & BigInt.from(0x7f)).toInt();
      v >>= 7;
      if (v == BigInt.zero) {
        out.add(b);
        return out;
      }
      out.add(b | 0x80);
    }
  }

  List<int> sLeb64(BigInt val) {
    final out = <int>[];
    var v = val;
    while (true) {
      final b = (v & BigInt.from(0x7f)).toInt();
      v >>= 7;
      final signBit = (b & 0x40) != 0;
      if ((v == BigInt.zero && !signBit) || (v == BigInt.from(-1) && signBit)) {
        out.add(b);
        return out;
      }
      out.add(b | 0x80);
    }
  }

  List<int> encStr(String s) {
    final b = utf8.encode(s);
    return <int>[...uLeb(BigInt.from(b.length)), ...b];
  }

  List<int> sec(int id, List<int> body) =>
      <int>[id, ...uLeb(BigInt.from(body.length)), ...body];

  const dataOffset = 64;
  const allocOffset = 1024;
  final packed =
      (BigInt.from(responseBytes.length) << 32) | BigInt.from(dataOffset);
  final allocBody = <int>[
    0x00,
    0x41,
    ...sLeb64(BigInt.from(allocOffset)),
    0x0b
  ];
  final invokeBody = <int>[0x00, 0x42, ...sLeb64(packed), 0x0b];

  return Uint8List.fromList(<int>[
    0x00,
    0x61,
    0x73,
    0x6d,
    0x01,
    0x00,
    0x00,
    0x00,
    ...sec(1, <int>[
      0x02,
      0x60,
      0x01,
      0x7f,
      0x01,
      0x7f,
      0x60,
      0x02,
      0x7f,
      0x7f,
      0x01,
      0x7e,
    ]),
    ...sec(3, <int>[0x02, 0x00, 0x01]),
    ...sec(5, <int>[0x01, 0x00, 0x01]),
    ...sec(7, <int>[
      0x03,
      ...encStr('memory'),
      0x02,
      0x00,
      ...encStr('${prefix}_alloc'),
      0x00,
      0x00,
      ...encStr('${prefix}_invoke'),
      0x00,
      0x01,
    ]),
    ...sec(10, <int>[
      0x02,
      ...uLeb(BigInt.from(allocBody.length)),
      ...allocBody,
      ...uLeb(BigInt.from(invokeBody.length)),
      ...invokeBody,
    ]),
    ...sec(11, <int>[
      0x01,
      0x00,
      0x41,
      ...sLeb64(BigInt.from(dataOffset)),
      0x0b,
      ...uLeb(BigInt.from(responseBytes.length)),
      ...responseBytes,
    ]),
  ]);
}

/// Evaluates zero-import `wasm32` Vibe-Space guests using the `vibe_alloc` /
/// `vibe_invoke` ABI (or a host-supplied [customRunner]).
class VibeWasmEvaluator {
  const VibeWasmEvaluator._();

  /// Executes [wasmBytes] and returns the raw decoded JSON object from linear memory.
  static FutureOr<Map<String, Object?>> evaluateRaw(
    Uint8List wasmBytes,
    Map<String, Object?> input, {
    FutureOr<Map<String, Object?>> Function(
      Uint8List wasmBytes,
      Map<String, Object?> input,
    )? customRunner,
  }) {
    validateVibeWasmBytes(wasmBytes);
    if (customRunner != null) {
      return customRunner(wasmBytes, input);
    }
    return _interpretWasmGuest(wasmBytes, input);
  }

  /// Executes [wasmBytes] and adapts any returned `view` / `a2ui` / `markdown`
  /// (or preserves `setData` patches for WeChat Mini Program Wasm guests).
  static FutureOr<Map<String, Object?>> evaluate(
    Uint8List wasmBytes,
    Map<String, Object?> input, {
    FutureOr<Map<String, Object?>> Function(
      Uint8List wasmBytes,
      Map<String, Object?> input,
    )? customRunner,
    Map<String, Object?>? dataModel,
  }) {
    final res = evaluateRaw(wasmBytes, input, customRunner: customRunner);
    if (res is Future<Map<String, Object?>>) {
      return res.then((out) => _normalizeWasmOutput(out, dataModel));
    }
    return _normalizeWasmOutput(res, dataModel);
  }

  static Map<String, Object?> _normalizeWasmOutput(
    Map<String, Object?> raw,
    Map<String, Object?>? dataModel,
  ) {
    final setData = raw['setData'] is Map
        ? (raw['setData'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : null;
    final hasExplicitView = raw.containsKey('view') ||
        raw.containsKey('a2ui') ||
        raw.containsKey('markdown') ||
        raw.containsKey('type');
    if (!hasExplicitView && setData != null) {
      return <String, Object?>{
        'state': raw['state'],
        'setData': setData,
        'view': null,
      };
    }
    final Object? viewCandidate =
        raw['view'] ?? raw['a2ui'] ?? raw['markdown'] ?? raw;
    final adapted = VibeUiCompatibilityAdapter.adapt(
      viewCandidate,
      dataModel: dataModel,
    );
    return <String, Object?>{
      'state': raw['state'],
      if (setData != null) 'setData': setData,
      'view': adapted,
    };
  }

  static Map<String, Object?> _interpretWasmGuest(
    Uint8List bytes,
    Map<String, Object?> input,
  ) {
    final types = <({int params, int results})>[];
    final funcTypeIndices = <int>[];
    final globals = <BigInt>[];
    final exports = <String, ({int kind, int index})>{};
    final codes = <({List<int> locals, Uint8List expr})>[];
    var initialPages = 1;

    final reader = _WasmReader(bytes, 8);
    final dataSegments = <({int offset, Uint8List data})>[];

    while (!reader.isDone) {
      final id = reader.readByte();
      final len = reader.readU32Leb();
      final end = reader.offset + len;
      switch (id) {
        case 1:
          final count = reader.readU32Leb();
          for (var i = 0; i < count; i++) {
            if (reader.readByte() != 0x60) {
              throw const FormatException('Unsupported Wasm func type');
            }
            final pCount = reader.readU32Leb();
            reader.offset += pCount;
            final rCount = reader.readU32Leb();
            reader.offset += rCount;
            types.add((params: pCount, results: rCount));
          }
        case 3:
          final count = reader.readU32Leb();
          for (var i = 0; i < count; i++) {
            funcTypeIndices.add(reader.readU32Leb());
          }
        case 5:
          final count = reader.readU32Leb();
          if (count >= 1) {
            final flags = reader.readU32Leb();
            initialPages = max(1, reader.readU32Leb());
            if (flags == 1) reader.readU32Leb();
          }
        case 6:
          final count = reader.readU32Leb();
          for (var i = 0; i < count; i++) {
            reader.offset += 2;
            globals.add(_evalConstExpr(reader));
          }
        case 7:
          final count = reader.readU32Leb();
          for (var i = 0; i < count; i++) {
            final name = reader.readUtf8();
            final kind = reader.readByte();
            final idx = reader.readU32Leb();
            exports[name] = (kind: kind, index: idx);
          }
        case 10:
          final count = reader.readU32Leb();
          for (var i = 0; i < count; i++) {
            final bodySize = reader.readU32Leb();
            final bodyEnd = reader.offset + bodySize;
            final localDeclCount = reader.readU32Leb();
            final locals = <int>[];
            for (var j = 0; j < localDeclCount; j++) {
              final n = reader.readU32Leb();
              final t = reader.readByte();
              for (var k = 0; k < n; k++) {
                locals.add(t);
              }
            }
            final expr = bytes.sublist(reader.offset, bodyEnd);
            codes.add((locals: locals, expr: expr));
            reader.offset = bodyEnd;
          }
        case 11:
          final count = reader.readU32Leb();
          for (var i = 0; i < count; i++) {
            final mode = reader.readU32Leb();
            if (mode == 0) {
              final off = _evalConstExpr(reader).toInt();
              final dLen = reader.readU32Leb();
              dataSegments.add((
                offset: off,
                data: bytes.sublist(reader.offset, reader.offset + dLen),
              ));
              reader.offset += dLen;
            } else {
              break;
            }
          }
      }
      reader.offset = end;
    }

    final memExp = exports['memory'];
    final allocExp = exports['vibe_alloc'] ??
        exports['leap_alloc'] ??
        exports['leapterm_alloc'] ??
        exports['omni_alloc'];
    final invokeExp = exports['vibe_invoke'] ??
        exports['leap_invoke'] ??
        exports['leapterm_invoke'] ??
        exports['omni_invoke'];
    if (memExp == null ||
        memExp.kind != 2 ||
        allocExp == null ||
        allocExp.kind != 0 ||
        invokeExp == null ||
        invokeExp.kind != 0) {
      throw const FormatException(
        'Wasm module must export memory, vibe_alloc, and vibe_invoke',
      );
    }

    final memory = Uint8List(initialPages * 65536);
    for (final seg in dataSegments) {
      if (seg.offset < 0 || seg.offset + seg.data.length > memory.length) {
        throw const FormatException('Wasm data segment out of bounds');
      }
      memory.setRange(seg.offset, seg.offset + seg.data.length, seg.data);
    }

    var fuel = kMaxVibeWasmFuel;
    BigInt callFunc(int fnIdx, List<BigInt> args) {
      final type = types[funcTypeIndices[fnIdx]];
      final code = codes[fnIdx];
      final locals = <BigInt>[
        ...args,
        for (var i = 0; i < code.locals.length; i++) BigInt.zero,
      ];
      final stack = <BigInt>[];
      final r = _WasmReader(code.expr, 0);
      final memData = ByteData.sublistView(memory);

      while (!r.isDone) {
        if (--fuel <= 0) {
          throw const FormatException('Wasm execution step budget exceeded');
        }
        final op = r.readByte();
        switch (op) {
          case 0x01:
            break;
          case 0x0b:
            if (r.isDone) {
              return type.results > 0 && stack.isNotEmpty
                  ? stack.removeLast()
                  : BigInt.zero;
            }
          case 0x0f:
            return type.results > 0 && stack.isNotEmpty
                ? stack.removeLast()
                : BigInt.zero;
          case 0x10:
            final callee = r.readU32Leb();
            final cType = types[funcTypeIndices[callee]];
            final cArgs = List<BigInt>.filled(cType.params, BigInt.zero);
            for (var i = cType.params - 1; i >= 0; i--) {
              cArgs[i] = stack.removeLast();
            }
            final res = callFunc(callee, cArgs);
            if (cType.results > 0) stack.add(res);
          case 0x1a:
            stack.removeLast();
          case 0x20:
            stack.add(locals[r.readU32Leb()]);
          case 0x21:
            locals[r.readU32Leb()] = stack.removeLast();
          case 0x22:
            locals[r.readU32Leb()] = stack.last;
          case 0x23:
            stack.add(globals[r.readU32Leb()]);
          case 0x24:
            globals[r.readU32Leb()] = stack.removeLast();
          case 0x28:
            r.readU32Leb();
            final addr =
                stack.removeLast().toUnsigned(32).toInt() + r.readU32Leb();
            stack.add(BigInt.from(memData.getUint32(addr, Endian.little)));
          case 0x2d:
            r.readU32Leb();
            final addr =
                stack.removeLast().toUnsigned(32).toInt() + r.readU32Leb();
            stack.add(BigInt.from(memory[addr]));
          case 0x36:
            r.readU32Leb();
            final off = r.readU32Leb();
            final val = stack.removeLast().toUnsigned(32).toInt();
            final addr = stack.removeLast().toUnsigned(32).toInt() + off;
            memData.setUint32(addr, val, Endian.little);
          case 0x3a:
            r.readU32Leb();
            final off = r.readU32Leb();
            final val = stack.removeLast().toUnsigned(8).toInt();
            final addr = stack.removeLast().toUnsigned(32).toInt() + off;
            memory[addr] = val;
          case 0x41:
            stack.add(BigInt.from(r.readS32Leb()).toUnsigned(32));
          case 0x42:
            stack.add(r.readS64Leb().toUnsigned(64));
          case 0x6a:
            final b = stack.removeLast(), a = stack.removeLast();
            stack.add((a + b).toUnsigned(32));
          case 0x6b:
            final b = stack.removeLast(), a = stack.removeLast();
            stack.add((a - b).toUnsigned(32));
          case 0x6c:
            final b = stack.removeLast(), a = stack.removeLast();
            stack.add((a * b).toUnsigned(32));
          case 0x71:
            final b = stack.removeLast(), a = stack.removeLast();
            stack.add((a & b).toUnsigned(32));
          case 0x72:
            final b = stack.removeLast(), a = stack.removeLast();
            stack.add((a | b).toUnsigned(32));
          case 0x7c:
            final b = stack.removeLast(), a = stack.removeLast();
            stack.add((a + b).toUnsigned(64));
          case 0x84:
            final b = stack.removeLast(), a = stack.removeLast();
            stack.add((a | b).toUnsigned(64));
          case 0x86:
            final b = stack.removeLast(), a = stack.removeLast();
            stack.add((a << (b.toInt() & 63)).toUnsigned(64));
          case 0xad:
            stack.add(stack.removeLast().toUnsigned(32));
          default:
            throw FormatException(
              'Unsupported Wasm opcode 0x${op.toRadixString(16)} in native fallback',
            );
        }
      }
      return type.results > 0 && stack.isNotEmpty
          ? stack.removeLast()
          : BigInt.zero;
    }

    final reqBytes = utf8.encode(jsonEncode(input));
    final ptr = callFunc(
      allocExp.index,
      <BigInt>[BigInt.from(reqBytes.length)],
    ).toSigned(32).toInt();
    if (ptr < 0 || ptr + reqBytes.length > memory.length) {
      throw const FormatException('Wasm alloc returned out-of-bounds pointer');
    }
    memory.setRange(ptr, ptr + reqBytes.length, reqBytes);

    final packed = callFunc(
      invokeExp.index,
      <BigInt>[BigInt.from(ptr), BigInt.from(reqBytes.length)],
    ).toUnsigned(64);
    final outOffset = (packed & BigInt.from(0xffffffff)).toInt();
    final outLength = (packed >> 32).toInt();
    if (outOffset < 0 ||
        outLength < 0 ||
        outLength > 1048576 ||
        outOffset + outLength > memory.length) {
      throw const FormatException('Wasm invoke returned out-of-bounds slice');
    }
    final decoded = jsonDecode(
      utf8.decode(memory.sublist(outOffset, outOffset + outLength)),
    );
    if (decoded is! Map) {
      throw const FormatException('Wasm output must be a JSON object');
    }
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  }

  static BigInt _evalConstExpr(_WasmReader r) {
    BigInt val = BigInt.zero;
    while (!r.isDone) {
      final op = r.readByte();
      if (op == 0x0b) break;
      if (op == 0x41) {
        val = BigInt.from(r.readS32Leb());
      } else if (op == 0x42) {
        val = r.readS64Leb();
      } else {
        throw const FormatException('Unsupported Wasm const init opcode');
      }
    }
    return val;
  }
}

class _WasmReader {
  _WasmReader(this.bytes, this.offset);

  final Uint8List bytes;
  int offset;

  bool get isDone => offset >= bytes.length;

  int readByte() {
    if (offset >= bytes.length) {
      throw const FormatException('Unexpected EOF in Wasm binary');
    }
    return bytes[offset++];
  }

  int readU32Leb() {
    var result = 0;
    var shift = 0;
    for (var i = 0; i < 5; i++) {
      final b = readByte();
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) return result >>> 0;
      shift += 7;
    }
    throw const FormatException('Invalid ULEB128 integer');
  }

  int readS32Leb() {
    var result = 0;
    var shift = 0;
    int b;
    var count = 0;
    do {
      if (++count > 5) throw const FormatException('Invalid SLEB128 i32');
      b = readByte();
      result |= (b & 0x7f) << shift;
      shift += 7;
    } while ((b & 0x80) != 0);
    if (shift < 32 && (b & 0x40) != 0) {
      result |= (~0 << shift);
    }
    return result;
  }

  BigInt readS64Leb() {
    var result = BigInt.zero;
    var shift = 0;
    int b;
    var count = 0;
    do {
      if (++count > 10) throw const FormatException('Invalid SLEB128 i64');
      b = readByte();
      result |= BigInt.from(b & 0x7f) << shift;
      shift += 7;
    } while ((b & 0x80) != 0);
    if (shift < 64 && (b & 0x40) != 0) {
      result |= (BigInt.from(-1) << shift);
    }
    return result;
  }

  String readUtf8() {
    final len = readU32Leb();
    if (offset + len > bytes.length) {
      throw const FormatException('Truncated UTF-8 string in Wasm');
    }
    final str = utf8.decode(bytes.sublist(offset, offset + len));
    offset += len;
    return str;
  }
}
