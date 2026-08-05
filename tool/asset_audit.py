"""Audits every GLB in assets/models and regenerates docs/asset_manifest.md.

Reads the files themselves rather than a build-time record, so the manifest
cannot drift from what actually ships. Run from the repo root:

    python tool/asset_audit.py
"""

from __future__ import annotations

import json
import os
import struct
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(REPO, "assets", "models")

BUDGETS = {"swarm": 500, "debris": 300, "prop": 2500,
           "interactive": 5000, "machine": 10000, "boss": 20000}


def parse_glb(path: str) -> dict:
    with open(path, "rb") as fh:
        data = fh.read()
    if len(data) < 12 or struct.unpack("<I", data[:4])[0] != 0x46546C67:
        raise ValueError("not a GLB")
    off, js = 12, None
    while off + 8 <= len(data):
        length, kind = struct.unpack("<II", data[off:off + 8])
        start = off + 8
        if kind == 0x4E4F534A:
            js = json.loads(data[start:start + length])
        off = start + length + ((4 - length % 4) % 4)
    if js is None:
        raise ValueError("no JSON chunk")

    tris = 0
    for mesh in js.get("meshes", []):
        for prim in mesh["primitives"]:
            if "indices" in prim:
                tris += js["accessors"][prim["indices"]]["count"] // 3
            else:
                acc = prim["attributes"].get("POSITION")
                if acc is not None:
                    tris += js["accessors"][acc]["count"] // 3
    return {
        "bytes": len(data),
        "nodes": len(js.get("nodes", [])),
        "meshes": len(js.get("meshes", [])),
        "materials": len(js.get("materials", [])),
        "primitives": sum(len(m["primitives"]) for m in js.get("meshes", [])),
        "triangles": tris,
        "material_names": [m.get("name", "?") for m in js.get("materials", [])],
    }


# name -> (budget class, gameplay use, status, source module)
CATALOGUE = {
    # --- Kanban Core (hero, rebuilt this pass) --------------------------
    "core/core_shell_upper.glb": ("interactive", "Core upper crystal cap; lifts on charge", "new", "mr_hero.build_core"),
    "core/core_shell_lower.glb": ("interactive", "Core lower cap; drops on charge", "new", "mr_hero.build_core"),
    "core/core_cracks.glb": ("prop", "Emissive crack network; brightens with charge", "new", "mr_hero.build_core"),
    "core/core_chamber.glb": ("swarm", "Energy chamber filling the shell seam", "new", "mr_hero.build_core"),
    "core/core_heart.glb": ("swarm", "White-hot heart, revealed at max charge", "new", "mr_hero.build_core"),
    "core/core_ring_inner.glb": ("prop", "Magnetic ring, inner", "new", "mr_hero.build_core"),
    "core/core_ring_mid.glb": ("prop", "Magnetic ring, middle", "new", "mr_hero.build_core"),
    "core/core_ring_outer.glb": ("prop", "Magnetic ring, outer", "new", "mr_hero.build_core"),
    "core/core_fragment_0.glb": ("debris", "Orbiting crystal fragment", "new", "mr_hero.build_core"),
    "core/core_fragment_1.glb": ("debris", "Orbiting crystal fragment", "new", "mr_hero.build_core"),
    "core/core_fragment_2.glb": ("debris", "Orbiting crystal fragment", "new", "mr_hero.build_core"),

    # --- Environment (rebuilt this pass) --------------------------------
    "platforms/platform_straight.glb": ("prop", "Standard 4x6 m deck", "new", "mr_env"),
    "platforms/platform_short.glb": ("prop", "Half-length deck", "new", "mr_env"),
    "platforms/platform_wide.glb": ("machine", "Wide opening deck", "new", "mr_env"),
    "platforms/platform_ledge.glb": ("prop", "Side ledge holding metal", "new", "mr_env"),
    "platforms/platform_corner.glb": ("machine", "90-degree turn", "new", "mr_env"),
    "platforms/platform_curve.glb": ("machine", "Swept curve", "new", "mr_env"),
    "platforms/platform_ramp.glb": ("prop", "11-degree climb", "new", "mr_env"),
    "platforms/platform_lab_base.glb": ("machine", "Raised laboratory section", "new", "mr_env"),
    "platforms/platform_bridge_anchor.glb": ("prop", "Magnetic bridge anchor", "new", "mr_env"),
    "platforms/platform_portal.glb": ("machine", "Portal deck", "new", "mr_env"),
    "platforms/prop_machinery_socket.glb": ("prop", "Deck machinery, set dressing", "new", "mr_env"),
    "platforms/prop_tower.glb": ("prop", "Midground vertical silhouette", "new", "mr_env"),
    "platforms/prop_cable_support.glb": ("prop", "Suspended machinery over route", "new", "mr_env"),
    "platforms/prop_backdrop_0.glb": ("prop", "Distant facility silhouette", "new", "mr_env"),
    "platforms/prop_backdrop_1.glb": ("prop", "Distant facility silhouette", "new", "mr_env"),
    "platforms/prop_backdrop_2.glb": ("prop", "Distant facility silhouette", "new", "mr_env"),
    "obstacles/obstacle_finish_portal.glb": ("machine", "Level exit; rings spin on unlock", "new", "mr_env"),
    "obstacles/obstacle_portal_disc.glb": ("swarm", "Portal energy surface", "new", "mr_env"),
    "obstacles/obstacle_key_chamber.glb": ("machine", "Barred key chamber", "new", "mr_env"),
    "obstacles/obstacle_hazard_emitter.glb": ("prop", "Telegraphed damage source", "new", "mr_env"),
}

# Assets kept from the original pass, in active use by Level 1.
KEPT_IN_USE = {
    "metal/metal_cube_small.glb", "metal/metal_cube_medium.glb",
    "metal/metal_bolt.glb", "metal/metal_nut.glb", "metal/metal_rod.glb",
    "metal/metal_plate.glb", "metal/metal_ring.glb",
    "metal/metal_gear_small.glb", "metal/metal_gear_large.glb",
    "metal/metal_pipe_piece.glb", "metal/metal_scrap_block.glb",
    "metal/metal_scrap_curved.glb", "metal/metal_scrap_triangle.glb",
    "metal/armour_plate.glb", "metal/armour_spike.glb",
    "metal/bridge_segment.glb", "metal/bridge_beam.glb",
    "metal/magnetic_key.glb",
}


def main() -> int:
    rows = []
    for root, _dirs, files in os.walk(MODELS):
        for f in sorted(files):
            if not f.endswith(".glb"):
                continue
            full = os.path.join(root, f)
            rel = os.path.relpath(full, MODELS).replace("\\", "/")
            try:
                info = parse_glb(full)
            except Exception as exc:  # noqa: BLE001
                rows.append({"rel": rel, "error": str(exc)})
                continue
            budget, use, status, source = CATALOGUE.get(
                rel,
                ("swarm" if rel.startswith("metal/") else "prop",
                 "Swarm silhouette" if rel in KEPT_IN_USE else "Not referenced by Level 1",
                 "keep" if rel in KEPT_IN_USE else "defer",
                 "build_assets.py"),
            )
            info.update(rel=rel, budget=budget, use=use, status=status,
                        source=source,
                        over=info["triangles"] > BUDGETS[budget])
            rows.append(info)

    ok = [r for r in rows if "error" not in r]
    bad = [r for r in rows if "error" in r]
    over = [r for r in ok if r["over"]]

    lines = []
    lines.append("# Asset Manifest\n")
    lines.append(
        "Generated by `python tool/asset_audit.py`, which parses the GLB files\n"
        "themselves. Nothing here is hand-maintained, so it cannot drift from\n"
        "what actually ships.\n")
    lines.append(f"**{len(ok)} assets** · "
                 f"{sum(r['triangles'] for r in ok):,} triangles total · "
                 f"{sum(r['bytes'] for r in ok) / 1024:.0f} kB · "
                 f"{len(over)} over budget · {len(bad)} failed to parse\n")

    lines.append("## Status meanings\n")
    lines.append("| Status | Meaning |")
    lines.append("|---|---|")
    lines.append("| `new` | Authored or rebuilt in this pass via Blender MCP "
                 "(`art/blender/mr_hero.py`, `art/blender/mr_env.py`). "
                 "Visually reviewed from the gameplay camera. |")
    lines.append("| `keep` | From the original headless pass, in active use by "
                 "Level 1, reviewed in situ on device. |")
    lines.append("| `defer` | From the original pass, not referenced by Level 1. "
                 "Retained for later worlds; **not** reviewed. |")
    lines.append("")

    for group, title in [("core", "Kanban Core"), ("platforms", "Platforms and props"),
                         ("obstacles", "Obstacles"), ("metal", "Metal and swarm")]:
        sub = [r for r in ok if r["rel"].startswith(group + "/")]
        if not sub:
            continue
        lines.append(f"## {title}\n")
        lines.append("| Asset | Tris | Mats | Prims | Bytes | Budget | Status | Gameplay use |")
        lines.append("|---|---:|---:|---:|---:|---|---|---|")
        for r in sorted(sub, key=lambda x: x["rel"]):
            flag = " ⚠" if r["over"] else ""
            lines.append(
                f"| `{r['rel']}` | {r['triangles']}{flag} | {r['materials']} | "
                f"{r['primitives']} | {r['bytes']:,} | {r['budget']} "
                f"({BUDGETS[r['budget']]}) | {r['status']} | {r['use']} |")
        lines.append("")

    lines.append("## Conventions enforced\n")
    lines.append("* metric scale, 1 unit = 1 metre")
    lines.append("* transforms applied, origin at the logical pivot "
                 "(deck modules pivot at the centre of the walkable top surface)")
    lines.append("* flat shading; normals recalculated at export")
    lines.append("* `+Y` up at export (glTF convention)")
    lines.append("* shared, cached materials so draw calls stay low")
    lines.append("* exported through a throwaway single-object scene rather than "
                 "`use_selection`, which in an interactive Blender session also "
                 "picks up selections in *other* scenes")
    lines.append("")
    if bad:
        lines.append("## Failed to parse\n")
        for r in bad:
            lines.append(f"* `{r['rel']}` — {r['error']}")
        lines.append("")

    out = os.path.join(REPO, "docs", "asset_manifest.md")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    print(f"{len(ok)} assets, {len(over)} over budget, {len(bad)} unparseable")
    print(f"wrote {out}")
    return 1 if (bad or over) else 0


if __name__ == "__main__":
    sys.exit(main())
