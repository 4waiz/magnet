/// The swarm/effects renderer: accumulates transformed copies of
/// [MeshTemplate]s into a single vertex buffer and uploads it to one
/// [MeshGeometry] per frame.
///
/// This is what keeps hundreds of orbiting metal pieces, particles and debris
/// fragments at a handful of draw calls with no rigid bodies: every piece is
/// just a few dozen vertices stamped through a matrix.
///
/// `InstancedMesh` in flutter_scene 0.16.0 does not help here — its own
/// documentation says the naive backend still issues one draw call per
/// instance. See `docs/renderer_decision.md`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'mesh_template.dart';

/// Unlit *and* alpha-blended, for glow geometry.
///
/// `UnlitMaterial` does not override `isOpaque()`, so stock unlit geometry is
/// always drawn in the opaque pass and its alpha is ignored. Overriding it
/// moves these draws into the depth-sorted translucent pass, which is what
/// makes trails, shockwaves and sparks read as light rather than as solid
/// plastic.
class GlowMaterial extends UnlitMaterial {
  GlowMaterial() {
    baseColorFactor = Vector4(1, 1, 1, 1);
    vertexColorWeight = 1.0;
  }

  @override
  bool isOpaque() => false;
}

class MeshBatcher {
  MeshBatcher({
    required this.maxVertices,
    required this.maxIndices,
    required this.material,
    required this.name,
  }) : _pos = Float32List(maxVertices * 3),
       _nrm = Float32List(maxVertices * 3),
       _col = Float32List(maxVertices * 4),
       _idx = Uint16List(maxIndices);

  final int maxVertices;
  final int maxIndices;
  final Material material;
  final String name;

  final Float32List _pos;
  final Float32List _nrm;
  final Float32List _col;
  final Uint16List _idx;

  int _vertCount = 0;
  int _idxCount = 0;
  int _dropped = 0;

  int get vertexCount => _vertCount;
  int get triangleCount => _idxCount ~/ 3;

  /// Instances rejected this frame because the batch was full. Non-zero means
  /// the caller's cap is above capacity — surfaced in the debug overlay
  /// rather than silently swallowed.
  int get droppedThisFrame => _dropped;

  MeshGeometry? _geometry;
  Node? _node;

  bool get hasNode => _node != null;

  void begin() {
    _vertCount = 0;
    _idxCount = 0;
    _dropped = 0;
  }

  /// Stamps [t] transformed by [m] into the batch.
  ///
  /// When [t] carries baked material colours they are multiplied by [tint];
  /// otherwise [tint] is used directly. Set [useTemplateColors] false to
  /// override a template's own colours entirely (particles do this).
  void add(
    MeshTemplate t,
    Matrix4 m,
    Vector4 tint, {
    bool useTemplateColors = true,
  }) {
    final vc = t.vertexCount;
    if (_vertCount + vc > maxVertices ||
        _idxCount + t.indices.length > maxIndices) {
      _dropped++;
      return;
    }

    final s = m.storage;
    final base = _vertCount;
    final src = useTemplateColors ? t.colors : null;

    for (var i = 0; i < vc; i++) {
      final px = t.positions[i * 3];
      final py = t.positions[i * 3 + 1];
      final pz = t.positions[i * 3 + 2];
      final o = (base + i) * 3;
      _pos[o] = s[0] * px + s[4] * py + s[8] * pz + s[12];
      _pos[o + 1] = s[1] * px + s[5] * py + s[9] * pz + s[13];
      _pos[o + 2] = s[2] * px + s[6] * py + s[10] * pz + s[14];

      final nx = t.normals[i * 3];
      final ny = t.normals[i * 3 + 1];
      final nz = t.normals[i * 3 + 2];
      var wx = s[0] * nx + s[4] * ny + s[8] * nz;
      var wy = s[1] * nx + s[5] * ny + s[9] * nz;
      var wz = s[2] * nx + s[6] * ny + s[10] * nz;
      final len = math.sqrt(wx * wx + wy * wy + wz * wz);
      if (len > 1e-6) {
        wx /= len;
        wy /= len;
        wz /= len;
      }
      _nrm[o] = wx;
      _nrm[o + 1] = wy;
      _nrm[o + 2] = wz;

      final c = (base + i) * 4;
      if (src != null) {
        _col[c] = src[i * 4] * tint.x;
        _col[c + 1] = src[i * 4 + 1] * tint.y;
        _col[c + 2] = src[i * 4 + 2] * tint.z;
        _col[c + 3] = src[i * 4 + 3] * tint.w;
      } else {
        _col[c] = tint.x;
        _col[c + 1] = tint.y;
        _col[c + 2] = tint.z;
        _col[c + 3] = tint.w;
      }
    }

    for (var i = 0; i < t.indices.length; i++) {
      _idx[_idxCount + i] = base + t.indices[i];
    }
    _vertCount += vc;
    _idxCount += t.indices.length;
  }

  /// Uploads the accumulated batch. Allocates GPU buffers once; subsequent
  /// frames reuse them via [MeshGeometry.rebuild].
  void flush(SceneGraph parent) {
    if (_idxCount == 0) {
      _node?.visible = false;
      return;
    }
    final positions = Float32List.sublistView(_pos, 0, _vertCount * 3);
    final normals = Float32List.sublistView(_nrm, 0, _vertCount * 3);
    final colors = Float32List.sublistView(_col, 0, _vertCount * 4);
    final indices = Uint16List.sublistView(_idx, 0, _idxCount);

    final existing = _geometry;
    if (existing == null) {
      final g = MeshGeometry.fromArrays(
        positions: positions,
        normals: normals,
        colors: colors,
        indices: indices,
        storage: GeometryStorage.updatable,
      );
      _geometry = g;
      _node = Node(name: name, mesh: Mesh(g, material));
      parent.add(_node!);
    } else {
      existing.rebuild(
        positions: positions,
        normals: normals,
        colors: colors,
        indices: indices,
      );
      _node!.visible = true;
    }
  }
}
