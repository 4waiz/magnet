"""Magnet Rush — runtime asset generator.

Builds every GLB the game loads, headlessly:

    blender --background --python art/blender/build_assets.py

    # or a subset
    blender --background --python art/blender/build_assets.py -- core metal

Outputs land in assets/models/ and a machine-readable index is written to
art/blender/asset_index.json, from which docs/asset_manifest.md is generated.
"""

from __future__ import annotations

import os
import sys

# Blender does not put the script's own directory on sys.path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import mr_kit as K  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(REPO, "assets", "models")

RECORDS: list[dict] = []


def emit(obj, rel_path: str, *, budget: str, purpose: str, collider: str):
    """Exports one asset and records it, failing loudly if over budget."""
    path = os.path.join(OUT, rel_path.replace("/", os.sep))
    rec = K.export_glb(obj, path)
    rec["glb"] = "assets/models/" + rel_path
    rec["budget_class"] = budget
    rec["purpose"] = purpose
    rec["collider"] = collider
    limit = K.BUDGETS[budget]
    rec["over_budget"] = rec["triangles"] > limit
    if rec["over_budget"]:
        print(
            f"  !! OVER BUDGET {rel_path}: {rec['triangles']} tris > {limit}",
            file=sys.stderr,
        )
    RECORDS.append(rec)
    print(f"  {rel_path:44s} {rec['triangles']:6d} tris  {rec['bytes']:7d} B")
    return rec


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------


def mats():
    return {
        "core_crystal": K.material(
            "MR_CoreCrystal", K.CORE_BLUE, metallic=0.15, roughness=0.18,
            emission=K.CYAN, emission_strength=6.0,
        ),
        "core_inner": K.material(
            "MR_CoreInner", K.ICE, metallic=0.0, roughness=0.05,
            emission=K.ICE, emission_strength=14.0,
        ),
        "core_deep": K.material(
            "MR_CoreDeep", K.CORE_DEEP, metallic=0.35, roughness=0.35,
            emission=K.CORE_BLUE, emission_strength=1.2,
        ),
        "energy": K.material(
            "MR_Energy", K.CYAN, metallic=0.0, roughness=0.1,
            emission=K.CYAN, emission_strength=10.0, alpha=0.55,
        ),
        "energy_white": K.material(
            "MR_EnergyWhite", K.WHITE, metallic=0.0, roughness=0.1,
            emission=K.WHITE, emission_strength=16.0, alpha=0.6,
        ),
        "metal": K.material("MR_Metal", K.SILVER, metallic=0.92, roughness=0.32),
        "metal_dark": K.material("MR_MetalDark", K.STEEL, metallic=0.88,
                                 roughness=0.45),
        "platform": K.material("MR_Platform", K.CHARCOAL, metallic=0.55,
                               roughness=0.62),
        "platform_top": K.material("MR_PlatformTop", (0.30, 0.34, 0.42),
                                   metallic=0.5, roughness=0.55),
        "circuit": K.material(
            "MR_Circuit", K.CYAN, metallic=0.0, roughness=0.2,
            emission=K.CYAN, emission_strength=8.0,
        ),
        "hazard": K.material(
            "MR_Hazard", K.ORANGE, metallic=0.2, roughness=0.4,
            emission=K.ORANGE, emission_strength=7.0,
        ),
        "success": K.material(
            "MR_Success", K.GREEN, metallic=0.0, roughness=0.2,
            emission=K.GREEN, emission_strength=8.0,
        ),
        "gold": K.material("MR_Gold", K.AMBER, metallic=1.0, roughness=0.22,
                           emission=K.AMBER, emission_strength=2.0),
    }


# ---------------------------------------------------------------------------
# Group: the Kanban Core
# ---------------------------------------------------------------------------


def build_core(M):
    print("[core]")

    # Full assembled Core: faceted shell + inner crystal + magnetic ring.
    shell = K.crystal("shell", radius=0.5, subdiv=1, jitter=0.16, seed=11,
                      mat=M["core_crystal"])
    inner = K.crystal("inner", radius=0.27, subdiv=1, jitter=0.30, seed=29,
                      mat=M["core_inner"])
    ring = K.torus("ring", major=0.72, minor=0.035, major_seg=18, minor_seg=5,
                   mat=M["energy"])
    ring.rotation_euler = (0.28, 0.0, 0.0)
    core = K.join([shell, inner, ring], "kanban_core")
    emit(core, "core/kanban_core.glb", budget="interactive",
         purpose="Player character, assembled default state", collider="sphere r=0.5")

    emit(
        K.crystal("kanban_core_inner_crystal", radius=0.27, subdiv=1,
                  jitter=0.30, seed=29, mat=M["core_inner"]),
        "core/kanban_core_inner_crystal.glb", budget="swarm",
        purpose="Inner energy crystal; scales/pulses with charge",
        collider="none",
    )
    emit(
        K.crystal("kanban_core_outer_shell", radius=0.5, subdiv=1, jitter=0.16,
                  seed=11, mat=M["core_crystal"]),
        "core/kanban_core_outer_shell.glb", budget="prop",
        purpose="Outer faceted shell; swappable per skin",
        collider="sphere r=0.5",
    )
    emit(
        K.torus("kanban_core_magnetic_ring", major=0.72, minor=0.035,
                major_seg=20, minor_seg=5, mat=M["energy"]),
        "core/kanban_core_magnetic_ring.glb", budget="swarm",
        purpose="Orbiting magnetic ring; spins while attracting",
        collider="none",
    )
    emit(
        K.torus("kanban_core_charge_ring", major=0.95, minor=0.022,
                major_seg=24, minor_seg=4, mat=M["energy_white"]),
        "core/kanban_core_charge_ring.glb", budget="swarm",
        purpose="Charge indicator ring; radius tracks charge level",
        collider="none",
    )
    emit(
        K.crystal("kanban_core_overcharge_shell", radius=0.62, subdiv=1,
                  jitter=0.10, seed=7, mat=M["energy_white"]),
        "core/kanban_core_overcharge_shell.glb", budget="prop",
        purpose="Stage 5 overcharge aura shell", collider="none",
    )
    emit(
        K.icosphere("kanban_core_shield", radius=0.95, subdiv=1,
                    mat=M["energy"]),
        "core/kanban_core_shield.glb", budget="prop",
        purpose="Armour/shield bubble when protected", collider="none",
    )

    # Repulsion shockwave: a flat expanding ring, scaled at runtime.
    emit(
        K.torus("kanban_core_repulse_wave", major=1.0, minor=0.06,
                major_seg=28, minor_seg=4, mat=M["energy_white"]),
        "core/kanban_core_repulse_wave.glb", budget="prop",
        purpose="Release shockwave; uniformly scaled outward",
        collider="none",
    )
    # Trail + field line are thin strips stretched along their local +Z.
    emit(
        K.box("kanban_core_trail", 0.14, 0.02, 1.0, mat=M["energy"]),
        "core/kanban_core_trail.glb", budget="debris",
        purpose="Motion trail quad; stretched along travel direction",
        collider="none",
    )
    emit(
        K.box("kanban_core_field_line", 0.02, 0.02, 1.0, mat=M["circuit"]),
        "core/kanban_core_field_line.glb", budget="debris",
        purpose="Magnetic field line; bends toward Core while holding",
        collider="none",
    )


# ---------------------------------------------------------------------------
# Group: collectible metal
# ---------------------------------------------------------------------------


def build_metal(M):
    print("[metal]")
    m, md = M["metal"], M["metal_dark"]

    specs = [
        ("metal_cube_small", lambda: K.box("metal_cube_small", .16, .16, .16, mat=m)),
        ("metal_cube_medium", lambda: K.box("metal_cube_medium", .26, .26, .26, mat=m)),
        ("metal_cube_large", lambda: K.box("metal_cube_large", .40, .40, .40, mat=m)),
        ("metal_sphere_small", lambda: K.icosphere("metal_sphere_small", .14, 1, mat=m)),
        ("metal_sphere_heavy", lambda: K.icosphere("metal_sphere_heavy", .26, 1, mat=md)),
        ("metal_plate", lambda: K.bevel_plate("metal_plate", .40, .30, .05, cut=.02, mat=m)),
        ("metal_rod", lambda: K.cylinder("metal_rod", .05, .62, 8, mat=m)),
        ("metal_ring", lambda: K.torus("metal_ring", .18, .05, 12, 5, mat=m)),
        ("metal_bolt", lambda: _bolt(m)),
        ("metal_nut", lambda: _nut(md)),
        ("metal_gear_small", lambda: K.gear("metal_gear_small", 8, .10, .17, .24, .09, mat=md)),
        ("metal_gear_large", lambda: K.gear("metal_gear_large", 12, .16, .28, .40, .12, mat=md)),
        ("metal_pipe_piece", lambda: K.cylinder("metal_pipe_piece", .13, .46, 10, mat=md, cap=False)),
        ("metal_scrap_triangle", lambda: K.cone("metal_scrap_triangle", .20, .30, 3, mat=m)),
        ("metal_scrap_block", lambda: K.crystal("metal_scrap_block", .19, 0, .38, 5, mat=m)),
        ("metal_scrap_curved", lambda: K.cylinder("metal_scrap_curved", .20, .10, 6, mat=m, cap=False)),
    ]
    for name, make in specs:
        emit(make(), f"metal/{name}.glb", budget="swarm",
             purpose="Collectible swarm metal", collider="sphere (batched)")

    # Special pieces
    emit(K.icosphere("heavy_projectile_ball", .30, 1, mat=md),
         "metal/heavy_projectile_ball.glb", budget="swarm",
         purpose="Heavy projectile; slow but high impact", collider="sphere r=0.30")
    emit(K.bevel_plate("armour_plate", .34, .26, .07, cut=.03, mat=m),
         "metal/armour_plate.glb", budget="swarm",
         purpose="Armour piece; absorbs one hazard impact", collider="box")
    emit(K.cone("armour_spike", .12, .34, 5, mat=md),
         "metal/armour_spike.glb", budget="swarm",
         purpose="Aggressive armour variant", collider="box")
    emit(_key(M), "metal/magnetic_key.glb", budget="prop",
         purpose="Unlocks the finish portal; pulled through bars",
         collider="sphere r=0.25")
    emit(K.bevel_plate("bridge_segment", .55, .42, .06, cut=.02, mat=m),
         "metal/bridge_segment.glb", budget="swarm",
         purpose="Bridge deck plate; snaps to anchors on release", collider="box")
    emit(K.box("bridge_beam", .09, .09, .95, mat=md),
         "metal/bridge_beam.glb", budget="swarm",
         purpose="Bridge spar; spans between anchors", collider="box")
    emit(_battery(M), "metal/energy_battery.glb", budget="prop",
         purpose="Powers machinery when delivered", collider="box")
    emit(_cell(M, "power_cell", K.CYAN), "metal/power_cell.glb", budget="prop",
         purpose="Activates energy sockets and lifts", collider="box")
    emit(_cell(M, "explosive_charge_cell", K.ORANGE),
         "metal/explosive_charge_cell.glb", budget="prop",
         purpose="Area damage on impact", collider="box")
    emit(K.crystal("magnetic_crystal", .22, 1, .25, 3, mat=M["energy"]),
         "metal/magnetic_crystal.glb", budget="swarm",
         purpose="Bonus charge pickup", collider="sphere r=0.22")
    emit(K.crystal("boss_damage_shard", .18, 0, .40, 17, mat=M["hazard"]),
         "metal/boss_damage_shard.glb", budget="swarm",
         purpose="Boss weak-point projectile", collider="sphere r=0.18")


def _bolt(mat):
    head = K.cylinder("head", .09, .06, 6, at=(0, 0, .13), mat=mat)
    shaft = K.cylinder("shaft", .045, .22, 6, mat=mat)
    return K.join([head, shaft], "metal_bolt")


def _nut(mat):
    outer = K.cylinder("outer", .11, .07, 6, mat=mat)
    return K.join([outer], "metal_nut")


def _key(M):
    stem = K.box("stem", .04, .04, .30, mat=M["gold"])
    ring = K.torus("kring", .10, .028, 10, 4, at=(0, 0, .20), mat=M["gold"])
    tooth = K.box("tooth", .09, .04, .04, at=(.05, 0, -.12), mat=M["gold"])
    glow = K.icosphere("glow", .13, 0, at=(0, 0, .20), mat=M["success"])
    return K.join([stem, ring, tooth, glow], "magnetic_key")


def _battery(M):
    body = K.bevel_plate("body", .16, .16, .30, cut=.03, mat=M["metal_dark"])
    band = K.box("band", .17, .17, .06, at=(0, 0, .06), mat=M["circuit"])
    return K.join([body, band], "energy_battery")


def _cell(M, name, color):
    glowmat = K.material(
        f"MR_Cell_{name}", color, metallic=0.0, roughness=0.15,
        emission=color, emission_strength=9.0,
    )
    shell = K.cylinder("shell", .11, .26, 8, mat=M["metal_dark"])
    core = K.cylinder("core", .07, .30, 8, mat=glowmat)
    return K.join([shell, core], name)


# ---------------------------------------------------------------------------
# Group: platform kit
# ---------------------------------------------------------------------------


def _deck(name, sx, sz, M, circuit=True):
    """A platform island: chamfered charcoal slab with a glowing top inlay."""
    parts = [K.bevel_plate("base", sx, 0.34, sz, cut=0.07, mat=M["platform"])]
    parts.append(
        K.bevel_plate("top", sx * 0.94, 0.06, sz * 0.94, cut=0.04,
                      at=(0, 0.19, 0), mat=M["platform_top"])
    )
    if circuit:
        parts.append(
            K.box("circuit_x", sx * 0.82, 0.012, 0.05, at=(0, 0.23, 0),
                  mat=M["circuit"])
        )
        parts.append(
            K.box("circuit_z", 0.05, 0.012, sz * 0.82, at=(0, 0.23, 0),
                  mat=M["circuit"])
        )
    return K.join(parts, name)


def build_platforms(M):
    print("[platforms]")
    emit(_deck("platform_straight_short", 3.2, 3.2, M),
         "platforms/platform_straight_short.glb", budget="prop",
         purpose="Short straight route module", collider="box")
    emit(_deck("platform_straight_long", 3.2, 6.4, M),
         "platforms/platform_straight_long.glb", budget="prop",
         purpose="Long straight route module", collider="box")
    emit(_deck("platform_arena_small", 7.0, 7.0, M),
         "platforms/platform_arena_small.glb", budget="prop",
         purpose="Small combat/puzzle arena", collider="box")
    emit(_deck("platform_arena_large", 11.0, 11.0, M),
         "platforms/platform_arena_large.glb", budget="machine",
         purpose="Boss arena floor", collider="box")

    # Curves: two decks meeting at a right angle.
    for name, dx in (("platform_curve_left", -1.6), ("platform_curve_right", 1.6)):
        a = _deck("a", 3.2, 3.2, M)
        b = _deck("b", 3.2, 3.2, M, circuit=False)
        b.location = (dx * 2, 0, 3.2)
        emit(K.join([a, b], name), f"platforms/{name}.glb", budget="prop",
             purpose="90-degree route turn", collider="box")

    ramp = _deck("platform_ramp_up", 3.2, 5.0, M)
    ramp.rotation_euler = (-0.20, 0, 0)
    emit(ramp, "platforms/platform_ramp_up.glb", budget="prop",
         purpose="Rising route section", collider="box")

    ramp2 = _deck("platform_ramp_down", 3.2, 5.0, M)
    ramp2.rotation_euler = (0.20, 0, 0)
    emit(ramp2, "platforms/platform_ramp_down.glb", budget="prop",
         purpose="Descending route section", collider="box")

    anchor_parts = [
        K.cylinder("post", .18, .70, 8, mat=M["metal_dark"]),
        K.torus("halo", .26, .04, 12, 4, at=(0, 0, .40), mat=M["circuit"]),
    ]
    emit(K.join(anchor_parts, "platform_bridge_anchor"),
         "platforms/platform_bridge_anchor.glb", budget="prop",
         purpose="Bridge attachment point; glows when bridgeable",
         collider="cylinder")

    finish_parts = [
        K.torus("gate", 1.25, 0.11, 20, 6, mat=M["success"]),
        K.cylinder("disc", 1.16, 0.05, 20, mat=M["energy"]),
        K.bevel_plate("plinth", 2.0, 0.30, 1.2, cut=0.05, at=(0, -1.35, 0),
                      mat=M["platform"]),
    ]
    finish = K.join(finish_parts, "platform_finish")
    finish.rotation_euler = (1.5708, 0, 0)
    emit(finish, "platforms/platform_finish.glb", budget="interactive",
         purpose="Level exit portal; locked until key collected",
         collider="cylinder r=1.25")


# ---------------------------------------------------------------------------
# Group: vertical-slice obstacles
# ---------------------------------------------------------------------------


def build_obstacles(M):
    print("[obstacles]")

    # Cracked wall: a grid of blocks with an orange fracture seam, so the
    # player can read "this one breaks".
    def wall(name, cols, rows, block=0.32):
        parts = []
        for c in range(cols):
            for r in range(rows):
                x = (c - (cols - 1) / 2) * block * 2.06
                y = (r + 0.5) * block * 2.06
                mat = M["hazard"] if (c + r) % 5 == 0 else M["platform_top"]
                parts.append(
                    K.bevel_plate(f"b{c}{r}", block, block, block * 0.55,
                                  cut=0.03, at=(x, y, 0), mat=mat)
                )
        return K.join(parts, name)

    emit(wall("cracked_wall_small", 4, 3), "obstacles/cracked_wall_small.glb",
         budget="prop", purpose="Breakable wall; destroyed by a release",
         collider="box")
    emit(wall("cracked_wall_large", 7, 5), "obstacles/cracked_wall_large.glb",
         budget="machine", purpose="Large breakable wall", collider="box")

    reinforced = wall("reinforced_wall", 5, 4)
    emit(reinforced, "obstacles/reinforced_wall.glb", budget="machine",
         purpose="Needs a heavy projectile or overcharge release",
         collider="box")

    emit(K.bevel_plate("glass_energy_panel", 1.6, 1.1, 0.06, cut=0.03,
                       mat=M["energy"]),
         "obstacles/glass_energy_panel.glb", budget="prop",
         purpose="Shatterable energy panel", collider="box")

    tower = []
    for i in range(6):
        tower.append(
            K.bevel_plate(f"t{i}", 0.34, 0.34, 0.34, cut=0.03,
                          at=(0, i * 0.72, 0), mat=M["platform_top"])
        )
    emit(K.join(tower, "block_tower"), "obstacles/block_tower.glb",
         budget="prop", purpose="Topples when struck", collider="box stack")

    # Damaging hazard for the slice: energy spikes.
    spikes = []
    for i in range(5):
        spikes.append(
            K.cone(f"s{i}", 0.14, 0.52, 5, at=((i - 2) * 0.34, 0.26, 0),
                   mat=M["hazard"])
        )
    spikes.append(
        K.bevel_plate("spike_base", 1.0, 0.08, 0.30, cut=0.02, mat=M["platform"])
    )
    emit(K.join(spikes, "energy_spikes"), "obstacles/energy_spikes.glb",
         budget="prop", purpose="Damaging hazard; armour absorbs one hit",
         collider="box")

    # Barred alcove the key sits behind.
    bars = [K.bevel_plate("frame", 1.1, 1.1, 0.10, cut=0.03,
                          mat=M["platform"])]
    for i in range(4):
        bars.append(
            K.cylinder(f"bar{i}", 0.045, 1.0, 6, at=((i - 1.5) * 0.24, 0, 0.10),
                       mat=M["metal_dark"])
        )
        bars[-1].rotation_euler = (1.5708, 0, 0)
    emit(K.join(bars, "metal_gate"), "obstacles/metal_gate.glb",
         budget="prop", purpose="Bars the key; field reaches through",
         collider="box")


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

GROUPS = {
    "core": build_core,
    "metal": build_metal,
    "platforms": build_platforms,
    "obstacles": build_obstacles,
}


def main() -> None:
    argv = sys.argv
    selected = argv[argv.index("--") + 1:] if "--" in argv else list(GROUPS)
    unknown = [g for g in selected if g not in GROUPS]
    if unknown:
        print(f"unknown group(s): {unknown}; known: {list(GROUPS)}", file=sys.stderr)
        sys.exit(2)

    print(f"Magnet Rush asset build -> {OUT}")
    for group in selected:
        K.reset_scene()
        GROUPS[group](mats())

    index = os.path.join(REPO, "art", "blender", "asset_index.json")
    K.write_manifest(RECORDS, index)

    over = [r for r in RECORDS if r["over_budget"]]
    total = sum(r["triangles"] for r in RECORDS)
    print(f"\n{len(RECORDS)} assets, {total} triangles total")
    print(f"index -> {index}")
    if over:
        print(f"{len(over)} OVER BUDGET:", file=sys.stderr)
        for r in over:
            print(f"  {r['glb']} {r['triangles']}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
