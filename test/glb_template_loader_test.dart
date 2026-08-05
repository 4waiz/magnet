import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:magnet_rush/game/renderer/glb_template_loader.dart';
import 'package:magnet_rush/game/renderer/mesh_template.dart';

MeshTemplate parseFile(String path) {
  final bytes = File(path).readAsBytesSync();
  return GlbTemplateLoader.parse(Uint8List.fromList(bytes), name: path);
}

void main() {
  group('GlbTemplateLoader', () {
    test('parses a single-material Blender export', () {
      final t = parseFile('assets/models/metal/metal_bolt.glb');
      expect(t.triangleCount, greaterThan(0));
      expect(t.positions.length, t.triangleCount * 9);
      expect(t.normals.length, t.triangleCount * 9);
      expect(t.indices.length, t.triangleCount * 3);
      expect(t.boundingRadius, greaterThan(0));
    });

    test('merges multi-material meshes and bakes per-primitive colour', () {
      // The Core upper cap has two material slots (bright / deep navy), so it
      // exports as two primitives. They must merge into one template with
      // different vertex colours, or the swarm batch loses the shading split.
      final t = parseFile('assets/models/core/core_shell_upper.glb');
      expect(t.colors, isNotNull);
      expect(t.colors!.length, t.vertexCount * 4);

      final distinct = <String>{};
      for (var i = 0; i < t.vertexCount; i++) {
        final o = i * 4;
        distinct.add(
          '${t.colors![o].toStringAsFixed(3)},'
          '${t.colors![o + 1].toStringAsFixed(3)},'
          '${t.colors![o + 2].toStringAsFixed(3)}',
        );
      }
      expect(
        distinct.length,
        greaterThanOrEqualTo(2),
        reason: 'expected at least two baked material colours',
      );
    });

    test('normals are unit length and per-face', () {
      final t = parseFile('assets/models/metal/metal_gear_small.glb');
      for (var i = 0; i < t.vertexCount; i++) {
        final o = i * 3;
        final len =
            (t.normals[o] * t.normals[o] +
                    t.normals[o + 1] * t.normals[o + 1] +
                    t.normals[o + 2] * t.normals[o + 2])
                .abs();
        expect(len, closeTo(1.0, 1e-3));
      }
      // Flat shading: the three vertices of a triangle share one normal.
      expect(t.normals[0], closeTo(t.normals[3], 1e-6));
      expect(t.normals[1], closeTo(t.normals[4], 1e-6));
    });

    test('normalizedTo rescales to the requested bounding radius', () {
      final t = parseFile('assets/models/metal/metal_nut.glb');
      final scaled = t.normalizedTo(0.25);
      expect(scaled.boundingRadius, closeTo(0.25, 1e-4));
      expect(scaled.triangleCount, t.triangleCount);
    });

    test('rejects non-GLB bytes with a clear message', () {
      expect(
        () => GlbTemplateLoader.parse(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<GlbParseException>()),
      );
    });

    test(
      'every swarm-facing asset loads and stays inside the index budget',
      () {
        final dir = Directory('assets/models/metal');
        final files = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.glb'))
            .toList();
        expect(files, isNotEmpty);
        for (final f in files) {
          final t = parseFile(f.path);
          expect(t.triangleCount, greaterThan(0), reason: f.path);
          expect(t.indices.length, lessThanOrEqualTo(0xFFFF), reason: f.path);
        }
      },
    );
  });
}
