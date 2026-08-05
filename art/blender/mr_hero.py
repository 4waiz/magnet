"""Magnet Rush — hero asset authoring.

Extends `mr_kit` with the shape vocabulary the premium look needs: asymmetric
faceted crystals, emissive crack networks, mechanical rings, chamfered platform
decks with circuit insets, and greeble.

Unlike `build_assets.py` this module is designed to be driven from an
*interactive* Blender session (Blender MCP) so hero assets can be rendered and
visually reviewed from the gameplay camera before export. It therefore never
calls `read_factory_settings` — it works inside a dedicated `MR_Build` scene and
leaves any other scene in the file untouched.

    # from Blender MCP
    import mr_hero; mr_hero.build_all()
"""

from __future__ import annotations

import json
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import mr_kit as K

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(REPO, "assets", "models")
BUILD_SCENE = "MR_Build"

# The equatorial split in the Core shell. The runtime widens the gap as charge
# rises, so these are shared constants rather than magic numbers.
#
# Placed at the crystal's widest point, not below it: the gameplay camera looks
# *down* at roughly 30 degrees, and a seam set lower is completely occluded by
# the upper cap's overhang. The gap also has to be a meaningful fraction of the
# 1.0 m diameter or it reads as a crack rather than a containment field.
CORE_SEAM_GAP = 0.150
CORE_SEAM_Z = 0.045

# The seam plane is tilted rather than horizontal. A level cut viewed from the
# elevated gameplay camera shows only as a symmetric crescent along the bottom
# silhouette — it reads as a grin. Tilting it lifts one side into view, makes
# the split visible from above, and satisfies the asymmetry the art direction
# asks for.
CORE_SEAM_NORMAL = (0.30, 0.16, 1.0)

# Chamber disc: flush with the shell wall so the glow fills the seam edge-on.
CORE_CHAMBER_RADIUS = 0.505
CORE_CHAMBER_SQUASH_Z = 0.16

# Ring rest orientations (Euler XY). Differing on both axes is what makes the
# three rings read as a gyroscopic cage instead of concentric hoops.
CORE_RING_AXES = {
    "inner": (0.14, 0.06),
    "mid": (1.02, 0.34),
    "outer": (0.52, -1.18),
}


# ---------------------------------------------------------------------------
# Non-destructive scene handling
# ---------------------------------------------------------------------------


def use_build_scene() -> bpy.types.Scene:
    """Activates (creating if needed) the isolated build scene.

    Deliberately does *not* wipe the file: an interactive Blender session may
    hold unsaved work in other scenes.
    """
    sc = bpy.data.scenes.get(BUILD_SCENE)
    if sc is None:
        sc = bpy.data.scenes.new(BUILD_SCENE)
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    for win in bpy.context.window_manager.windows:
        win.scene = sc
    return sc


def clear_build_scene() -> None:
    """Removes only objects owned by the build scene."""
    sc = use_build_scene()
    for obj in list(sc.collection.objects):
        sc.collection.objects.unlink(obj)
        if obj.users == 0:
            bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def link(obj: bpy.types.Object) -> bpy.types.Object:
    """Links into the build scene explicitly (MCP has no reliable context)."""
    sc = bpy.data.scenes.get(BUILD_SCENE) or use_build_scene()
    for coll in list(obj.users_collection):
        coll.objects.unlink(obj)
    sc.collection.objects.link(obj)
    return obj


def _adopt(obj: bpy.types.Object) -> bpy.types.Object:
    """mr_kit builders link into bpy.context.collection; re-home into ours."""
    return link(obj)


# ---------------------------------------------------------------------------
# Shape vocabulary
# ---------------------------------------------------------------------------


def _fill_open_edges(bm) -> None:
    open_edges = [e for e in bm.edges if len(e.link_faces) == 1]
    if open_edges:
        bmesh.ops.holes_fill(bm, edges=open_edges)


def _asym_crystal_bm(
    radius: float,
    subdiv: int,
    *,
    seed: int,
    jitter: float,
    squash,
    facet_planes: int,
    facet_bite: float,
):
    """The shared crystal body: a jittered icosphere with planes sliced off.

    The plane cuts are what separate a *crystal* from a lumpy rock: they
    produce large flat faces that catch the key light cleanly, which is what
    makes the silhouette read at phone scale.
    """
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)

    for v in bm.verts:
        v.co.x *= squash[0]
        v.co.y *= squash[1]
        v.co.z *= squash[2]
        v.co *= 1.0 + rng.uniform(-jitter, jitter)

    for _ in range(facet_planes):
        n = Vector(
            (rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.7, 1.0))
        ).normalized()
        d = radius * rng.uniform(facet_bite, facet_bite + 0.12)
        bmesh.ops.bisect_plane(
            bm,
            geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
            plane_co=n * d, plane_no=n, clear_outer=True,
        )
        _fill_open_edges(bm)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _finish(bm, name: str, mat=None) -> bpy.types.Object:
    bmesh.ops.triangulate(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    link(obj)
    K.flat_shade(obj)
    if mat:
        K.assign(obj, mat)
    return obj


def asym_crystal(
    name: str,
    radius: float = 0.5,
    subdiv: int = 1,
    *,
    seed: int = 11,
    jitter: float = 0.20,
    squash=(1.0, 1.0, 1.12),
    facet_planes: int = 5,
    facet_bite: float = 0.86,
    mat=None,
) -> bpy.types.Object:
    """An asymmetric faceted crystal."""
    bm = _asym_crystal_bm(radius, subdiv, seed=seed, jitter=jitter,
                          squash=squash, facet_planes=facet_planes,
                          facet_bite=facet_bite)
    return _finish(bm, name, mat)


def crystal_caps(
    name: str,
    radius: float = 0.5,
    subdiv: int = 2,
    *,
    seed: int = 17,
    jitter: float = 0.14,
    squash=(0.96, 0.94, 1.14),
    facet_planes: int = 6,
    facet_bite: float = 0.80,
    gap: float = 0.085,
    seam_z: float = -0.05,
    seam_normal=(0.0, 0.0, 1.0),
) -> tuple[bpy.types.Object, bpy.types.Object]:
    """Splits one crystal into an upper and a lower cap with a gap between.

    A solid shell hides the energy chamber completely, which is why the first
    pass read as an opaque blue rock. Splitting the shell leaves a bright
    equatorial seam the chamber glows through, so 'contained energy' is
    legible in a single frame without any transparency.
    """
    n = Vector(seam_normal).normalized()

    def cut(keep_upper: bool):
        bm = _asym_crystal_bm(radius, subdiv, seed=seed, jitter=jitter,
                              squash=squash, facet_planes=facet_planes,
                              facet_bite=facet_bite)
        d = seam_z + (gap * 0.5 if keep_upper else -gap * 0.5)
        bmesh.ops.bisect_plane(
            bm,
            geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
            plane_co=n * d, plane_no=n,
            clear_outer=not keep_upper, clear_inner=keep_upper,
        )
        _fill_open_edges(bm)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return bm

    upper = _finish(cut(True), f"{name}_upper")
    lower = _finish(cut(False), f"{name}_lower")
    return upper, lower


def _place_on_seam(obj: bpy.types.Object) -> bpy.types.Object:
    """Aligns an object to the tilted seam plane and slides it onto the cut."""
    n = Vector(CORE_SEAM_NORMAL).normalized()
    obj.rotation_euler = n.to_track_quat("Z", "Y").to_euler()
    obj.location = n * CORE_SEAM_Z
    return obj


def shade_by_height(
    obj: bpy.types.Object,
    top_mat: bpy.types.Material,
    bottom_mat: bpy.types.Material,
    *,
    split: float = 0.02,
    rear_bias: float = 0.0,
) -> bpy.types.Object:
    """Assigns two materials by face orientation.

    The art direction calls for darker blue lower and rear faces so the Core
    does not read as a uniform glowing ball. Doing it by face normal keeps it
    to two material slots (two primitives) rather than a texture.
    """
    obj.data.materials.clear()
    obj.data.materials.append(top_mat)
    obj.data.materials.append(bottom_mat)
    for poly in obj.data.polygons:
        n = poly.normal
        score = n.z + rear_bias * n.y
        poly.material_index = 0 if score > split else 1
    return obj


def crack_network(
    name: str,
    source: bpy.types.Object,
    *,
    count: int = 9,
    width: float = 0.018,
    inflate: float = 1.008,
    seed: int = 3,
    mat=None,
) -> bpy.types.Object:
    """Emissive cracks that follow the crystal's own edges.

    Picks edges from the shell, offsets them fractionally outward, and gives
    them a little width so they render as glowing seams sitting *in* the
    surface rather than as decals floating over it.
    """
    rng = random.Random(seed)
    src = bmesh.new()
    src.from_mesh(source.data)
    src.edges.ensure_lookup_table()
    edges = [e for e in src.edges if e.calc_length() > 0.06]
    rng.shuffle(edges)
    picked = edges[: max(1, count)]

    out = bmesh.new()
    for e in picked:
        a = e.verts[0].co.copy() * inflate
        b = e.verts[1].co.copy() * inflate
        axis = (b - a)
        if axis.length < 1e-5:
            continue
        axis.normalize()
        # A stable perpendicular, then a second one, to build a thin quad tube.
        ref = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
        u = axis.cross(ref).normalized() * width
        v = axis.cross(u).normalized() * width
        ring_a = [out.verts.new(a + u), out.verts.new(a + v),
                  out.verts.new(a - u), out.verts.new(a - v)]
        ring_b = [out.verts.new(b + u), out.verts.new(b + v),
                  out.verts.new(b - u), out.verts.new(b - v)]
        for i in range(4):
            j = (i + 1) % 4
            try:
                out.faces.new((ring_a[i], ring_a[j], ring_b[j], ring_b[i]))
            except ValueError:
                pass
    src.free()
    bmesh.ops.recalc_face_normals(out, faces=out.faces)

    mesh = bpy.data.meshes.new(name)
    out.to_mesh(mesh)
    out.free()
    obj = bpy.data.objects.new(name, mesh)
    link(obj)
    K.flat_shade(obj)
    if mat:
        K.assign(obj, mat)
    return obj


def ring_with_clamps(
    name: str,
    *,
    major: float = 0.7,
    minor: float = 0.022,
    segments: int = 22,
    clamps: int = 6,
    clamp_size=(0.05, 0.05, 0.035),
    tilt: float = 0.0,
    ring_mat=None,
    clamp_mat=None,
) -> bpy.types.Object:
    """A thin energy ring carrying small mechanical clamps.

    The clamps are the detail that stops the rings reading as bare circles;
    they also give the eye something to track when the ring spins.
    """
    parts = []
    ring = K.torus(
        f"{name}_band", major=major, minor=minor,
        major_seg=segments, minor_seg=4, mat=ring_mat,
    )
    _adopt(ring)
    parts.append(ring)

    for i in range(clamps):
        a = (i / max(1, clamps)) * math.tau
        cx, cy = math.cos(a) * major, math.sin(a) * major
        blk = K.box(
            f"{name}_clamp{i}",
            clamp_size[0], clamp_size[1], clamp_size[2],
            at=(cx, cy, 0.0), mat=clamp_mat,
        )
        _adopt(blk)
        blk.rotation_euler = (0.0, 0.0, a)
        parts.append(blk)

    obj = K.join(parts, name)
    _adopt(obj)
    if abs(tilt) > 1e-6:
        obj.rotation_euler = (tilt, 0.0, 0.0)
        K.apply_transforms(obj)
    return obj


def shard(name: str, size: float = 0.09, *, seed: int = 1, mat=None):
    """A small angular crystal fragment."""
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=0, radius=size)
    for v in bm.verts:
        v.co.x *= rng.uniform(0.5, 1.3)
        v.co.y *= rng.uniform(0.5, 1.3)
        v.co.z *= rng.uniform(0.9, 2.0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    link(obj)
    K.flat_shade(obj)
    if mat:
        K.assign(obj, mat)
    return obj


def deck(
    name: str,
    hx: float,
    hy: float,
    *,
    thickness: float = 0.34,
    chamfer: float = 0.07,
    top_mat=None,
    body_mat=None,
) -> list[bpy.types.Object]:
    """A chamfered platform deck: bright top slab over a darker body.

    [hx] and [hy] are HALF-extents, matching how level data addresses modules.
    `mr_kit.box`/`bevel_plate` take full extents, so they are doubled here —
    conflating the two made every circuit line and greeble block overhang its
    deck by 2x in the first environment pass.

    Returns the parts unjoined so callers can add circuits and understructure
    before merging.
    """
    parts = []
    top = K.bevel_plate(
        f"{name}_top", hx * 2.0, hy * 2.0, 0.06, cut=chamfer,
        at=(0, 0, -0.03), mat=top_mat,
    )
    _adopt(top)
    parts.append(top)

    body = K.bevel_plate(
        f"{name}_body", hx * 1.88, hy * 1.88, thickness, cut=chamfer * 1.4,
        at=(0, 0, -0.06 - thickness * 0.5), mat=body_mat,
    )
    _adopt(body)
    parts.append(body)
    return parts


def circuit_inset(
    name: str,
    points: list[tuple[float, float]],
    *,
    width: float = 0.035,
    z: float = 0.005,
    mat=None,
) -> bpy.types.Object:
    """A glowing channel strip laid across a deck top."""
    bm = bmesh.new()
    for i in range(len(points) - 1):
        ax, ay = points[i]
        bx, by = points[i + 1]
        d = Vector((bx - ax, by - ay, 0.0))
        if d.length < 1e-6:
            continue
        d.normalize()
        n = Vector((-d.y, d.x, 0.0)) * width
        v0 = bm.verts.new((ax + n.x, ay + n.y, z))
        v1 = bm.verts.new((bx + n.x, by + n.y, z))
        v2 = bm.verts.new((bx - n.x, by - n.y, z))
        v3 = bm.verts.new((ax - n.x, ay - n.y, z))
        try:
            bm.faces.new((v0, v1, v2, v3))
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    link(obj)
    K.flat_shade(obj)
    if mat:
        K.assign(obj, mat)
    return obj


def understructure(
    name: str,
    hx: float,
    hy: float,
    *,
    seed: int = 5,
    depth: float = 1.5,
    ribs: int = 4,
    mat=None,
) -> list[bpy.types.Object]:
    """Machinery hanging beneath a platform. [hx]/[hy] are half-extents.

    Section 7 asks for undersides that are visible over gaps — without this a
    floating platform reads as a flat card the moment the camera sees its edge.
    """
    rng = random.Random(seed)
    parts = []
    for i in range(ribs):
        t = (i + 0.5) / ribs
        x = (t - 0.5) * hx * 1.55
        h = depth * rng.uniform(0.45, 1.0)
        w = rng.uniform(0.10, 0.20)
        blk = K.box(
            f"{name}_rib{i}", w, hy * rng.uniform(0.45, 1.05), h,
            at=(x, rng.uniform(-0.3, 0.3) * hy, -0.4 - h * 0.5), mat=mat,
        )
        _adopt(blk)
        parts.append(blk)
    spine = K.box(
        f"{name}_spine", hx * 1.5, 0.12, 0.14, at=(0, 0, -0.42), mat=mat,
    )
    _adopt(spine)
    parts.append(spine)
    return parts


def greeble(
    name: str,
    hx: float,
    hy: float,
    *,
    count: int = 10,
    seed: int = 2,
    z: float = 0.0,
    mat=None,
) -> list[bpy.types.Object]:
    """Scattered surface detail — vents, hatches, conduit boxes.

    [hx]/[hy] are half-extents; blocks stay inside 0.82 of them so nothing
    hangs over a deck edge.
    """
    rng = random.Random(seed)
    parts = []
    for i in range(count):
        w = rng.uniform(0.10, 0.34)
        d = rng.uniform(0.10, 0.34)
        h = rng.uniform(0.03, 0.11)
        x = rng.uniform(-0.82, 0.82) * hx
        y = rng.uniform(-0.82, 0.82) * hy
        blk = K.box(f"{name}_g{i}", w, d, h, at=(x, y, z + h * 0.5), mat=mat)
        _adopt(blk)
        parts.append(blk)
    return parts


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

RECORDS: list[dict] = []


EXPORT_SCENE = "MR_Export"


def emit(obj, rel_path: str, *, budget: str, purpose: str, collider: str,
         review: str = "pending") -> dict:
    """Exports exactly one object to GLB.

    Uses a throwaway single-object scene rather than `use_selection`. In an
    interactive session `use_selection` also picks up whatever is selected in
    *other* scenes' view layers — during development that silently welded a
    stray 480-triangle prop from an unrelated open project into every Core
    part. An isolated scene cannot be contaminated by selection state.
    """
    path = os.path.join(OUT, rel_path.replace("/", os.sep))
    os.makedirs(os.path.dirname(path), exist_ok=True)

    K.recalc_normals(obj)
    K.apply_transforms(obj)

    ex = bpy.data.scenes.get(EXPORT_SCENE)
    if ex is None:
        ex = bpy.data.scenes.new(EXPORT_SCENE)
        ex.unit_settings.system = "METRIC"
    for o in list(ex.collection.objects):
        ex.collection.objects.unlink(o)
    ex.collection.objects.link(obj)

    win = bpy.context.window
    prev = win.scene
    win.scene = ex
    try:
        bpy.ops.export_scene.gltf(
            filepath=path,
            export_format="GLB",
            use_selection=False,
            use_active_scene=True,
            export_apply=True,
            export_yup=True,
            export_normals=True,
            export_materials="EXPORT",
            export_cameras=False,
            export_lights=False,
        )
    finally:
        win.scene = prev
        if obj.name in ex.collection.objects:
            ex.collection.objects.unlink(obj)

    tris = K.triangle_count(obj)
    limit = K.BUDGETS[budget]
    rec = {
        "name": obj.name,
        "glb": "assets/models/" + rel_path,
        "source": "art/blender/mr_hero.py",
        "triangles": tris,
        "materials": len([m for m in obj.data.materials if m is not None]),
        "bytes": os.path.getsize(path) if os.path.exists(path) else 0,
        "budget_class": budget,
        "purpose": purpose,
        "collider": collider,
        "over_budget": tris > limit,
        "review": review,
    }
    RECORDS.append(rec)
    flag = " !! OVER BUDGET" if rec["over_budget"] else ""
    print(f"  {rel_path:46s} {tris:6d} tris  {rec['bytes']:7d} B{flag}")
    return rec


def write_index(path: str | None = None) -> str:
    path = path or os.path.join(os.path.dirname(__file__), "hero_index.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(RECORDS, fh, indent=2)
    return path


# ---------------------------------------------------------------------------
# Visual review
# ---------------------------------------------------------------------------


def setup_review(
    out_path: str,
    *,
    target=(0.0, 0.0, 0.0),
    distance: float = 9.0,
    height: float = 5.4,
    lens: float = 44.0,
    res=(720, 1280),
    samples: int = 24,
) -> str:
    """Renders the build scene from the *gameplay* camera angle.

    Assets are approved or rejected on how they read in the shot the player
    actually sees — an elevated three-quarter portrait view — not from a
    convenient orbit in the viewport. Defaults mirror the runtime camera in
    `lib/game/camera/`.
    """
    sc = use_build_scene()
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    try:
        sc.eevee.taa_render_samples = samples
    except AttributeError:
        pass
    sc.view_settings.view_transform = "Standard"

    world = bpy.data.worlds.get("MR_ReviewWorld") or bpy.data.worlds.new("MR_ReviewWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.012, 0.020, 0.045, 1.0)
        bg.inputs[1].default_value = 1.0
    sc.world = world

    for name in ("MR_RevCam", "MR_KeyLight", "MR_RimLight", "MR_FillLight"):
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)

    cam_data = bpy.data.cameras.new("MR_RevCamData")
    cam_data.lens = lens
    cam = bpy.data.objects.new("MR_RevCam", cam_data)
    link(cam)
    tv = Vector(target)
    cam.location = tv + Vector((0.0, -distance, height))
    direction = tv - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam

    def add_light(name, kind, energy, color, loc, angle=None):
        d = bpy.data.lights.new(name + "Data", type=kind)
        d.energy = energy
        d.color = color
        if kind == "SUN" and angle is not None:
            d.angle = angle
        o = bpy.data.objects.new(name, d)
        link(o)
        o.location = loc
        d2 = tv - Vector(loc)
        o.rotation_euler = d2.to_track_quat("-Z", "Y").to_euler()
        return o

    # Cool key from high front-left, blue rim from behind, soft fill.
    add_light("MR_KeyLight", "SUN", 3.2, (0.80, 0.90, 1.00), (-5, -6, 8), angle=0.3)
    add_light("MR_RimLight", "AREA", 420.0, (0.25, 0.65, 1.00), (4.5, 5.0, 3.2))
    add_light("MR_FillLight", "AREA", 90.0, (0.35, 0.50, 0.85), (5.0, -4.0, 1.0))

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    sc.render.filepath = out_path
    sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    return out_path


def assemble_core_preview() -> list[bpy.types.Object]:
    """Rebuilds every Core part in place so the assembly can be reviewed."""
    M = hero_materials()
    use_build_scene()
    clear_build_scene()

    parts = []
    upper, lower = crystal_caps("rev_shell", radius=0.50, subdiv=2, seed=17,
                                jitter=0.135, squash=(0.96, 0.94, 1.15),
                                facet_planes=6, facet_bite=0.78,
                                gap=CORE_SEAM_GAP, seam_z=CORE_SEAM_Z,
                                seam_normal=CORE_SEAM_NORMAL)
    shade_by_height(upper, M["crystal_lit"], M["crystal_deep"],
                    split=-0.30, rear_bias=0.45)
    K.assign(lower, M["crystal_deep"])
    parts += [upper, lower]

    ref = asym_crystal("rev_ref", radius=0.50, subdiv=2, seed=17, jitter=0.135,
                       squash=(0.96, 0.94, 1.15), facet_planes=6,
                       facet_bite=0.78)
    parts.append(crack_network("rev_cracks", ref, count=15, width=0.0135,
                               inflate=1.014, seed=5, mat=M["crack"]))
    bpy.data.objects.remove(ref, do_unlink=True)

    ch = asym_crystal("rev_chamber", radius=CORE_CHAMBER_RADIUS, subdiv=1,
                      seed=41, jitter=0.08,
                      squash=(1.0, 1.0, CORE_CHAMBER_SQUASH_Z),
                      facet_planes=2, facet_bite=0.94, mat=M["chamber"])
    _place_on_seam(ch)
    parts.append(ch)

    for key, major, minor, seg, clamps, csize in [
        ("inner", 0.620, 0.0165, 24, 6, (0.046, 0.046, 0.032)),
        ("mid", 0.740, 0.0135, 26, 5, (0.040, 0.040, 0.028)),
        ("outer", 0.880, 0.0110, 28, 4, (0.034, 0.034, 0.024)),
    ]:
        r = ring_with_clamps(f"rev_ring_{key}", major=major, minor=minor,
                             segments=seg, clamps=clamps, clamp_size=csize,
                             ring_mat=M["ring_energy"],
                             clamp_mat=M["ring_mech"])
        ax = CORE_RING_AXES[key]
        r.rotation_euler = (ax[0], ax[1], 0.0)
        parts.append(r)

    rig_frags = [(0.74, 0.20, 0.0), (0.82, -0.14, 2.1), (0.68, 0.30, 4.2)]
    for i, (rad, hgt, phase) in enumerate(rig_frags):
        f = shard(f"rev_frag_{i}", size=0.070 + i * 0.016, seed=90 + i * 7,
                  mat=M["crystal_lit"])
        f.location = (math.cos(phase) * rad, math.sin(phase) * rad, hgt)
        parts.append(f)
    return parts


# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------


def hero_materials() -> dict:
    """The restricted palette from the art direction.

    Deliberately small: bright cyan, electric blue, deep navy, white-hot
    highlights, and a little silver. Everything else is a hazard colour and
    must stay rare so orange keeps meaning 'this will hurt you'.
    """
    return {
        # Core. Emission is kept low on the *shell* on purpose: the first pass
        # pushed it to 2.4 and the crystal blew out to near-white, which threw
        # away the electric-blue identity and flattened every facet. Only the
        # chamber and the seams are allowed to be hot.
        # Emission was first tuned against a Blender EEVEE preview using the
        # Standard view transform, where anything above ~1.0 clipped to white.
        # The runtime is far darker (environmentIntensity 0.16), so those
        # values rendered the Core as a dull blue lump with only its rings
        # visible. These are tuned against the *device*, which is the only
        # view that matters.
        "crystal_lit": K.material(
            "MR_CrystalLit", (0.10, 0.42, 1.00), metallic=0.10, roughness=0.18,
            emission=(0.10, 0.46, 1.00), emission_strength=2.4,
        ),
        "crystal_deep": K.material(
            "MR_CrystalDeep", (0.012, 0.050, 0.230), metallic=0.20,
            roughness=0.48, emission=(0.02, 0.10, 0.38),
            emission_strength=0.55,
        ),
        "chamber": K.material(
            "MR_Chamber", (0.80, 0.98, 1.00), metallic=0.0, roughness=0.05,
            emission=(0.76, 0.98, 1.00), emission_strength=26.0,
        ),
        "crack": K.material(
            "MR_Crack", (0.16, 0.78, 1.00), metallic=0.0, roughness=0.10,
            emission=(0.14, 0.84, 1.00), emission_strength=6.5,
        ),
        "ring_energy": K.material(
            "MR_RingEnergy", K.CYAN, metallic=0.0, roughness=0.12,
            emission=(0.16, 0.84, 1.00), emission_strength=5.5,
        ),
        "ring_mech": K.material(
            "MR_RingMech", (0.62, 0.70, 0.80), metallic=0.95, roughness=0.28,
        ),
        # Environment
        # Environment. Kept deliberately dark: the Core must be the brightest
        # thing on screen, and a light-grey deck competes with it directly.
        # Metallic is kept LOW on structural surfaces. A metallic surface takes
        # its colour from the environment probe rather than from its base
        # colour, so decks authored at 0.45-0.80 metallic rendered as bright
        # reflective grey on device and threw away the dark navy entirely.
        "deck_top": K.material(
            "MR_DeckTop", (0.105, 0.130, 0.185), metallic=0.06, roughness=0.72,
        ),
        "deck_body": K.material(
            "MR_DeckBody", (0.048, 0.060, 0.092), metallic=0.05, roughness=0.80,
        ),
        "deck_mech": K.material(
            "MR_DeckMech", (0.075, 0.090, 0.130), metallic=0.25, roughness=0.55,
        ),
        # Emission at 7.0 clipped straight to white and lost the colour that
        # carries the cyan-is-safe / orange-is-danger rule.
        "circuit": K.material(
            "MR_CircuitLine", (0.06, 0.55, 0.78), metallic=0.0, roughness=0.2,
            emission=(0.05, 0.62, 0.92), emission_strength=2.4,
        ),
        "hazard_line": K.material(
            "MR_HazardLine", (0.85, 0.30, 0.05), metallic=0.1, roughness=0.35,
            emission=(0.95, 0.34, 0.05), emission_strength=2.8,
        ),
        # Loose metal stays genuinely metallic — it is meant to catch the light
        # and separate from the structure it is torn out of.
        "metal": K.material(
            "MR_MetalBright", (0.60, 0.66, 0.78), metallic=0.85, roughness=0.32,
        ),
        "metal_dark": K.material(
            "MR_MetalDim", (0.24, 0.28, 0.36), metallic=0.55, roughness=0.55,
        ),
        "backdrop": K.material(
            "MR_Backdrop", (0.028, 0.038, 0.070), metallic=0.0, roughness=0.95,
        ),
        "gold": K.material(
            "MR_KeyGold", K.AMBER, metallic=1.0, roughness=0.20,
            emission=K.AMBER, emission_strength=3.5,
        ),
        "portal": K.material(
            "MR_PortalEnergy", (0.30, 0.92, 1.00), metallic=0.0, roughness=0.1,
            emission=(0.45, 0.95, 1.00), emission_strength=14.0,
        ),
    }


# ---------------------------------------------------------------------------
# The Kanban Core — hero asset
# ---------------------------------------------------------------------------


def build_core(M: dict | None = None) -> dict:
    """Builds the Core as *separable animated parts*, not one welded blob.

    The previous `kanban_core.glb` joined shell + inner + ring into a single
    mesh, which is exactly why it read as a plain blue rock: nothing could
    move independently. Each part is exported on its own so the runtime can
    spin the rings at different rates, pulse the chamber, brighten the cracks
    with charge, and throw the fragments outward on release.
    """
    M = M or hero_materials()
    use_build_scene()
    clear_build_scene()
    print("[core]")

    # --- Split outer shell -------------------------------------------------
    # Two caps with a gap, not one solid ball. See crystal_caps().
    upper, lower = crystal_caps(
        "core_shell", radius=0.50, subdiv=2, seed=17, jitter=0.135,
        squash=(0.96, 0.94, 1.15), facet_planes=6, facet_bite=0.78,
        gap=CORE_SEAM_GAP, seam_z=CORE_SEAM_Z,
        seam_normal=CORE_SEAM_NORMAL,
    )
    shade_by_height(upper, M["crystal_lit"], M["crystal_deep"],
                    split=-0.30, rear_bias=0.45)
    shell_rec = emit(
        upper, "core/core_shell_upper.glb", budget="interactive",
        purpose="Core upper crystal cap; bright front faces and deep navy "
                "rear faces as two primitives. Lifts on charge.",
        collider="sphere r=0.50",
    )
    K.assign(lower, M["crystal_deep"])
    emit(lower, "core/core_shell_lower.glb", budget="interactive",
         purpose="Core lower crystal cap; deep navy, drops on charge to widen "
                 "the energy seam",
         collider="none")

    # --- Emissive cracks ---------------------------------------------------
    # Rebuilt from an identical crystal so the seams track the shell's edges.
    ref = asym_crystal(
        "core_shell_ref", radius=0.50, subdiv=2, seed=17, jitter=0.135,
        squash=(0.96, 0.94, 1.15), facet_planes=6, facet_bite=0.78,
    )
    cracks = crack_network(
        "core_cracks", ref, count=15, width=0.0135, inflate=1.014,
        seed=5, mat=M["crack"],
    )
    bpy.data.objects.remove(ref, do_unlink=True)
    emit(cracks, "core/core_cracks.glb", budget="prop",
         purpose="Cyan emissive crack network; brightens with charge",
         collider="none")

    # --- Inner energy chamber ---------------------------------------------
    # A flattened disc that *fills* the seam rather than a small sphere buried
    # inside it. A sphere at r=0.395 sat 0.1 m behind the shell wall and was
    # completely invisible edge-on from the gameplay camera; this reads as a
    # bright energy belt from every angle.
    chamber = asym_crystal(
        "core_chamber", radius=CORE_CHAMBER_RADIUS, subdiv=1, seed=41,
        jitter=0.08, squash=(1.0, 1.0, CORE_CHAMBER_SQUASH_Z),
        facet_planes=2, facet_bite=0.94, mat=M["chamber"],
    )
    _place_on_seam(chamber)
    emit(chamber, "core/core_chamber.glb", budget="swarm",
         purpose="Inner energy chamber; fills the shell seam, scale and "
                 "emissive pulse with charge",
         collider="none")

    # A small hot heart, visible once the seam opens wide at high charge.
    heart = asym_crystal(
        "core_heart", radius=0.21, subdiv=1, seed=63, jitter=0.24,
        squash=(1.0, 1.0, 1.1), facet_planes=3, facet_bite=0.82,
        mat=M["chamber"],
    )
    _place_on_seam(heart)
    emit(heart, "core/core_heart.glb", budget="swarm",
         purpose="White-hot inner heart; revealed when the seam opens at "
                 "maximum charge",
         collider="none")

    # --- Magnetic rings ----------------------------------------------------
    # Radii sit just outside the shell so the crystal stays the dominant mass.
    # Axes differ on both X and Y so the three rings read as a gyroscopic cage
    # rather than as concentric flat hoops.
    for key, major, minor, seg, clamps, csize in [
        ("inner", 0.620, 0.0165, 24, 6, (0.046, 0.046, 0.032)),
        ("mid", 0.740, 0.0135, 26, 5, (0.040, 0.040, 0.028)),
        ("outer", 0.880, 0.0110, 28, 4, (0.034, 0.034, 0.024)),
    ]:
        ring = ring_with_clamps(
            f"core_ring_{key}", major=major, minor=minor, segments=seg,
            clamps=clamps, clamp_size=csize,
            ring_mat=M["ring_energy"], clamp_mat=M["ring_mech"],
        )
        emit(ring, f"core/core_ring_{key}.glb", budget="prop",
             purpose=f"Magnetic ring ({key}); independent spin axis and rate",
             collider="none")

    # --- Floating crystal fragments ---------------------------------------
    for i in range(3):
        frag = shard(f"core_fragment_{i}", size=0.070 + i * 0.016,
                     seed=90 + i * 7, mat=M["crystal_lit"])
        emit(frag, f"core/core_fragment_{i}.glb", budget="debris",
             purpose="Floating crystal fragment; pulled in while attracting, "
                     "thrown out on release",
             collider="none")

    # --- Rig ---------------------------------------------------------------
    # Attachment data the runtime needs. Exported as JSON rather than as glTF
    # empties because the runtime importer discards nodes without meshes.
    rig = {
        "unit": "metre",
        "collision_proxy": {"type": "sphere", "radius": 0.50,
                            "centre": [0.0, 0.0, 0.0]},
        "orbit_layers": [
            {"name": "inner_fast", "radius": 1.02, "height": 0.00,
             "speed": 2.55, "slots": 14, "tilt": 0.10},
            {"name": "mid_armour", "radius": 1.46, "height": 0.08,
             "speed": -1.70, "slots": 20, "tilt": 0.42},
            {"name": "outer_scrap", "radius": 1.96, "height": -0.06,
             "speed": 1.15, "slots": 28, "tilt": 0.78},
        ],
        "special_slots": {
            "magnetic_key": {"radius": 1.24, "height": 0.34, "speed": 1.9},
        },
        "trail_points": [
            [0.0, 0.0, -0.34], [0.30, -0.10, -0.22], [-0.30, -0.10, -0.22],
        ],
        "field_line_anchors": [
            [0.0, 0.52, 0.0], [0.0, -0.52, 0.0],
            [0.46, 0.16, 0.16], [-0.46, 0.16, 0.16],
            [0.46, -0.16, -0.16], [-0.46, -0.16, -0.16],
            [0.0, 0.20, 0.50], [0.0, -0.20, -0.50],
        ],
        "seam": {"gap": CORE_SEAM_GAP, "z": CORE_SEAM_Z,
                 "max_open": CORE_SEAM_GAP * 2.6},
        "ring_axes": {k: [v[0], v[1]] for k, v in CORE_RING_AXES.items()},
        "ring_speeds": {"inner": 1.35, "mid": -0.95, "outer": 0.62},
        "fragment_orbits": [
            {"radius": 0.74, "height": 0.20, "speed": 0.85, "phase": 0.0},
            {"radius": 0.82, "height": -0.14, "speed": -0.62, "phase": 2.1},
            {"radius": 0.68, "height": 0.30, "speed": 0.48, "phase": 4.2},
        ],
    }
    rig_path = os.path.join(OUT, "core", "kanban_core_rig.json")
    os.makedirs(os.path.dirname(rig_path), exist_ok=True)
    with open(rig_path, "w", encoding="utf-8") as fh:
        json.dump(rig, fh, indent=2)
    print(f"  core/kanban_core_rig.json  ({len(rig['orbit_layers'])} orbit layers)")

    return {"shell_triangles": shell_rec["triangles"], "records": len(RECORDS)}
