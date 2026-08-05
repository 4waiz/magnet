/// Loads Blender-authored GLB files into CPU-side [MeshTemplate]s.
///
/// Why this exists: `flutter_scene` imports GLB straight onto the GPU, which
/// is right for static scenery but useless for the swarm — the swarm is one
/// merged mesh rebuilt every frame from CPU vertex data, so it needs the
/// triangles in Dart. Without this, the swarm could only stamp shapes that
/// were hand-coded in Dart, which is exactly how it ended up as a hundred
/// identical cubes.
///
/// Scope is deliberately narrow: triangle primitives with float POSITION,
/// non-sparse accessors, and no Draco compression — i.e. what
/// `art/blender/*.py` actually exports. Anything else throws with a clear
/// message rather than silently producing wrong geometry.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:vector_math/vector_math.dart';

import 'mesh_template.dart';

const int _kGlbMagic = 0x46546C67; // 'glTF'
const int _kChunkJson = 0x4E4F534A; // 'JSON'
const int _kChunkBin = 0x004E4942; // 'BIN\0'

const int _compUnsignedByte = 5121;
const int _compUnsignedShort = 5123;
const int _compUnsignedInt = 5125;
const int _compFloat = 5126;

class GlbParseException implements Exception {
  GlbParseException(this.message);
  final String message;
  @override
  String toString() => 'GlbParseException: $message';
}

/// One primitive's worth of geometry, already in world space.
class _Primitive {
  _Primitive(this.positions, this.indices, this.baseColor);
  final Float32List positions;
  final List<int> indices;
  final Vector4 baseColor;
}

class GlbTemplateLoader {
  GlbTemplateLoader._();

  static final Map<String, MeshTemplate> _cache = {};

  /// Loads [assetPath] and merges every primitive into one template.
  ///
  /// Per-vertex colours are baked from each primitive's material
  /// `baseColorFactor`, so a multi-material Blender mesh survives the merge
  /// into a single batched draw.
  static Future<MeshTemplate> load(String assetPath) async {
    final hit = _cache[assetPath];
    if (hit != null) return hit;
    final data = await rootBundle.load(assetPath);
    final template = parse(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      name: assetPath,
    );
    _cache[assetPath] = template;
    return template;
  }

  /// Loads several assets concurrently.
  static Future<Map<String, MeshTemplate>> loadAll(
    Iterable<String> assetPaths,
  ) async {
    final paths = assetPaths.toList();
    final loaded = await Future.wait(paths.map(load));
    return {for (var i = 0; i < paths.length; i++) paths[i]: loaded[i]};
  }

  static void clearCache() => _cache.clear();

  /// Parses GLB bytes. Exposed for tests so they need no asset bundle.
  static MeshTemplate parse(Uint8List bytes, {String name = ''}) {
    final bd = ByteData.sublistView(bytes);
    if (bytes.length < 12) {
      throw GlbParseException('$name: too short to be a GLB');
    }
    if (bd.getUint32(0, Endian.little) != _kGlbMagic) {
      throw GlbParseException('$name: not a GLB (bad magic)');
    }

    Map<String, dynamic>? json;
    Uint8List? bin;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final len = bd.getUint32(offset, Endian.little);
      final type = bd.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      if (start + len > bytes.length) break;
      if (type == _kChunkJson) {
        json =
            jsonDecode(utf8.decode(bytes.sublist(start, start + len)))
                as Map<String, dynamic>;
      } else if (type == _kChunkBin) {
        bin = Uint8List.sublistView(bytes, start, start + len);
      }
      offset = start + len + ((4 - (len % 4)) % 4);
    }

    if (json == null) throw GlbParseException('$name: no JSON chunk');
    if (bin == null) throw GlbParseException('$name: no BIN chunk');

    final prims = <_Primitive>[];
    _walkNodes(json, bin, prims, name);
    if (prims.isEmpty) {
      throw GlbParseException('$name: no triangle primitives found');
    }

    return _merge(prims, name);
  }

  // -------------------------------------------------------------------------
  // Scene graph
  // -------------------------------------------------------------------------

  static void _walkNodes(
    Map<String, dynamic> json,
    Uint8List bin,
    List<_Primitive> out,
    String name,
  ) {
    final nodes = (json['nodes'] as List?) ?? const [];
    final scenes = (json['scenes'] as List?) ?? const [];
    final sceneIndex = (json['scene'] as int?) ?? 0;

    final roots = <int>[];
    if (scenes.isNotEmpty && sceneIndex < scenes.length) {
      final s = scenes[sceneIndex] as Map<String, dynamic>;
      roots.addAll(((s['nodes'] as List?) ?? const []).cast<int>());
    } else {
      for (var i = 0; i < nodes.length; i++) {
        roots.add(i);
      }
    }

    void visit(int index, Matrix4 parent) {
      if (index < 0 || index >= nodes.length) return;
      final node = nodes[index] as Map<String, dynamic>;
      final world = parent.multiplied(_nodeMatrix(node));
      final meshIndex = node['mesh'] as int?;
      if (meshIndex != null) {
        _readMesh(json, bin, meshIndex, world, out, name);
      }
      for (final child
          in ((node['children'] as List?) ?? const []).cast<int>()) {
        visit(child, world);
      }
    }

    for (final r in roots) {
      visit(r, Matrix4.identity());
    }
  }

  static Matrix4 _nodeMatrix(Map<String, dynamic> node) {
    final m = node['matrix'] as List?;
    if (m != null && m.length == 16) {
      // glTF matrices are column-major, which is what Matrix4.fromList wants.
      return Matrix4.fromList(m.cast<num>().map((e) => e.toDouble()).toList());
    }
    final out = Matrix4.identity();
    final t = node['translation'] as List?;
    final r = node['rotation'] as List?;
    final s = node['scale'] as List?;
    if (t != null && t.length == 3) {
      out.setTranslation(
        Vector3(
          (t[0] as num).toDouble(),
          (t[1] as num).toDouble(),
          (t[2] as num).toDouble(),
        ),
      );
    }
    if (r != null && r.length == 4) {
      final q = Quaternion(
        (r[0] as num).toDouble(),
        (r[1] as num).toDouble(),
        (r[2] as num).toDouble(),
        (r[3] as num).toDouble(),
      );
      out.setRotation(q.asRotationMatrix());
      if (t != null && t.length == 3) {
        out.setTranslation(
          Vector3(
            (t[0] as num).toDouble(),
            (t[1] as num).toDouble(),
            (t[2] as num).toDouble(),
          ),
        );
      }
    }
    if (s != null && s.length == 3) {
      out.scaleByVector3(
        Vector3(
          (s[0] as num).toDouble(),
          (s[1] as num).toDouble(),
          (s[2] as num).toDouble(),
        ),
      );
    }
    return out;
  }

  static void _readMesh(
    Map<String, dynamic> json,
    Uint8List bin,
    int meshIndex,
    Matrix4 world,
    List<_Primitive> out,
    String name,
  ) {
    final meshes = (json['meshes'] as List?) ?? const [];
    if (meshIndex >= meshes.length) return;
    final mesh = meshes[meshIndex] as Map<String, dynamic>;

    for (final rawPrim in ((mesh['primitives'] as List?) ?? const [])) {
      final prim = rawPrim as Map<String, dynamic>;
      // mode 4 == TRIANGLES; absent means 4.
      final mode = (prim['mode'] as int?) ?? 4;
      if (mode != 4) continue;
      if (prim.containsKey('extensions') &&
          (prim['extensions'] as Map).containsKey(
            'KHR_draco_mesh_compression',
          )) {
        throw GlbParseException(
          '$name: Draco-compressed primitive; re-export without Draco',
        );
      }

      final attrs = prim['attributes'] as Map<String, dynamic>;
      final posIndex = attrs['POSITION'] as int?;
      if (posIndex == null) continue;

      final rawPos = _readAccessorFloats(json, bin, posIndex, 3, name);
      final count = rawPos.length ~/ 3;

      // Bake the node transform in — the batcher works in template space.
      final positions = Float32List(rawPos.length);
      final v = Vector3.zero();
      for (var i = 0; i < count; i++) {
        v.setValues(rawPos[i * 3], rawPos[i * 3 + 1], rawPos[i * 3 + 2]);
        world.transform3(v);
        positions[i * 3] = v.x;
        positions[i * 3 + 1] = v.y;
        positions[i * 3 + 2] = v.z;
      }

      List<int> indices;
      final idxAccessor = prim['indices'] as int?;
      if (idxAccessor != null) {
        indices = _readAccessorInts(json, bin, idxAccessor, name);
      } else {
        indices = List<int>.generate(count, (i) => i);
      }

      out.add(
        _Primitive(
          positions,
          indices,
          _materialColor(json, prim['material'] as int?),
        ),
      );
    }
  }

  static Vector4 _materialColor(Map<String, dynamic> json, int? index) {
    if (index == null) return Vector4(1, 1, 1, 1);
    final materials = (json['materials'] as List?) ?? const [];
    if (index >= materials.length) return Vector4(1, 1, 1, 1);
    final mat = materials[index] as Map<String, dynamic>;
    final pbr = mat['pbrMetallicRoughness'] as Map<String, dynamic>?;
    final f = pbr?['baseColorFactor'] as List?;
    if (f == null || f.length < 4) return Vector4(1, 1, 1, 1);
    return Vector4(
      (f[0] as num).toDouble(),
      (f[1] as num).toDouble(),
      (f[2] as num).toDouble(),
      (f[3] as num).toDouble(),
    );
  }

  // -------------------------------------------------------------------------
  // Accessors
  // -------------------------------------------------------------------------

  static Map<String, dynamic> _accessor(
    Map<String, dynamic> json,
    int index,
    String name,
  ) {
    final accessors = (json['accessors'] as List?) ?? const [];
    if (index >= accessors.length) {
      throw GlbParseException('$name: accessor $index out of range');
    }
    final a = accessors[index] as Map<String, dynamic>;
    if (a.containsKey('sparse')) {
      throw GlbParseException('$name: sparse accessors are not supported');
    }
    return a;
  }

  /// Resolves an accessor to (ByteData view, element stride, count).
  static (ByteData, int, int, int) _view(
    Map<String, dynamic> json,
    Uint8List bin,
    Map<String, dynamic> accessor,
    int componentBytes,
    int components,
    String name,
  ) {
    final count = accessor['count'] as int;
    final accessorOffset = (accessor['byteOffset'] as int?) ?? 0;
    final bvIndex = accessor['bufferView'] as int?;
    if (bvIndex == null) {
      throw GlbParseException('$name: accessor without bufferView');
    }
    final views = (json['bufferViews'] as List?) ?? const [];
    final bv = views[bvIndex] as Map<String, dynamic>;
    final bvOffset = (bv['byteOffset'] as int?) ?? 0;
    final stride = (bv['byteStride'] as int?) ?? (componentBytes * components);
    final base = bvOffset + accessorOffset;
    return (ByteData.sublistView(bin), stride, count, base);
  }

  static Float32List _readAccessorFloats(
    Map<String, dynamic> json,
    Uint8List bin,
    int index,
    int components,
    String name,
  ) {
    final a = _accessor(json, index, name);
    if (a['componentType'] != _compFloat) {
      throw GlbParseException(
        '$name: expected float accessor, got ${a['componentType']}',
      );
    }
    final (bd, stride, count, base) = _view(json, bin, a, 4, components, name);
    final out = Float32List(count * components);
    for (var i = 0; i < count; i++) {
      final o = base + i * stride;
      for (var c = 0; c < components; c++) {
        out[i * components + c] = bd.getFloat32(o + c * 4, Endian.little);
      }
    }
    return out;
  }

  static List<int> _readAccessorInts(
    Map<String, dynamic> json,
    Uint8List bin,
    int index,
    String name,
  ) {
    final a = _accessor(json, index, name);
    final ct = a['componentType'] as int;
    final bytes = switch (ct) {
      _compUnsignedByte => 1,
      _compUnsignedShort => 2,
      _compUnsignedInt => 4,
      _ => throw GlbParseException('$name: bad index componentType $ct'),
    };
    final (bd, stride, count, base) = _view(json, bin, a, bytes, 1, name);
    final out = List<int>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      final o = base + i * stride;
      out[i] = switch (bytes) {
        1 => bd.getUint8(o),
        2 => bd.getUint16(o, Endian.little),
        _ => bd.getUint32(o, Endian.little),
      };
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Merge
  // -------------------------------------------------------------------------

  static MeshTemplate _merge(List<_Primitive> prims, String name) {
    var totalVerts = 0;
    var totalIndices = 0;
    for (final p in prims) {
      totalVerts += p.positions.length ~/ 3;
      totalIndices += p.indices.length;
    }
    if (totalIndices > 0xFFFF) {
      throw GlbParseException(
        '$name: ${totalIndices ~/ 3} triangles exceeds the 16-bit index '
        'budget for batched geometry; split the asset',
      );
    }

    final positions = Float32List(totalVerts * 3);
    final colors = Float32List(totalVerts * 4);
    final indices = Uint16List(totalIndices);

    var vOff = 0, iOff = 0;
    for (final p in prims) {
      final n = p.positions.length ~/ 3;
      positions.setRange(vOff * 3, vOff * 3 + n * 3, p.positions);
      for (var i = 0; i < n; i++) {
        final c = (vOff + i) * 4;
        colors[c] = p.baseColor.x;
        colors[c + 1] = p.baseColor.y;
        colors[c + 2] = p.baseColor.z;
        colors[c + 3] = p.baseColor.w;
      }
      for (var i = 0; i < p.indices.length; i++) {
        indices[iOff + i] = vOff + p.indices[i];
      }
      vOff += n;
      iOff += p.indices.length;
    }

    // Recompute flat normals from the merged soup; Blender's exported normals
    // are per-vertex and the faceted look wants per-face.
    return MeshTemplate.fromTriangleSoup(
      positions,
      indices,
      colors: colors,
      name: name,
    );
  }
}
