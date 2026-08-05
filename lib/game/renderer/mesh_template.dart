/// CPU-side low-poly meshes, kept in structure-of-arrays form so they can be
/// stamped into a batched vertex buffer without allocating per frame.
///
/// This is the unit the swarm batcher works in: every orbiting metal piece,
/// every particle and every piece of debris is one of these plus a transform.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

class MeshTemplate {
  MeshTemplate({
    required this.positions,
    required this.normals,
    required this.indices,
    this.colors,
    this.name = '',
  });

  /// 3 floats per vertex.
  final Float32List positions;

  /// 3 floats per vertex.
  final Float32List normals;

  final Uint16List indices;

  /// Optional 4 floats per vertex, baked from the source material's base
  /// colour. Lets one batch carry meshes of different colours.
  final Float32List? colors;

  final String name;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;

  /// Longest distance from the origin — used for culling and for scaling
  /// pieces into orbit slots.
  double get boundingRadius {
    var maxSq = 0.0;
    for (var i = 0; i < positions.length; i += 3) {
      final x = positions[i], y = positions[i + 1], z = positions[i + 2];
      final d = x * x + y * y + z * z;
      if (d > maxSq) maxSq = d;
    }
    return math.sqrt(maxSq);
  }

  /// Returns a copy scaled so [boundingRadius] equals [radius].
  MeshTemplate normalizedTo(double radius) {
    final r = boundingRadius;
    if (r < 1e-6) return this;
    final k = radius / r;
    final p = Float32List(positions.length);
    for (var i = 0; i < positions.length; i++) {
      p[i] = positions[i] * k;
    }
    return MeshTemplate(
      positions: p,
      normals: normals,
      indices: indices,
      colors: colors,
      name: name,
    );
  }

  /// A flat-shaded box. 24 verts / 36 indices — the faceted look the art
  /// direction asks for, and cheap enough to stamp hundreds of times.
  static MeshTemplate box(double hx, double hy, double hz, {String name = ''}) {
    final pos = <double>[];
    final nrm = <double>[];
    final idx = <int>[];

    void face(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector3 n) {
      final base = pos.length ~/ 3;
      for (final v in [a, b, c, d]) {
        pos.addAll([v.x, v.y, v.z]);
        nrm.addAll([n.x, n.y, n.z]);
      }
      idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    }

    final p = [
      Vector3(-hx, -hy, -hz),
      Vector3(hx, -hy, -hz),
      Vector3(hx, hy, -hz),
      Vector3(-hx, hy, -hz),
      Vector3(-hx, -hy, hz),
      Vector3(hx, -hy, hz),
      Vector3(hx, hy, hz),
      Vector3(-hx, hy, hz),
    ];
    face(p[4], p[5], p[6], p[7], Vector3(0, 0, 1));
    face(p[1], p[0], p[3], p[2], Vector3(0, 0, -1));
    face(p[5], p[1], p[2], p[6], Vector3(1, 0, 0));
    face(p[0], p[4], p[7], p[3], Vector3(-1, 0, 0));
    face(p[3], p[7], p[6], p[2], Vector3(0, 1, 0));
    face(p[0], p[1], p[5], p[4], Vector3(0, -1, 0));

    return MeshTemplate(
      positions: Float32List.fromList(pos),
      normals: Float32List.fromList(nrm),
      indices: Uint16List.fromList(idx),
      name: name,
    );
  }

  /// A flat-shaded prism with [sides] sides — bolts, rods, nuts, pipe pieces.
  static MeshTemplate prism(
    double radius,
    double halfHeight,
    int sides, {
    double taper = 1.0,
    String name = '',
  }) {
    final pos = <double>[];
    final nrm = <double>[];
    final idx = <int>[];

    void tri(Vector3 a, Vector3 b, Vector3 c) {
      final n = (b - a).cross(c - a);
      if (n.length2 > 1e-12) n.normalize();
      final base = pos.length ~/ 3;
      for (final v in [a, b, c]) {
        pos.addAll([v.x, v.y, v.z]);
        nrm.addAll([n.x, n.y, n.z]);
      }
      idx.addAll([base, base + 1, base + 2]);
    }

    Vector3 ring(int i, bool top) {
      final a = (i % sides) / sides * math.pi * 2;
      final r = radius * (top ? taper : 1.0);
      return Vector3(
        math.cos(a) * r,
        top ? halfHeight : -halfHeight,
        math.sin(a) * r,
      );
    }

    final topC = Vector3(0, halfHeight, 0);
    final botC = Vector3(0, -halfHeight, 0);
    for (var i = 0; i < sides; i++) {
      final b0 = ring(i, false), b1 = ring(i + 1, false);
      final t0 = ring(i, true), t1 = ring(i + 1, true);
      tri(b0, b1, t1);
      tri(b0, t1, t0);
      tri(t0, t1, topC);
      tri(b1, b0, botC);
    }
    return MeshTemplate(
      positions: Float32List.fromList(pos),
      normals: Float32List.fromList(nrm),
      indices: Uint16List.fromList(idx),
      name: name,
    );
  }

  /// A faceted (flat-shaded) icosphere.
  static MeshTemplate icosphere(
    double radius,
    int subdivisions, {
    String name = '',
  }) {
    final t = (1.0 + math.sqrt(5.0)) / 2.0;
    final verts = <Vector3>[
      Vector3(-1, t, 0),
      Vector3(1, t, 0),
      Vector3(-1, -t, 0),
      Vector3(1, -t, 0),
      Vector3(0, -1, t),
      Vector3(0, 1, t),
      Vector3(0, -1, -t),
      Vector3(0, 1, -t),
      Vector3(t, 0, -1),
      Vector3(t, 0, 1),
      Vector3(-t, 0, -1),
      Vector3(-t, 0, 1),
    ].map((v) => v.normalized()).toList();

    var faces = <List<int>>[
      [0, 11, 5],
      [0, 5, 1],
      [0, 1, 7],
      [0, 7, 10],
      [0, 10, 11],
      [1, 5, 9],
      [5, 11, 4],
      [11, 10, 2],
      [10, 7, 6],
      [7, 1, 8],
      [3, 9, 4],
      [3, 4, 2],
      [3, 2, 6],
      [3, 6, 8],
      [3, 8, 9],
      [4, 9, 5],
      [2, 4, 11],
      [6, 2, 10],
      [8, 6, 7],
      [9, 8, 1],
    ];

    for (var s = 0; s < subdivisions; s++) {
      final next = <List<int>>[];
      final cache = <String, int>{};
      int mid(int a, int b) {
        final key = a < b ? '$a-$b' : '$b-$a';
        final hit = cache[key];
        if (hit != null) return hit;
        verts.add((verts[a] + verts[b]).normalized());
        final id = verts.length - 1;
        cache[key] = id;
        return id;
      }

      for (final f in faces) {
        final a = mid(f[0], f[1]);
        final b = mid(f[1], f[2]);
        final c = mid(f[2], f[0]);
        next.addAll([
          [f[0], a, c],
          [f[1], b, a],
          [f[2], c, b],
          [a, b, c],
        ]);
      }
      faces = next;
    }

    // Unweld for flat shading — each triangle gets its own normal, which is
    // what gives the crystalline faceted read.
    return _fromTriangles(
      faces.map(
        (f) => [
          verts[f[0]] * radius,
          verts[f[1]] * radius,
          verts[f[2]] * radius,
        ],
      ),
      name,
    );
  }

  static MeshTemplate _fromTriangles(
    Iterable<List<Vector3>> tris,
    String name,
  ) {
    final list = tris.toList();
    final pos = Float32List(list.length * 9);
    final nrm = Float32List(list.length * 9);
    final idx = Uint16List(list.length * 3);
    for (var i = 0; i < list.length; i++) {
      final a = list[i][0], b = list[i][1], c = list[i][2];
      final n = (b - a).cross(c - a);
      if (n.length2 > 1e-12) n.normalize();
      final o = i * 9;
      pos[o] = a.x;
      pos[o + 1] = a.y;
      pos[o + 2] = a.z;
      pos[o + 3] = b.x;
      pos[o + 4] = b.y;
      pos[o + 5] = b.z;
      pos[o + 6] = c.x;
      pos[o + 7] = c.y;
      pos[o + 8] = c.z;
      for (var k = 0; k < 3; k++) {
        nrm[o + k * 3] = n.x;
        nrm[o + k * 3 + 1] = n.y;
        nrm[o + k * 3 + 2] = n.z;
      }
      idx[i * 3] = i * 3;
      idx[i * 3 + 1] = i * 3 + 1;
      idx[i * 3 + 2] = i * 3 + 2;
    }
    return MeshTemplate(positions: pos, normals: nrm, indices: idx, name: name);
  }

  /// Builds a template from raw triangle soup. Used by the GLB loader.
  static MeshTemplate fromTriangleSoup(
    Float32List positions,
    Uint16List indices, {
    Float32List? colors,
    String name = '',
  }) {
    final triCount = indices.length ~/ 3;
    final pos = Float32List(triCount * 9);
    final nrm = Float32List(triCount * 9);
    final col = colors == null ? null : Float32List(triCount * 12);
    final idx = Uint16List(triCount * 3);

    final a = Vector3.zero(), b = Vector3.zero(), c = Vector3.zero();
    for (var t = 0; t < triCount; t++) {
      final i0 = indices[t * 3],
          i1 = indices[t * 3 + 1],
          i2 = indices[t * 3 + 2];
      a.setValues(
        positions[i0 * 3],
        positions[i0 * 3 + 1],
        positions[i0 * 3 + 2],
      );
      b.setValues(
        positions[i1 * 3],
        positions[i1 * 3 + 1],
        positions[i1 * 3 + 2],
      );
      c.setValues(
        positions[i2 * 3],
        positions[i2 * 3 + 1],
        positions[i2 * 3 + 2],
      );
      final n = (b - a).cross(c - a);
      if (n.length2 > 1e-12) n.normalize();

      final o = t * 9;
      pos[o] = a.x;
      pos[o + 1] = a.y;
      pos[o + 2] = a.z;
      pos[o + 3] = b.x;
      pos[o + 4] = b.y;
      pos[o + 5] = b.z;
      pos[o + 6] = c.x;
      pos[o + 7] = c.y;
      pos[o + 8] = c.z;
      for (var k = 0; k < 3; k++) {
        nrm[o + k * 3] = n.x;
        nrm[o + k * 3 + 1] = n.y;
        nrm[o + k * 3 + 2] = n.z;
      }
      if (col != null && colors != null) {
        final srcs = [i0, i1, i2];
        for (var k = 0; k < 3; k++) {
          final s = srcs[k] * 4;
          final d = t * 12 + k * 4;
          col[d] = colors[s];
          col[d + 1] = colors[s + 1];
          col[d + 2] = colors[s + 2];
          col[d + 3] = colors[s + 3];
        }
      }
      idx[t * 3] = t * 3;
      idx[t * 3 + 1] = t * 3 + 1;
      idx[t * 3 + 2] = t * 3 + 2;
    }
    return MeshTemplate(
      positions: pos,
      normals: nrm,
      indices: idx,
      colors: col,
      name: name,
    );
  }
}
