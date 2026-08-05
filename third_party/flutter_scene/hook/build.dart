import 'package:hooks/hooks.dart';

import 'package:flutter_gpu_shaders/build.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    await buildShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/base.shaderbundle.json',
      // MAGNET RUSH LOCAL PATCH.
      //
      // Upstream 0.16.0 leaves this at impellerc's default (GLSL ES 1.00).
      // The engine lighting shaders sample radiance with textureLod, which is
      // core in 300 es but under the 1.00 profile requires
      // GL_EXT_shader_texture_lod. Impeller's GLES backend rejects that at
      // compile time and aborts the raster thread in render_pass_gles.cc
      // ("Must be able to encode GL commands without error").
      //
      // Impeller falls back to its GLES backend on the Android emulator and on
      // devices without a usable Vulkan driver, so this is a shipping concern,
      // not merely a local one. Pinning 300 sets the native GLES floor at
      // OpenGL ES 3.0, which covers our whole target range.
      //
      // Upstream adopted the same fix in 0.20.0.
      glesLanguageVersion: 300,
    );
  });
}
