# MAGNET RUSH

### ATTRACT. CHARGE. BLAST.

A one-finger 3D action-puzzle game for Android. You control the **Kanban Core**,
a magnetic energy crystal that travels through floating futuristic facilities.
There is exactly one control:

* **Hold** — attract metal. The swarm grows around you and becomes armour.
* **Release** — repel. Everything you collected launches outward and destroys
  what is in front of you.

> **Project status: early. Foundations built and verified; the game itself is
> not built yet.** Read `docs/known_limitations.md` before anything else — it
> states plainly what works and what does not.

## What currently works, verified on an Android build

* Renderer selected and proven by a running app — `lib/dev/smoke_test.dart`
  renders the Kanban Core, 100 collectible objects, hold-to-attract,
  controlled swarm orbit, release-to-repel and a breakable wall.
* Debug and release APKs build and run.
* 54 GLB assets generated headlessly from Blender, 0 triangle-budget violations.
* A shipping-critical Impeller GLES crash root-caused and fixed.

Not yet built: the game proper, all 50 levels, all enemies and bosses, and every
meta system. See `docs/known_limitations.md`.

## Quick start

```sh
flutter pub get

# renderer / swarm harness on a device or emulator
flutter run -t lib/dev/smoke_test.dart --release

# regenerate every 3D asset from source
blender --background --python art/blender/build_assets.py
python art/blender/write_manifest_md.py
```

Requires Flutter **stable 3.44.8**, Android SDK 36, JDK 17, and Blender 5.2 for
asset work. Flutter GPU needs `flutter config --enable-native-assets` once.

## Layout

```
lib/dev/            renderer + swarm smoke-test harness
art/blender/        scripted asset generators (no .blend files by design)
assets/models/      generated GLB output
third_party/        vendored, patched flutter_scene — see its README
android/            app id ae.kanbanstudios.magnet_rush, portrait, Flutter GPU on
docs/               design, decisions, pipeline, manifest, limitations
```

## Technology

| | |
|---|---|
| App shell, UI, meta | Flutter (stable 3.44.8) |
| Gameplay 3D | `flutter_scene` 0.16.0 (vendored + patched) on Flutter GPU / Impeller |
| Backend | Impeller Vulkan preferred, GLES 3.0 supported |
| Swarm | One merged dynamic mesh rebuilt per frame — N objects, 1 draw call |
| Physics | Custom deterministic kinematics; no rigid-body engine |
| Art | Scripted Blender 5.2, flat-shaded low-poly, no textures |

The reasoning, the alternatives rejected, and the measurements are in
`docs/renderer_decision.md`.

## Documentation

| Document | Contents |
|---|---|
| `docs/renderer_decision.md` | Renderer/physics choice, benchmarks, the GLES crash |
| `docs/blender_pipeline.md` | How assets are generated and the conventions enforced |
| `docs/asset_manifest.md` | Generated table of all 54 assets |
| `docs/known_limitations.md` | **Honest status — what is and is not done** |
| `third_party/README.md` | Why `flutter_scene` is vendored and what was patched |
