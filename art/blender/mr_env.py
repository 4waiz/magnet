"""Magnet Rush — environment kit.

The modular platform vocabulary Level 1 is assembled from, plus the obstacles
and set dressing that give the scene depth.

Module conventions, so levels can be authored as data:

  * pivot at the CENTRE of the walkable top surface (Blender z = 0)
  * length runs along Blender +Y, which becomes the level's forward axis
  * a lane is 4.0 m wide; the standard module is 6.0 m long
  * every deck gets a chamfered bright top, a darker body, understructure
    hanging below, and a little greeble — a platform whose underside is bare
    reads as a flat card the moment the camera sees over its edge

    # from Blender MCP
    import mr_env; mr_env.build_environment()
"""

from __future__ import annotations

import math
import random

import bpy

import mr_kit as K
import mr_hero as H

LANE_W = 4.0
MODULE_L = 6.0


def _deck_module(name, sx, sy, M, *, seed=5, circuits=True, hazard=False,
                 ribs=4, greeble_count=8, thickness=0.34):
    """Deck + understructure + circuits + greeble, returned unjoined."""
    parts = H.deck(name, sx, sy, thickness=thickness,
                   top_mat=M["deck_top"], body_mat=M["deck_body"])
    parts += H.understructure(name, sx, sy, seed=seed, depth=1.4, ribs=ribs,
                              mat=M["deck_mech"])
    parts += H.greeble(name, sx * 0.8, sy * 0.8, count=greeble_count,
                       seed=seed + 3, mat=M["deck_mech"])
    if circuits:
        parts.append(H.circuit_inset(
            f"{name}_circ_a",
            [(-sx * 0.55, -sy), (-sx * 0.55, sy * 0.2), (sx * 0.2, sy * 0.2),
             (sx * 0.2, sy)],
            width=0.045, mat=M["circuit"]))
        parts.append(H.circuit_inset(
            f"{name}_circ_b", [(sx * 0.72, -sy), (sx * 0.72, sy)],
            width=0.028, mat=M["circuit"]))
    if hazard:
        parts.append(H.circuit_inset(
            f"{name}_haz", [(-sx, sy * 0.78), (sx, sy * 0.78)],
            width=0.055, mat=M["hazard_line"]))
    return parts


def build_environment(M: dict | None = None) -> dict:
    """The Level 1 platform kit, obstacles and set dressing."""
    M = M or H.hero_materials()
    H.use_build_scene()
    H.clear_build_scene()
    print("[environment]")

    hx, hy = LANE_W * 0.5, MODULE_L * 0.5
    A = H._adopt

    # --- Straight ----------------------------------------------------------
    p = _deck_module("plat_straight", hx, hy, M, seed=5)
    H.emit(K.join(p, "platform_straight"), "platforms/platform_straight.glb",
           budget="prop", purpose="Standard 4x6 m walkable deck",
           collider="box 4x0.4x6")

    # --- Short -------------------------------------------------------------
    p = _deck_module("plat_short", hx, hy * 0.5, M, seed=9, ribs=3,
                     greeble_count=5)
    H.emit(K.join(p, "platform_short"), "platforms/platform_short.glb",
           budget="prop", purpose="Half-length deck for spacing and gaps",
           collider="box 4x0.4x3")

    # --- Wide arena --------------------------------------------------------
    p = _deck_module("plat_wide", hx * 1.7, hy, M, seed=13, ribs=6,
                     greeble_count=14)
    H.emit(K.join(p, "platform_wide"), "platforms/platform_wide.glb",
           budget="machine", purpose="Wide deck for the opening and set pieces",
           collider="box 6.8x0.4x6")

    # --- Side ledge --------------------------------------------------------
    p = _deck_module("plat_ledge", hx * 0.55, hy * 0.7, M, seed=63, ribs=2,
                     greeble_count=4, circuits=False, thickness=0.26)
    H.emit(K.join(p, "platform_ledge"), "platforms/platform_ledge.glb",
           budget="prop", purpose="Small side ledge; holds metal groups",
           collider="box 2.2x0.3x4.2")

    # --- Corner (L turn) ---------------------------------------------------
    p = _deck_module("plat_corner", hx, hy, M, seed=21, circuits=False)
    arm = H.deck("plat_corner_arm", hy, hx, thickness=0.34,
                 top_mat=M["deck_top"], body_mat=M["deck_body"])
    for a in arm:
        a.location = (hy, hy - hx, 0.0)
    p += arm
    p.append(H.circuit_inset(
        "plat_corner_circ",
        [(-hx * 0.5, -hy), (-hx * 0.5, hy * 0.35), (hx * 1.6, hy * 0.35)],
        width=0.045, mat=M["circuit"]))
    H.emit(K.join(p, "platform_corner"), "platforms/platform_corner.glb",
           budget="machine", purpose="90-degree route turn", collider="composite")

    # --- Curve -------------------------------------------------------------
    curve_parts = []
    steps = 7
    r = 5.6
    for i in range(steps):
        t = i / (steps - 1)
        a = t * (math.pi * 0.42)
        cx = math.sin(a) * r - r
        cy = math.cos(a) * r - r + MODULE_L * 0.5
        seg = H.deck(f"plat_curve_s{i}", hx * 0.92, MODULE_L / steps * 0.62,
                     thickness=0.30, top_mat=M["deck_top"],
                     body_mat=M["deck_body"])
        for s in seg:
            s.location = (cx, cy, 0.0)
            s.rotation_euler = (0.0, 0.0, -a)
        curve_parts += seg
    curve_parts += H.understructure("plat_curve", hx, hy, seed=31, ribs=5,
                                    mat=M["deck_mech"])
    H.emit(K.join(curve_parts, "platform_curve"),
           "platforms/platform_curve.glb", budget="machine",
           purpose="Swept route curve", collider="composite")

    # --- Ramp --------------------------------------------------------------
    p = _deck_module("plat_ramp", hx, hy, M, seed=17, greeble_count=4)
    ramp = K.join(p, "platform_ramp")
    A(ramp)
    ramp.rotation_euler = (math.radians(11.0), 0.0, 0.0)
    H.emit(ramp, "platforms/platform_ramp.glb", budget="prop",
           purpose="11-degree climb linking deck heights", collider="box slope")

    # --- Raised laboratory base -------------------------------------------
    p = _deck_module("lab_base", hx * 1.35, hy * 0.95, M, seed=41, ribs=6,
                     greeble_count=16, thickness=0.52)
    for i, (lx, ly, lz, w, d, h) in enumerate([
        (-hx * 1.05, -hy * 0.45, 0.55, 0.26, 0.26, 0.55),
        (hx * 1.05, -hy * 0.45, 0.55, 0.26, 0.26, 0.55),
        (-hx * 1.05, hy * 0.55, 0.75, 0.22, 0.22, 0.75),
        (hx * 1.05, hy * 0.55, 0.75, 0.22, 0.22, 0.75),
    ]):
        p.append(A(K.box(f"lab_col{i}", w, d, h, at=(lx, ly, lz),
                         mat=M["metal_dark"])))
    p.append(A(K.bevel_plate("lab_hood", hx * 1.2, hy * 0.8, 0.09, cut=0.10,
                             at=(0, hy * 0.1, 1.42), mat=M["deck_mech"])))
    p.append(H.circuit_inset("lab_hood_glow",
                             [(-hx * 1.1, hy * 0.1), (hx * 1.1, hy * 0.1)],
                             width=0.06, z=1.34, mat=M["circuit"]))
    H.emit(K.join(p, "platform_lab_base"), "platforms/platform_lab_base.glb",
           budget="machine",
           purpose="Raised laboratory section with canopy and support columns",
           collider="box + columns")

    # --- Bridge anchor -----------------------------------------------------
    parts = [A(K.bevel_plate("anchor_base", 0.62, 0.62, 0.30, cut=0.07,
                             at=(0, 0, -0.15), mat=M["deck_body"]))]
    for i in range(3):
        parts.append(A(K.box(f"anchor_fin{i}", 0.10, 0.42, 0.62,
                             at=(-0.34 + i * 0.34, 0, 0.31),
                             mat=M["metal_dark"])))
    parts.append(A(K.torus("anchor_coil", major=0.40, minor=0.045,
                           major_seg=14, minor_seg=5, at=(0, 0, 0.78),
                           mat=M["circuit"])))
    H.emit(K.join(parts, "platform_bridge_anchor"),
           "platforms/platform_bridge_anchor.glb", budget="prop",
           purpose="Magnetic anchor; bridge pieces lock between a pair",
           collider="box 1.2x1.6x1.2")

    # --- Machinery socket --------------------------------------------------
    parts = [A(K.cylinder("socket_drum", radius=0.72, depth=0.55, segments=10,
                          at=(0, 0, -0.28), mat=M["deck_body"])),
             A(K.torus("socket_ring", major=0.72, minor=0.06, major_seg=12,
                       minor_seg=5, at=(0, 0, -0.02), mat=M["circuit"]))]
    for i in range(4):
        a = i * math.pi / 2
        parts.append(A(K.box(f"socket_b{i}", 0.14, 0.14, 0.22,
                             at=(math.cos(a) * 0.55, math.sin(a) * 0.55, -0.11),
                             mat=M["metal_dark"])))
    H.emit(K.join(parts, "prop_machinery_socket"),
           "platforms/prop_machinery_socket.glb", budget="prop",
           purpose="Deck-mounted machinery socket; set dressing and metal source",
           collider="cylinder r=0.72")

    # --- Decorative tower --------------------------------------------------
    rng = random.Random(77)
    parts = []
    hgt = 0.0
    for i in range(5):
        w = 0.85 - i * 0.13
        h = rng.uniform(0.9, 1.7)
        parts.append(A(K.bevel_plate(
            f"tower_s{i}", w, w, h, cut=0.06,
            at=(rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), hgt + h * 0.5),
            mat=M["deck_body"] if i % 2 == 0 else M["deck_mech"])))
        hgt += h
    parts.append(H.circuit_inset("tower_glow", [(-0.5, 0.0), (0.5, 0.0)],
                                 width=0.05, z=hgt * 0.55, mat=M["circuit"]))
    parts.append(A(K.cylinder("tower_mast", radius=0.06, depth=1.5, segments=6,
                              at=(0, 0, hgt + 0.75), mat=M["metal_dark"])))
    H.emit(K.join(parts, "prop_tower"), "platforms/prop_tower.glb",
           budget="prop", purpose="Background/midground vertical silhouette",
           collider="none")

    # --- Suspended cable support -------------------------------------------
    parts = []
    for side in (-1, 1):
        parts.append(A(K.box(f"cable_pylon{side}", 0.16, 0.16, 2.6,
                             at=(side * 2.6, 0, 1.3), mat=M["metal_dark"])))
    parts.append(A(K.box("cable_span", 2.7, 0.07, 0.07, at=(0, 0, 2.5),
                         mat=M["metal_dark"])))
    for i in range(5):
        parts.append(A(K.box(f"cable_drop{i}", 0.03, 0.03, 0.9,
                             at=(-2.0 + i * 1.0, 0, 2.05), mat=M["metal"])))
    H.emit(K.join(parts, "prop_cable_support"),
           "platforms/prop_cable_support.glb", budget="prop",
           purpose="Suspended machinery over the route", collider="none")

    # --- Portal deck + finish portal ---------------------------------------
    p = _deck_module("portal_deck", hx * 1.25, hy * 0.8, M, seed=55, ribs=5,
                     greeble_count=8)
    H.emit(K.join(p, "platform_portal"), "platforms/platform_portal.glb",
           budget="machine", purpose="Deck the finish portal stands on",
           collider="box 5x0.4x4.8")

    parts = []
    for i, (maj, minr) in enumerate([(1.55, 0.11), (1.30, 0.07)]):
        ring = A(K.torus(f"portal_ring{i}", major=maj, minor=minr,
                         major_seg=20, minor_seg=6, at=(0, 0, 1.75),
                         mat=M["portal"]))
        ring.rotation_euler = (math.pi / 2, 0, 0)
        parts.append(ring)
    for i in range(6):
        a = i * math.tau / 6
        pin = A(K.box(f"portal_pin{i}", 0.10, 0.10, 0.24,
                      at=(math.cos(a) * 1.55, 0.0, 1.75 + math.sin(a) * 1.55),
                      mat=M["metal_dark"]))
        pin.rotation_euler = (0, -a, 0)
        parts.append(pin)
    for side in (-1, 1):
        parts.append(A(K.box(f"portal_leg{side}", 0.20, 0.24, 0.95,
                             at=(side * 1.5, 0, 0.47), mat=M["deck_body"])))
    H.emit(K.join(parts, "obstacle_finish_portal"),
           "obstacles/obstacle_finish_portal.glb", budget="machine",
           purpose="Level exit; rings spin and fill with energy once unlocked",
           collider="torus r=1.55")

    disc = A(K.cylinder("portal_disc", radius=1.28, depth=0.05, segments=20,
                        at=(0, 0, 1.75), mat=M["portal"]))
    disc.rotation_euler = (math.pi / 2, 0, 0)
    H.emit(disc, "obstacles/obstacle_portal_disc.glb", budget="swarm",
           purpose="Portal energy surface; fades in on unlock", collider="none")

    # --- Barred key chamber ------------------------------------------------
    parts = []
    for side in (-1, 1):
        parts.append(A(K.box(f"key_post{side}", 0.12, 0.12, 1.85,
                             at=(side * 1.05, 0, 0.92), mat=M["metal_dark"])))
    for i in range(5):
        bar = A(K.cylinder(f"key_bar{i}", radius=0.052, depth=2.1, segments=6,
                           at=(-0.84 + i * 0.42, 0, 0.95), mat=M["metal"]))
        bar.rotation_euler = (math.pi / 2, 0, 0)
        parts.append(bar)
    for z in (0.06, 1.84):
        parts.append(A(K.box(f"key_rail{int(z * 100)}", 1.12, 0.09, 0.09,
                             at=(0, 0, z), mat=M["metal_dark"])))
    parts.append(A(K.bevel_plate("key_back", 1.10, 0.10, 1.85, cut=0.05,
                                 at=(0, 0.62, 0.92), mat=M["deck_body"])))
    parts.append(H.circuit_inset("key_back_glow", [(-0.9, 0.55), (0.9, 0.55)],
                                 width=0.05, z=1.5, mat=M["circuit"]))
    H.emit(K.join(parts, "obstacle_key_chamber"),
           "obstacles/obstacle_key_chamber.glb", budget="machine",
           purpose="Barred chamber; the key must be attracted between the bars",
           collider="composite")

    # --- Hazard emitter ----------------------------------------------------
    parts = [A(K.bevel_plate("haz_body", 0.55, 0.55, 0.70, cut=0.08,
                             at=(0, 0, 0.35), mat=M["deck_body"]))]
    head = A(K.cone("haz_head", radius=0.42, depth=0.66, segments=8,
                    at=(0, 0, 1.0), mat=M["metal_dark"]))
    head.rotation_euler = (math.pi / 2, 0, 0)
    parts.append(head)
    lens = A(K.torus("haz_lens", major=0.30, minor=0.06, major_seg=12,
                     minor_seg=5, at=(0, -0.28, 1.0), mat=M["hazard_line"]))
    lens.rotation_euler = (math.pi / 2, 0, 0)
    parts.append(lens)
    H.emit(K.join(parts, "obstacle_hazard_emitter"),
           "obstacles/obstacle_hazard_emitter.glb", budget="prop",
           purpose="Telegraphed damage source; lens flashes orange before firing",
           collider="box 1.1x1.4x1.1")

    # --- Background silhouettes -------------------------------------------
    for idx, seed in enumerate((101, 137, 173)):
        rng = random.Random(seed)
        parts = []
        for i in range(rng.randint(5, 8)):
            w = rng.uniform(0.6, 2.2)
            d = rng.uniform(0.6, 1.8)
            h = rng.uniform(1.5, 7.0)
            parts.append(A(K.box(f"bg{idx}_{i}", w, d, h,
                                 at=(rng.uniform(-7, 7), rng.uniform(-3, 3),
                                     h * 0.5),
                                 mat=M["backdrop"])))
        H.emit(K.join(parts, f"prop_backdrop_{idx}"),
               f"platforms/prop_backdrop_{idx}.glb", budget="prop",
               purpose="Distant facility silhouette; darkest depth layer",
               collider="none")

    return {"records": len(H.RECORDS)}
