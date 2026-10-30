#!/usr/bin/env python3
"""Build an editable airfield asset kit in Blender 4.3+.

Run from the repository root with:
    blender --background --python tools/generate_airfield_kit.py

The script replaces only the named outputs inside assets/models/airport_kit.
It creates independent GLBs in metres, an organized Blender source, and a render.
It does not modify the existing island or add any gameplay logic.
"""
from pathlib import Path
import math
import os
import random
import shutil
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/airport_kit"
GLB_DIR = OUT / "glb"
TEX = OUT / "textures"
GLB_DIR.mkdir(parents=True, exist_ok=True)
RANDOM = random.Random(1403)
ASSETS = {}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    bpy.context.scene.render.engine = "CYCLES"
    bpy.context.scene.world = bpy.data.worlds.new("Overcast daylight")
    bpy.context.scene.world.use_nodes = True
    bg = bpy.context.scene.world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.60, 0.68, 0.71, 1)
    bg.inputs["Strength"].default_value = 0.60


def material(name, color, roughness=.8, metallic=0, image=None, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.diffuse_color = (*color, alpha)
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = roughness
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Alpha"].default_value = alpha
    if image:
        path = TEX / image
        if not path.is_file():
            raise FileNotFoundError(f"Missing checked-in texture: {path}")
        n = m.node_tree.nodes.new("ShaderNodeTexImage")
        n.name = "Base color (embedded in GLB)"
        n.image = bpy.data.images.load(str(path), check_existing=True)
        n.extension = "REPEAT"
        m.node_tree.links.new(n.outputs["Color"], p.inputs["Base Color"])
        if image in ("chainlink.png", "spruce_branch.png"):
            m.node_tree.links.new(n.outputs["Alpha"], p.inputs["Alpha"])
    if alpha < 1 or image in ("chainlink.png", "spruce_branch.png"):
        m.blend_method = "BLEND"
        m.use_backface_culling = False
    return m


def init_materials():
    return {
        "roof": material("Aged corrugated steel", (.55, .53, .48), .9, .38, "corrugated_rust.jpg"),
        "rust": material("Pitted rusted steel", (.38, .23, .14), .95, .35, "rusted_metal.jpg"),
        "concrete": material("Dirty concrete floor", (.55, .53, .49), .96, 0, "concrete.jpg"),
        "wall": material("Streaked exterior concrete", (.62, .60, .57), .98, 0, "weathered_concrete.jpg"),
        "wood": material("Weathered planks", (.42, .32, .22), .93, 0, "planks.jpg"),
        "asphalt": material("Cracked asphalt", (.22, .22, .20), .99, 0, "cracked_asphalt.jpg"),
        "chain": material("Chain link - alpha", (.5, .52, .48), .85, .45, "chainlink.png"),
        "needles": material("Conifer needle cards - Poly Haven CC0", (.4,.48,.29), .96, 0, "spruce_branch.png"),
        "frame": material("Dark oxidized frame", (.16, .17, .15), .8, .6),
        "rust_paint": material("Flaked orange rust", (.29, .105, .048), .98, .25),
        "trim": material("Faded desaturated edge paint", (.43, .40, .33), .88, .25),
        "white": material("Faded runway marking", (.70, .67, .58), .98),
        "glass": material("Dusty blue grey glass", (.24, .34, .36), .18, .05, alpha=.36),
        "darkglass": material("Vehicle dirty windows", (.095, .15, .16), .28, .1, alpha=.67),
        "solar": material("Solar panels", (.025, .07, .10), .36, .4),
        "rubber": material("Old rubber", (.045, .046, .043), .96),
        "green": material("Peeling dark olive vehicle paint", (.14, .20, .135), .91, .3, "paint_olive.jpg"),
        "red": material("Faded red vehicle paint", (.32, .105, .068), .92, .3, "paint_red.jpg"),
        "sand": material("Faded tan vehicle paint", (.37, .33, .26), .9, .3, "paint_sand.jpg"),
        "canvas": material("Faded canvas cover", (.24, .25, .19), 1),
        "brown": material("Dry soil and debris", (.22, .19, .13), 1),
        "grass": material("Dry green weeds", (.24, .30, .14), 1),
        "yellow": material("Dirty safety yellow", (.58, .43, .12), .88),
        "lamp": material("Lamp glass", (.72, .70, .55), .3, .05),
        "marker_enemy": material("Marker red - editor only", (.8, .08, .06), .8),
        "marker_loot": material("Marker blue - editor only", (.08, .3, .8), .8),
        "marker_story": material("Marker gold - editor only", (.95, .65, .06), .8),
    }


class Asset:
    def __init__(self, name, stage):
        self.name = name
        self.collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(self.collection)
        self.root = bpy.data.objects.new(name, None)
        self.root.empty_display_type = "PLAIN_AXES"
        self.root.empty_display_size = .5
        self.collection.objects.link(self.root)
        self.root.location = stage
        self.root["kit_asset"] = name
        self.root["units"] = "metres"
        ASSETS[name] = self

    def marker(self, name, position, purpose):
        obj = bpy.data.objects.new(name, None)
        obj.empty_display_type = "ARROWS"
        obj.empty_display_size = .55
        obj.parent = self.root
        obj.location = position
        obj["purpose"] = purpose
        self.collection.objects.link(obj)
        return obj


def uv_project(mesh, scale=.35):
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        n = poly.normal
        for li in poly.loop_indices:
            v = mesh.vertices[mesh.loops[li].vertex_index].co
            if abs(n.z) >= abs(n.x) and abs(n.z) >= abs(n.y):
                u, w = v.x, v.y
            elif abs(n.y) >= abs(n.x):
                u, w = v.x, v.z
            else:
                u, w = v.y, v.z
            uv.data[li].uv = (u * scale, w * scale)


def mesh_object(asset, name, verts, faces, mat, position=(0, 0, 0), uv_scale=.35, smooth=False):
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    uv_project(mesh, uv_scale)
    if smooth:
        for polygon in mesh.polygons:
            polygon.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    asset.collection.objects.link(obj)
    obj.parent = asset.root
    obj.location = position
    if mat:
        mesh.materials.append(mat)
    return obj


def box_data(size):
    x, y, z = (v / 2 for v in size)
    verts = [(-x,-y,-z), (x,-y,-z), (x,y,-z), (-x,y,-z),
             (-x,-y,z), (x,-y,z), (x,y,z), (-x,y,z)]
    faces = [(0,3,2,1), (4,5,6,7), (0,1,5,4), (1,2,6,5), (2,3,7,6), (3,0,4,7)]
    return verts, faces


def box(asset, name, position, size, mat, rotation=None, uv_scale=.35):
    verts, faces = box_data(size)
    obj = mesh_object(asset, name, verts, faces, mat, position, uv_scale)
    if rotation is not None:
        obj.rotation_euler = rotation
    return obj


def cylinder(asset, name, position, radius, length, mat, axis=(0, 0, 1), sides=20):
    verts = []
    for z in (-length / 2, length / 2):
        for i in range(sides):
            angle = 2 * math.pi * i / sides
            verts.append((radius * math.cos(angle), radius * math.sin(angle), z))
    faces = []
    faces.append(tuple(range(sides - 1, -1, -1)))
    faces.append(tuple(range(sides, 2 * sides)))
    for i in range(sides):
        j = (i + 1) % sides
        faces.append((i, j, sides + j, sides + i))
    obj = mesh_object(asset, name, verts, faces, mat, position, uv_scale=.7)
    for poly in obj.data.polygons:
        poly.use_smooth = (len(poly.vertices) == 4)
    direction = Vector(axis).normalized()
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def beam(asset, name, start, end, width, mat):
    a, b = Vector(start), Vector(end)
    obj = box(asset, name, (a + b) * .5, (width, width, (b - a).length), mat)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (b - a).normalized().to_track_quat("Z", "Y")
    return obj


def batch_beams(asset, name, segments, width, mat):
    verts, faces = [], []
    for start, end in segments:
        a, b = Vector(start), Vector(end)
        direction = b - a
        if direction.length < .0001:
            continue
        local, quads = box_data((width, width, direction.length))
        rotation = direction.normalized().to_track_quat("Z", "Y")
        center = (a + b) * .5
        offset = len(verts)
        verts.extend([tuple(center + rotation @ Vector(v)) for v in local])
        faces.extend([tuple(offset + i for i in face) for face in quads])
    return mesh_object(asset, name, verts, faces, mat)


def plane(asset, name, corners, mat, uv_scale=1):
    # Corners are authored in asset-local coordinates.
    return mesh_object(asset, name, corners, [tuple(range(len(corners)))], mat, uv_scale=uv_scale)


def arched_roof(asset, width, depth, side_height, rise, mat, name="Roof_arched_separate"):
    segments = 80
    verts, faces = [], []
    for i in range(segments + 1):
        t = math.pi * i / segments
        x = -width * .5 * math.cos(t)
        z = side_height + rise * math.sin(t)
        # The small alternating offset makes the roof physically corrugated.
        z += .025 * math.sin(i * math.pi / 2) * math.sin(t)
        verts.extend([(x, -depth * .5, z), (x, depth * .5, z)])
    for i in range(segments):
        faces.append((2*i, 2*i+2, 2*i+3, 2*i+1))
    obj = mesh_object(asset, name, verts, faces, mat, uv_scale=.35)
    # Unwrap continuously around the arch instead of changing projection axis.
    uv = obj.data.uv_layers.active
    approximate_arc = math.pi * (3*(width/2+rise)-math.sqrt((3*width/2+rise)*(width/2+3*rise))) / 2
    for p in obj.data.polygons:
        p.use_smooth = True
        for li in p.loop_indices:
            vi = obj.data.loops[li].vertex_index
            u = (vi//2)/segments * approximate_arc * .35
            v = (verts[vi][1] + depth/2) * .35
            uv.data[li].uv=(u,v)
    return obj


def arch_gable(asset, name, width, y, side_height, rise, mat, front=True):
    # Solid spandrel over an actually open rectangular doorway.
    segments = 40
    verts, faces = [], []
    for i in range(segments + 1):
        t = math.pi * i / segments
        x = -width * .5 * math.cos(t)
        z = side_height + rise * math.sin(t)
        verts += [(x, y, side_height), (x, y, z)]
    for i in range(segments):
        if front:
            faces.append((2*i, 2*i+1, 2*i+3, 2*i+2))
        else:
            faces.append((2*i+2, 2*i+3, 2*i+1, 2*i))
    return mesh_object(asset, name, verts, faces, mat, uv_scale=.35)


def arched_ribs(asset, width, depth, side_height, rise, mat, count=6):
    segments = []
    for k in range(count):
        y = -depth / 2 + .35 + (depth - .7) * k / (count - 1)
        for i in range(20):
            t1 = math.pi * i / 20
            t2 = math.pi * (i + 1) / 20
            a = (-width*.5*math.cos(t1), y, side_height + rise*math.sin(t1) - .15)
            b = (-width*.5*math.cos(t2), y, side_height + rise*math.sin(t2) - .15)
            segments.append((a, b))
        segments += [((-width/2+.12,y,.15),(-width/2+.12,y,side_height)),
                     ((width/2-.12,y,.15),(width/2-.12,y,side_height))]
    return batch_beams(asset, "Interior_separate_steel_roof_ribs", segments, .15, mat)


def gabled_roof(asset, width, depth, wall_h, rise, mat):
    x, y = width / 2, depth / 2
    return mesh_object(asset, "Roof_gabled_separate", [(-x,-y,wall_h),(0,-y,wall_h+rise),(x,-y,wall_h),
                    (-x,y,wall_h),(0,y,wall_h+rise),(x,y,wall_h)],
                    [(0,3,4,1),(1,4,5,2)], mat, uv_scale=.35)


def gable_end(asset, name, width, y, wall_h, rise, mat):
    x = width / 2
    return mesh_object(asset, name, [(-x,y,wall_h),(x,y,wall_h),(0,y,wall_h+rise)], [(0,1,2)], mat)


def world_object(name, obj_type, data, location):
    collection = bpy.data.collections.get("Presentation_only")
    if collection is None:
        collection = bpy.data.collections.new("Presentation_only")
        bpy.context.scene.collection.children.link(collection)
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.location = location
    return obj


def weeds(asset, points, m):
    """Sparse actual leaf geometry at wall edges, grouped in one editable mesh."""
    verts, faces = [], []
    for x,y in points:
        for _ in range(7):
            angle=RANDOM.uniform(0,2*math.pi); h=RANDOM.uniform(.16,.42)
            width=RANDOM.uniform(.025,.055); spread=RANDOM.uniform(.04,.16)
            dx,dy=math.cos(angle),math.sin(angle)
            base=len(verts)
            verts += [(x-dy*width,y+dx*width,.015),(x+dy*width,y-dx*width,.015),
                      (x+dx*spread,y+dy*spread,h)]
            faces.append((base,base+1,base+2))
    return mesh_object(asset,"Edge_weeds_separate",verts,faces,m["grass"])


def side_wall_windows(a, x, d, h, m, label):
    """A concrete side wall with two real glazed openings, not pasted windows."""
    gaps=[(-3.15,-1.35),(1.05,2.85)]
    spans=[(-d/2,gaps[0][0]),(gaps[0][1],gaps[1][0]),(gaps[1][1],d/2)]
    for i,(lo,hi) in enumerate(spans):
        box(a,f"{label}_wall_section_{i}",(x,(lo+hi)/2,h/2),(.24,hi-lo,h),m["wall"])
    frame=[]
    for i,(lo,hi) in enumerate(gaps):
        sill,top=1.0,2.65;mid=(lo+hi)/2
        box(a,f"{label}_window_sill_{i}",(x,mid,sill/2),(.24,hi-lo,sill),m["wall"])
        box(a,f"{label}_window_header_{i}",(x,mid,(top+h)/2),(.24,hi-lo,h-top),m["wall"])
        box(a,f"{label}_window_glass_{i}_separate",(x,mid,(sill+top)/2),(.04,hi-lo,top-sill),m["glass"])
        xo=x+(.15 if x>0 else -.15)
        frame += [((xo,lo,sill),(xo,hi,sill)),((xo,lo,top),(xo,hi,top)),
                  ((xo,lo,sill),(xo,lo,top)),((xo,hi,sill),(xo,hi,top)),((xo,mid,sill),(xo,mid,top))]
    batch_beams(a,f"{label}_window_frames_separate",frame,.075,m["frame"])


def facade_panel_seams(a,w,d,h,opening,rise,m,gable=False):
    seg=[]
    for x in [(-w/2)+i*2 for i in range(int(w/2)+1)]:
        shape = (1-abs(x)/(w/2)) if gable else math.sqrt(max(0,1-(x/(w/2))**2))
        top = h + rise*shape
        bottom = 0 if abs(x)>opening/2 else h
        if top-bottom>.06: seg.append(((x,-d/2-.02,bottom),(x,-d/2-.02,top)))
    for z in (.15,h-.12):
        seg.extend([((-w/2,-d/2-.03,z),(-opening/2,-d/2-.03,z)),
                    ((opening/2,-d/2-.03,z),(w/2,-d/2-.03,z))])
    batch_beams(a,"Front_sheet_seams_and_trims",seg,.035,m["frame"])


def bevel(obj, amount=.06):
    modifier=obj.modifiers.new("Softened weathered edges", "BEVEL")
    modifier.width=amount
    modifier.segments=2
    modifier.limit_method="ANGLE"
    return obj


def hangar_large(m):
    a = Asset("hangar_large", (-26, 22, 0))
    w, d, h, rise, door_w = 36, 28, 6.0, 7.0, 22
    box(a, "Floor_concrete_walkable", (0, 0, -.12), (w, d, .24), m["concrete"], uv_scale=.22)
    box(a, "Wall_left_separate", (-w/2+.12, 0, h/2), (.24, d, h), m["roof"])
    box(a, "Wall_right_separate", (w/2-.12, 0, h/2), (.24, d, h), m["roof"])
    box(a, "Wall_rear_separate", (0, d/2-.12, h/2), (w, .24, h), m["roof"])
    p = (w - door_w) / 2
    for side in (-1, 1):
        box(a, f"Front_pier_{side}", (side*(door_w/2+p/2), -d/2+.12, h/2), (p, .24, h), m["roof"])
        door_width = door_w / 2
        # Both leaves are parked outside the clear central opening.
        x = side * (door_w/2 + door_width/2)
        box(a, f"Sliding_door_{'left' if side < 0 else 'right'}_OPEN_separate", (x, -d/2-.18, h/2-.10), (door_width, .20, h-.2), m["roof"])
        for k in range(3):
            box(a, f"Door_horizontal_brace_{side}_{k}", (x, -d/2-.31, .25+k*(h-.5)/2), (door_width, .08, .10), m["frame"])
    arch_gable(a, "Front_arch_over_opening", w, -d/2+.12, h, rise, m["roof"])
    arch_gable(a, "Rear_arch", w, d/2-.12, h, rise, m["roof"], False)
    arched_roof(a, w+.45, d+.5, h, rise, m["roof"])
    arched_ribs(a, w, d, h, rise, m["frame"], 6)
    facade_panel_seams(a,w,d,h,door_w,rise,m)
    # Low, separately editable side annex with its own real front doorway.
    ax0,ax1=-w/2-5,-w/2
    ay0,ay1=-10,10
    box(a,"Annex_floor_walkable",((ax0+ax1)/2,0,-.1),(5,20,.2),m["concrete"])
    box(a,"Annex_side_wall",(ax0+.12,0,1.75),(.24,20,3.5),m["roof"])
    box(a,"Annex_rear_wall",((ax0+ax1)/2,ay1-.12,1.75),(5,.24,3.5),m["roof"])
    door_l,door_r=ax0+1.7,ax0+3.3
    box(a,"Annex_front_left_pier",((ax0+door_l)/2,ay0+.12,1.75),(door_l-ax0,.24,3.5),m["roof"])
    box(a,"Annex_front_right_pier",((door_r+ax1)/2,ay0+.12,1.75),(ax1-door_r,.24,3.5),m["roof"])
    box(a,"Annex_door_header",((door_l+door_r)/2,ay0+.12,3.0),(door_r-door_l,.24,1),m["roof"])
    box(a,"Annex_door_OPEN_separate",(door_l-.07,ay0-.7,1.25),(.12,1.4,2.5),m["roof"])
    plane(a,"Annex_roof_separate",[(ax0-.2,ay0-.25,3.55),(ax1+.1,ay0-.25,4.4),
                                   (ax1+.1,ay1+.25,4.4),(ax0-.2,ay1+.25,3.55)],m["roof"],uv_scale=.35)
    for x,y in ((-4,3),(4,-3)):
        z=h+rise*math.sqrt(1-(x/(w/2))**2)
        box(a,f"Roof_vent_{x}_{y}",(x,y,z+.28),(1.8,1,.55),m["frame"])
        box(a,f"Roof_vent_cap_{x}_{y}",(x,y,z+.60),(2,1.2,.1),m["roof"])
    # Separate floor props make the scale and usable interior visible in Blender.
    box(a,"Interior_wood_crate_separate",(-12.5,7.5,.6),(1.2,1.2,1.2),m["wood"],uv_scale=.7)
    box(a,"Interior_pallet_separate",(10.5,8.5,.08),(2.3,1.3,.16),m["wood"])
    for i,(x,y) in enumerate([(-15,-13.7),(-13.4,-13.7),(14,-13.7),(15.5,-13.7)]):
        box(a,f"Exterior_cargo_box_{i}_separate",(x,y,.52),(1,1,1.04),m["wood"],uv_scale=.7)
    weeds(a,[(ax0-.15,-8),(ax0-.1,-4),(ax0-.1,2),(ax0-.1,8),(-17.3,-14.3),(17,-14.3)],m)
    a.marker("MARKER_INFECTED_HANGAR", (-5, 5, 0), "infected spawn placeholder; no gameplay")
    a.marker("MARKER_LOOT_HANGAR", (11, 8, 0), "loot placeholder; no gameplay")
    return a


def hangar_small(m):
    a = Asset("hangar_small", (13, 21, 0))
    w, d, h, rise, door_w = 18, 18, 5.2, 3.0, 12
    box(a, "Floor_concrete_walkable", (0,0,-.1), (w,d,.2), m["concrete"], uv_scale=.22)
    box(a, "Wall_left_separate", (-w/2+.12,0,h/2), (.24,d,h), m["roof"])
    box(a, "Wall_right_separate", (w/2-.12,0,h/2), (.24,d,h), m["roof"])
    box(a, "Wall_rear_separate", (0,d/2-.12,h/2), (w,.24,h), m["roof"])
    pier = (w-door_w)/2
    for side in (-1, 1):
        x = side*(door_w/2+pier/2)
        box(a, f"Front_pier_{side}", (x,-d/2+.12,h/2), (pier,.24,h), m["roof"])
        door_width = door_w/2
        xdoor = side*(door_w/2+door_width/2)
        box(a, f"Sliding_door_{side}_OPEN_separate", (xdoor,-d/2-.19,h/2-.1), (door_width,.18,h-.2), m["roof"])
        for z in (.28,2.55,4.85):
            box(a, f"Door_brace_{side}_{z}", (xdoor,-d/2-.29,z), (door_width,.08,.10), m["frame"])
    gable_end(a, "Front_gable", w,-d/2+.12,h,rise,m["roof"])
    gable_end(a, "Rear_gable", w,d/2-.12,h,rise,m["roof"])
    gabled_roof(a,w+.35,d+.4,h,rise,m["roof"])
    supports=[]
    for y in (-8.5,-4,0,4,8.5):
        supports.extend([((-w/2+.2,y,.1),(-w/2+.2,y,h)), ((w/2-.2,y,.1),(w/2-.2,y,h)),
                         ((-w/2+.2,y,h),(0,y,h+rise-.12)), ((0,y,h+rise-.12),(w/2-.2,y,h))])
    batch_beams(a,"Interior_exposed_gable_frames",supports,.13,m["frame"])
    facade_panel_seams(a,w,d,h,door_w,rise,m,gable=True)
    for i,(x,y) in enumerate([(-7.7,-8.8),(7.7,-8.8),(7.7,7.8)]):
        box(a,f"Cargo_box_{i}_separate",(x,y,.55),(1.1,1.1,1.1),m["wood"],uv_scale=.7)
    weeds(a,[(-8.9,-7),(-8.9,0),(-8.9,7),(8.9,-7),(8.9,3)],m)
    a.marker("MARKER_INFECTED_SMALL_HANGAR",(-3,4,0),"infected spawn placeholder; no gameplay")
    a.marker("MARKER_LOOT_SMALL_HANGAR",(5,5,0),"loot placeholder; no gameplay")
    return a


def front_wall_with_openings(a, w, d, h, m, door=(-4.8,-3.2), window=(1.0,5.3)):
    y = -d/2 + .12
    # Three full-height sections, one door header, and window sill/header.
    for i, (l, r) in enumerate([(-w/2,door[0]), (door[1],window[0]), (window[1],w/2)]):
        if r > l:
            box(a, f"Front_wall_section_{i}", ((l+r)/2,y,h/2), (r-l,.24,h), m["wall"])
    door_h = 2.45
    box(a,"Door_header",((door[0]+door[1])/2,y,(door_h+h)/2),
        (door[1]-door[0],.24,h-door_h),m["wall"])
    sill, top = 1.0, 2.65
    cx = (window[0]+window[1])/2
    ww = window[1]-window[0]
    box(a,"Window_sill_wall",(cx,y,sill/2),(ww,.24,sill),m["wall"])
    box(a,"Window_header_wall",(cx,y,(top+h)/2),(ww,.24,h-top),m["wall"])
    box(a,"Window_glass_separate",(cx,y-.13,(sill+top)/2),(ww,.035,top-sill),m["glass"])
    segments = [((window[0],y-.17,sill),(window[1],y-.17,sill)),
                ((window[0],y-.17,top),(window[1],y-.17,top)),
                ((window[0],y-.17,sill),(window[0],y-.17,top)),
                ((window[1],y-.17,sill),(window[1],y-.17,top)),
                ((cx,y-.17,sill),(cx,y-.17,top))]
    batch_beams(a,"Window_frame_separate",segments,.075,m["frame"])
    # A separately editable swung-open door; the 1.6 m opening stays clear.
    width = door[1]-door[0]
    box(a,"Personnel_door_OPEN_separate",(door[0]-.07,-d/2-width/2,door_h/2),(.12,width,door_h),m["roof"])
    cylinder(a,"Door_handle_separate",(door[0]-.17,-d/2-width*.8,1.05),.045,.16,m["yellow"],axis=(1,0,0))


def service_building(m):
    a = Asset("service_building",(-31,-8,0))
    w,d,h = 16,10,3.8
    box(a,"Floor_concrete_walkable",(0,0,-.1),(w,d,.2),m["concrete"],uv_scale=.25)
    front_wall_with_openings(a,w,d,h,m)
    box(a,"Wall_back_separate",(0,d/2-.12,h/2),(w,.24,h),m["wall"])
    side_wall_windows(a,-w/2+.12,d,h,m,"Left")
    side_wall_windows(a,w/2-.12,d,h,m,"Right")
    # Partition has a real 1.7 m doorway rather than a texture.
    box(a,"Interior_partition_front",(0,-3.25,h/2),(.16,3.5,h),m["concrete"])
    box(a,"Interior_partition_back",(0,3.25,h/2),(.16,3.5,h),m["concrete"])
    box(a,"Interior_partition_door_header",(0,0,(2.45+h)/2),(.16,3, h-2.45),m["concrete"])
    box(a,"Roof_flat_separate",(0,0,h+.12),(w+.5,d+.5,.24),m["concrete"],uv_scale=.25)
    for side in (-1,1):
        box(a,f"Roof_parapet_long_{side}",(side*(w/2+.1),0,h+.38),(.16,d+.5,.5),m["concrete"])
        box(a,f"Roof_parapet_short_{side}",(0,side*(d/2+.1),h+.38),(w,.16,.5),m["concrete"])
    # Two rows of individual framed panels sitting above the separate roof.
    for ix in range(4):
        for iy in range(2):
            x, y = -4.5+ix*2.75, -2.1+iy*3
            panel = box(a,f"Solar_panel_{ix}_{iy}_separate",(x,y,h+.5),(2.25,1.6,.08),m["solar"],rotation=(.18,0,0))
            box(a,f"Solar_frame_{ix}_{iy}",(x,y,h+.48),(2.36,1.7,.08),m["frame"],rotation=(.18,0,0))
    box(a,"Office_desk_separate",(-4.3,2.6,.8),(2.4,.8,.12),m["wood"])
    for x in (-5.25,-3.35):
        box(a,f"Office_desk_leg_{x}",(x,2.6,.4),(.1,.7,.8),m["frame"])
    box(a,"Interior_shelf_separate",(5.2,3.8,1.2),(2,.55,2.4),m["frame"])
    for z in (.25,.85,1.45,2.05):
        box(a,f"Shelf_plank_{z}",(5.2,3.8,z),(1.9,.6,.06),m["wood"])
    # Small corrugated awning and storeroom props, like the reference building.
    plane(a,"Service_side_awning_roof_separate",[(7.95,-4.5,3.30),(11.3,-4.5,2.90),
                                                (11.3,4.5,2.90),(7.95,4.5,3.30)],m["roof"],uv_scale=.4)
    for y in (-4.25,4.25):
        box(a,f"Service_awning_post_{y}",(11.1,y,1.48),(.13,.13,2.96),m["frame"])
    for i,(x,y) in enumerate(((9.1,-2.5),(9.9,-2.5),(9.5,2.7))):
        box(a,f"Awning_cargo_box_{i}_separate",(x,y,.5),(1,1,1),m["wood"],uv_scale=.7)
    for x,y in ((-5,3.4),(5,3.4)):
        box(a,f"Roof_vent_service_{x}",(x,y,h+.58),(.55,.55,.9),m["wall"])
        box(a,f"Roof_vent_service_cap_{x}",(x,y,h+1.05),(.7,.7,.1),m["frame"])
    weeds(a,[(-8,-4),(-8,1),(-8,4),(8,-4),(8,4),(-6,-5.1),(3,-5.1)],m)
    a.marker("MARKER_LOOT_OFFICE",(-4,3,0),"loot placeholder; no gameplay")
    a.marker("MARKER_STORY_OFFICE",(5,3,0),"story item placeholder; no gameplay")
    return a


def control_tower(m):
    a = Asset("control_tower",(34,20,0))
    w,d,h = 14,10,3.7
    box(a,"Floor_ground_walkable",(0,0,-.12),(w,d,.24),m["concrete"],uv_scale=.25)
    front_wall_with_openings(a,w,d,h,m,door=(-4.6,-3.0),window=(.4,4.8))
    box(a,"Wall_ground_rear",(0,d/2-.12,h/2),(w,.24,h),m["wall"])
    side_wall_windows(a,-w/2+.12,d,h,m,"Ground_left")
    side_wall_windows(a,w/2-.12,d,h,m,"Ground_right")
    # Upper floor is split into panels around the stairwell, not a solid slab.
    box(a,"Floor_upper_main_walkable",(-1.9,0,h),(10.2,d,.24),m["concrete"])
    box(a,"Floor_upper_stair_front",(5.1,-4.2,h),(3.8,1.6,.24),m["concrete"])
    box(a,"Floor_upper_stair_back",(5.1,4.3,h),(3.8,1.4,.24),m["concrete"])
    box(a,"Stair_top_landing_walkable",(4.8,3.0,h),(1.55,1.2,.24),m["concrete"])
    for i in range(18):
        z = (i+1)*h/18
        y = -3.8 + i*.36
        box(a,f"Stair_step_{i+1:02d}",(4.8,y,z-.06),(1.55,.38,.12),m["concrete"])
    stair_rail=[((3.95,-3.8,.9),(3.95,2.32,h+.75)),((5.65,-3.8,.9),(5.65,2.32,h+.75))]
    for i in (0,4,8,12,17):
        y=-3.8+i*.36; z=(i+1)*h/18
        stair_rail.extend([((3.95,y,z),(3.95,y,z+.9)),((5.65,y,z),(5.65,y,z+.9))])
    batch_beams(a,"Interior_stair_rails",stair_rail,.06,m["frame"])
    # Central shaft and glazed observation cabin: roof, glass and railing are separate.
    shaft_w, shaft_d, shaft_top = 6.4,6.0,9.0
    for x in (-shaft_w/2,shaft_w/2):
        for y in (-2.2,2.2):
            box(a,f"Tower_shaft_side_pier_{x}_{y}",(x,y,(h+shaft_top)/2),(.24,1.6,shaft_top-h),m["wall"])
        box(a,f"Tower_shaft_side_sill_{x}",(x,0,h+.55),(.24,2.8,1.1),m["wall"])
        box(a,f"Tower_shaft_side_header_{x}",(x,0,(h+2.8+shaft_top)/2),(.24,2.8,shaft_top-h-2.8),m["wall"])
        box(a,f"Tower_shaft_window_{x}_separate",(x,0,h+1.95),(.04,2.8,1.7),m["glass"])
        for y in (-1.4,0,1.4):
            beam(a,f"Tower_shaft_window_mullion_{x}_{y}",(x,y,h+1.1),(x,y,h+2.8),.07,m["frame"])
    box(a,"Tower_shaft_rear_wall",(0,shaft_d/2,(h+shaft_top)/2),(shaft_w,.24,shaft_top-h),m["wall"])
    for x in (-2.1,2.1):
        box(a,f"Tower_upper_door_pier_{x}",(x,-shaft_d/2,(h+shaft_top)/2),(2.2,.24,shaft_top-h),m["wall"])
    box(a,"Tower_upper_door_header",(0,-shaft_d/2,(h+2.4+shaft_top)/2),(2,.24,shaft_top-h-2.4),m["wall"])
    box(a,"Tower_upper_door_OPEN_separate",(-1.05,-shaft_d/2-.75,h+1.2),(.12,1.5,2.4),m["roof"])
    box(a,"Observation_deck_floor",(0,0,shaft_top),(10,8,.30),m["concrete"])
    cw, cd, ch = 8.6,6.5,2.9
    base = shaft_top+.15
    glass_z = base+ch/2
    for x in (-cw/2,cw/2):
        box(a,f"Cabin_glass_side_{x}",(x,0,glass_z),(.055,cd,ch),m["glass"])
    for y in (-cd/2,cd/2):
        box(a,f"Cabin_glass_end_{y}",(0,y,glass_z),(cw,.055,ch),m["glass"])
    seg=[]
    for x in (-cw/2,0,cw/2):
        for y in (-cd/2,cd/2):
            seg.append(((x,y,base),(x,y,base+ch)))
    for y in (-cd/2,0,cd/2):
        for x in (-cw/2,cw/2):
            seg.append(((x,y,base),(x,y,base+ch)))
    for z in (base,base+ch):
        for x in (-cw/2,cw/2): seg.append(((x,-cd/2,z),(x,cd/2,z)))
        for y in (-cd/2,cd/2): seg.append(((-cw/2,y,z),(cw/2,y,z)))
    batch_beams(a,"Cabin_window_frames_separate",seg,.12,m["frame"])
    box(a,"Cabin_roof_separate",(0,0,base+ch+.15),(9.1,7,.3),m["roof"])
    rail=[]
    for x in (-4.85,4.85):
        rail.append(((x,-3.85,shaft_top+1.1),(x,3.85,shaft_top+1.1)))
        for y in (-3.85,0,3.85): rail.append(((x,y,shaft_top),(x,y,shaft_top+1.1)))
    for y in (-3.85,3.85):
        rail.append(((-4.85,y,shaft_top+1.1),(4.85,y,shaft_top+1.1)))
    batch_beams(a,"Observation_deck_railing",rail,.055,m["frame"])
    lower_rail=[]
    for x in (-6.85,6.85):
        lower_rail.append(((x,-4.85,h+1.05),(x,4.85,h+1.05)))
        for y in (-4.85,0,4.85):lower_rail.append(((x,y,h),(x,y,h+1.05)))
    for y in (-4.85,4.85):
        lower_rail.append(((-6.85,y,h+1.05),(6.85,y,h+1.05)))
        for x in (-4,0,4):lower_rail.append(((x,y,h),(x,y,h+1.05)))
    batch_beams(a,"Lower_roof_balustrade_separate",lower_rail,.055,m["frame"])
    # Control furniture is visible behind the cabin glass; the mast is part of the tower.
    box(a,"Control_cabin_console_separate",(0,1.7,base+.62),(5,.65,1.24),m["frame"])
    box(a,"Control_cabin_console_top",(0,1.7,base+1.28),(5.1,.75,.10),m["darkglass"])
    mast_base=base+ch+.3
    cylinder(a,"Control_tower_antenna",(0,0,mast_base+1.4),.045,2.8,m["frame"],sides=12)
    for z in (mast_base+.7,mast_base+1.7,mast_base+2.5):
        beam(a,f"Tower_antenna_cross_{z:.1f}",(-.7,0,z),(.7,0,z),.035,m["frame"])
    for x,y in ((-5,-4.8),(5,-4.8),(6.5,4.4)):
        box(a,f"Tower_exterior_box_{x}_{y}_separate",(x,y,.5),(1,1,1),m["wood"],uv_scale=.7)
    weeds(a,[(-7,-4),(-7,1),(-7,4),(7,-4),(7,4),(-6,-5.1),(3,-5.1)],m)
    a.marker("MARKER_INFECTED_TOWER",(-3,3,0),"infected spawn placeholder; no gameplay")
    a.marker("MARKER_LOOT_TOWER",(0,1,h+.2),"loot placeholder; no gameplay")
    return a


def fuel_canopy(m):
    a=Asset("fuel_canopy",(-4,-8,0))
    w,d,h=11,7,4.6
    for x in (-w/2+.2,w/2-.2):
        for y in (-d/2+.2,d/2-.2):
            box(a,f"Canopy_post_{x}_{y}",(x,y,h/2),(.22,.22,h),m["frame"])
            box(a,f"Concrete_foot_{x}_{y}",(x,y,.18),(.55,.55,.36),m["concrete"])
    box(a,"Canopy_roof_separate",(0,0,h+.14),(w+.6,d+.6,.28),m["roof"],uv_scale=.4)
    box(a,"Canopy_front_fascia",(0,-d/2-.15,h),(w+.6,.15,.5),m["rust"])
    box(a,"Canopy_rear_fascia",(0,d/2+.15,h),(w+.6,.15,.5),m["rust"])
    batch_beams(a,"Canopy_support_crossbeams",[((-w/2+.2,-d/2+.2,h-.25),(w/2-.2,-d/2+.2,h-.25)),
                    ((-w/2+.2,d/2-.2,h-.25),(w/2-.2,d/2-.2,h-.25))],.14,m["frame"])
    return a


def fuel_tank(m):
    a=Asset("fuel_tank",(-5,-8,0))
    # Cylinder length follows Y, with grounded saddles and separate caps/piping.
    cylinder(a,"Horizontal_tank_body",(0,0,1.65),1.15,4.8,m["rust"],axis=(0,1,0),sides=32)
    for y in (-2.35,2.35):
        cylinder(a,f"Tank_end_cap_{y}",(0,y,1.65),1.16,.08,m["rust"],axis=(0,1,0),sides=32)
    for y in (-1.55,1.55):
        box(a,f"Tank_saddle_{y}",(0,y,.38),(1.8,.35,.76),m["frame"])
        box(a,f"Tank_foundation_{y}",(0,y,.1),(2.3,.8,.2),m["concrete"])
    cylinder(a,"Tank_filler",(0,-.8,2.9),.24,.35,m["frame"])
    cylinder(a,"Tank_filler_cap",(0,-.8,3.1),.29,.08,m["rust"])
    segments=[((-.95,-1.95,.2),(-.95,-1.95,2.8)),((-.95,1.95,.2),(-.95,1.95,2.8))]
    for z in (.45,1.0,1.55,2.1,2.65): segments.append(((-.95,-1.95,z),(-.95,1.95,z)))
    batch_beams(a,"Tank_side_ladder",segments,.045,m["frame"])
    return a


def fuel_pump(m):
    a=Asset("fuel_pump",(.5,-8,0))
    box(a,"Pump_body",(0,0,1),(.95,.65,2),m["roof"])
    box(a,"Pump_top",(0,0,2.07),(1.05,.75,.14),m["frame"])
    box(a,"Pump_display",(0,-.335,1.55),(.62,.04,.38),m["darkglass"])
    box(a,"Pump_base",(0,0,.12),(1.2,.85,.24),m["concrete"])
    beam(a,"Pump_hose_part_1",(.5,0,1.7),(.8,0,1.2),.09,m["rubber"])
    beam(a,"Pump_hose_part_2",(.8,0,1.2),(.72,0,.55),.09,m["rubber"])
    beam(a,"Pump_hose_part_3",(.72,0,.55),(.55,0,.45),.09,m["rubber"])
    a.marker("MARKER_LOOT_FUEL",(.7,.8,0),"loot placeholder; no gameplay")
    return a


def pickup(m, name, stage, body, covered=False, roof_rack=False):
    a=Asset(name,stage)
    length=5.35 if covered else 4.75
    front=-length/2
    rear=length/2
    box(a,"Chassis_separate",(0,0,.64),(1.75,length-.15,.32),m["frame"])
    bevel(box(a,"Body_lower_separate",(0,0,1.02),(1.82,length,.58),body),.09)
    bevel(box(a,"Hood_separate",(0,front+.75,1.39),(1.78,1.42,.32),body),.08)
    # Irregular chipped areas are separate geometry rather than square color blocks.
    z=1.556
    plane(a,"Hood_rust_patch_separate",[(-.55,front+.42,z),(-.40,front+.36,z),(-.24,front+.50,z),
               (-.30,front+.68,z),(-.49,front+.73,z),(-.60,front+.61,z)],m["rust_paint"])
    for i in range(5):
        x=-.58+i*.29
        box(a,f"Hood_vent_{i}",(x,front+1.08,1.56),(.16,.22,.015),m["frame"])
    box(a,"Front_grille",(0,front-.015,1.11),(1.36,.055,.36),m["frame"])
    for z in (.99,1.08,1.17,1.26):
        box(a,f"Grille_horizontal_bar_{z}",(0,front-.05,z),(1.25,.025,.025),m["trim"])
    box(a,"Front_bumper",(0,front-.12,.75),(1.96,.18,.16),m["rust"])
    box(a,"Rear_bumper",(0,rear+.11,.7),(1.96,.18,.16),m["frame"])
    batch_beams(a,"Front_bullbar_separate",[((-.8,front-.22,.78),(-.8,front-.22,1.44)),
                     ((.8,front-.22,.78),(.8,front-.22,1.44)),
                     ((-.8,front-.22,1.4),(.8,front-.22,1.4))],.055,m["frame"])
    for x in (-.7,.7):
        box(a,f"Headlamp_{x}",(x,front-.05,1.24),(.32,.07,.22),m["lamp"])
        box(a,f"Rear_lamp_{x}",(x,rear+.03,1.17),(.23,.07,.24),m["red"])
    cab_front=front+1.35
    cab_rear=cab_front+1.68
    box(a,"Cab_lower",(0,(cab_front+cab_rear)/2,1.38),(1.78,1.68,.36),body)
    # Cabin windows are actual transparent geometry and retain their own names.
    windshield=[(-.78,cab_front,1.55),(.78,cab_front,1.55),(.74,cab_front+.20,2.16),(-.74,cab_front+.20,2.16)]
    plane(a,"Windshield_glass_separate",windshield,m["darkglass"])
    rearwin=[(-.76,cab_rear,1.55),(-.72,cab_rear,2.16),(.72,cab_rear,2.16),(.76,cab_rear,1.55)]
    plane(a,"Rear_window_glass_separate",rearwin,m["darkglass"])
    for side in (-1,1):
        sidewin=[(side*.84,cab_front+.10,1.56),(side*.84,cab_rear-.04,1.56),
                 (side*.79,cab_rear-.04,2.16),(side*.79,cab_front+.22,2.16)]
        plane(a,f"Side_window_{side}_separate",sidewin,m["darkglass"])
        box(a,f"Side_door_{side}_separate",(side*.915,(cab_front+cab_rear)/2,1.20),(.05,1.6,.55),body)
        box(a,f"Door_handle_{side}",(side*.95,cab_rear-.22,1.46),(.06,.22,.05),m["frame"])
        x=side*.952
        plane(a,f"Door_rust_patch_{side}_separate",[(x,cab_rear-.72,.99),(x,cab_rear-.50,.94),
                     (x,cab_rear-.30,1.03),(x,cab_rear-.35,1.15),(x,cab_rear-.58,1.18)],m["rust_paint"])
        box(a,f"Side_mirror_{side}",(side*1.03,cab_front+.24,1.62),(.22,.25,.15),m["frame"])
        box(a,f"Running_board_{side}",(side*1.02,(cab_front+cab_rear)/2,.68),(.28,1.65,.10),m["frame"])
    pillars=[]
    for side in (-1,1):
        pillars += [((side*.83,cab_front,1.52),(side*.79,cab_front+.20,2.18)),
                    ((side*.84,cab_rear,1.52),(side*.79,cab_rear,2.18)),
                    ((side*.81,(cab_front+cab_rear)/2,1.56),(side*.79,(cab_front+cab_rear)/2,2.16)),
                    ((side*.78,cab_front+.2,2.16),(side*.79,cab_rear,2.16))]
    batch_beams(a,"Cab_window_frames_separate",pillars,.075,body)
    bevel(box(a,"Cab_roof_separate",(0,(cab_front+cab_rear)/2+.1,2.22),(1.72,1.62,.15),body),.07)
    batch_beams(a,"Windshield_wipers_separate",[((-.70,cab_front-.02,1.59),(-.08,cab_front-.02,1.68)),
                 ((.08,cab_front-.02,1.68),(.70,cab_front-.02,1.59))],.025,m["frame"])
    bed_start=cab_rear+.05
    bed_len=max(.7,rear-bed_start)
    box(a,"Pickup_bed_floor",(0,(bed_start+rear)/2,1.27),(1.65,bed_len,.12),m["rust"])
    for side in (-1,1):
        box(a,f"Pickup_bed_side_{side}",(side*.85,(bed_start+rear)/2,1.52),(.16,bed_len,.56),body)
        box(a,f"Pickup_side_rust_{side}",(side*.94,rear-.45,1.48),(.015,.45,.24),m["rust_paint"])
    box(a,"Tailgate_separate",(0,rear-.06,1.52),(1.76,.13,.55),body)
    if covered:
        # Canvas-covered cargo bay makes this utility vehicle distinct.
        center=(bed_start+rear)/2
        box(a,"Cargo_canvas_top_separate",(0,center,2.05),(1.82,bed_len, .12),m["canvas"])
        for side in (-1,1):
            box(a,f"Cargo_canvas_side_{side}",(side*.86,center,1.78),(.08,bed_len,.55),m["canvas"])
        box(a,"Cargo_canvas_rear",(0,rear-.08,1.80),(1.7,.08,.5),m["canvas"])
        box(a,"Canvas_tear_rust",(.4,rear-.13,1.8),(.31,.03,.20),m["brown"])
    if roof_rack:
        seg=[]
        for x in (-.66,.66): seg.append(((x,cab_front+.25,2.42),(x,cab_rear-.03,2.42)))
        for y in (cab_front+.25,cab_rear-.03): seg.append(((-.66,y,2.42),(.66,y,2.42)))
        for x in (-.66,.66):
            for y in (cab_front+.25,cab_rear-.03): seg.append(((x,y,2.28),(x,y,2.42)))
        batch_beams(a,"Roof_rack_separate",seg,.055,m["frame"])
    for side in (-1,1):
        for wy in (front+1.05,rear-1.0):
            cylinder(a,f"Tyre_{side}_{wy:.1f}_separate",(side*.96,wy,.52),.52,.32,m["rubber"],axis=(1,0,0),sides=24)
            cylinder(a,f"Wheel_rim_{side}_{wy:.1f}_separate",(side*1.13,wy,.52),.28,.035,m["rust"],axis=(1,0,0),sides=20)
            cylinder(a,f"Wheel_hub_{side}_{wy:.1f}",(side*1.16,wy,.52),.09,.04,m["frame"],axis=(1,0,0),sides=16)
            spoke=[];arch=[]
            for i in range(6):
                t=2*math.pi*i/6
                spoke.append(((side*1.16,wy+.10*math.cos(t),.52+.10*math.sin(t)),
                              (side*1.16,wy+.25*math.cos(t),.52+.25*math.sin(t))))
            for i in range(8):
                t0=math.pi*i/8;t1=math.pi*(i+1)/8
                arch.append(((side*.94,wy+.56*math.cos(t0),.52+.56*math.sin(t0)),
                             (side*.94,wy+.56*math.cos(t1),.52+.56*math.sin(t1))))
            batch_beams(a,f"Wheel_spokes_{side}_{wy:.1f}",spoke,.035,m["frame"])
            batch_beams(a,f"Wheel_arch_trim_{side}_{wy:.1f}",arch,.075,m["frame"])
    return a


def cargo_crate(m):
    a=Asset("cargo_crate",(-33,-23,0))
    box(a,"Crate_wood_body",(0,0,.65),(1.3,1.3,1.3),m["wood"],uv_scale=.7)
    strips=[]
    for x in (-.54,.54):
        for y in (-.66,.66): strips.append(((x,y,.03),(x,y,1.27)))
    for y in (-.66,.66):
        for z in (.12,1.18): strips.append(((-.64,y,z),(.64,y,z)))
        strips.append(((-.52,y,.18),(.52,y,1.12)))
    for x in (-.66,.66):
        for z in (.12,1.18): strips.append(((x,-.64,z),(x,.64,z)))
        strips.append(((x,-.5,.18),(x,.5,1.12)))
    batch_beams(a,"Crate_reinforcement_planks_separate",strips,.085,m["trim"])
    return a


def cargo_pallet(m):
    a=Asset("cargo_pallet",(-30.7,-23,0))
    for y in (-.42,0,.42): box(a,f"Pallet_runner_{y}",(0,y,.075),(1.2,.12,.15),m["wood"],uv_scale=.8)
    for i in range(6):
        x=-.5+i*.2
        box(a,f"Pallet_top_plank_{i}",(x,0,.18),(.16,1.0,.06),m["wood"],uv_scale=.8)
    return a


def rusty_barrel(m):
    a=Asset("rusty_barrel",(-28.6,-23,0))
    cylinder(a,"Barrel_body",(0,0,.48),.34,.94,m["rust"],sides=24)
    for z in (.08,.32,.64,.88): cylinder(a,f"Barrel_rib_{z}",(0,0,z),.35,.045,m["frame"],sides=24)
    cylinder(a,"Barrel_top",(0,0,.96),.34,.035,m["rust"],sides=24)
    cylinder(a,"Barrel_bung",(.13,.08,.983),.045,.02,m["frame"],sides=12)
    return a


def wire_cage(m):
    a=Asset("wire_cage",(-25.2,-23,0))
    w,d,h=2.1,1.5,1.65
    box(a,"Cage_floor",(0,0,.08),(w,d,.16),m["wood"])
    seg=[]
    for x in (-w/2,w/2):
        for y in (-d/2,d/2): seg.append(((x,y,.1),(x,y,h)))
    for z in (.1,h):
        for x in (-w/2,w/2): seg.append(((x,-d/2,z),(x,d/2,z)))
        for y in (-d/2,d/2): seg.append(((-w/2,y,z),(w/2,y,z)))
    batch_beams(a,"Cage_frame_separate",seg,.06,m["frame"])
    for y in (-d/2,d/2):
        plane(a,f"Cage_wire_end_{y}",[(-w/2,y,.1),(w/2,y,.1),(w/2,y,h),(-w/2,y,h)],m["chain"],uv_scale=1.3)
    for x in (-w/2,w/2):
        plane(a,f"Cage_wire_side_{x}",[(x,-d/2,.1),(x,d/2,.1),(x,d/2,h),(x,-d/2,h)],m["chain"],uv_scale=1.3)
    return a


def fence_section(m):
    a=Asset("fence_section",(-16,-23,0))
    w,h=4,2.35
    for x in (-w/2,w/2):
        cylinder(a,f"Fence_post_{x}",(x,0,h/2),.07,h+.1,m["frame"],sides=12)
        box(a,f"Fence_post_foot_{x}",(x,0,.1),(.35,.35,.2),m["concrete"])
    beam(a,"Fence_top_rail",(-w/2,0,h-.04),(w/2,0,h-.04),.08,m["frame"])
    beam(a,"Fence_bottom_rail",(-w/2,0,.14),(w/2,0,.14),.055,m["frame"])
    plane(a,"Chainlink_mesh_separate",[(-w/2,0,.14),(w/2,0,.14),(w/2,0,h-.04),(-w/2,0,h-.04)],m["chain"],uv_scale=1.0)
    for z in (h+.15,h+.30): beam(a,f"Barbed_wire_run_{z}",(-w/2,0,z),(w/2,0,z),.025,m["rust"])
    return a


def fence_gate(m):
    a=Asset("fence_gate",(-9.3,-23,0))
    w,h=4.3,2.35
    for x in (-w/2,w/2):
        cylinder(a,f"Gate_post_{x}",(x,0,h/2),.10,h+.15,m["frame"],sides=12)
        box(a,f"Gate_post_foundation_{x}",(x,0,.12),(.42,.42,.24),m["concrete"])
    for side in (-1,1):
        pivot=bpy.data.objects.new(f"Gate_{'left' if side<0 else 'right'}_pivot_OPEN",None)
        a.collection.objects.link(pivot); pivot.parent=a.root
        pivot.location=(side*w/2,0,0)
        pivot.rotation_euler.z=side * (-math.pi/2)
        leaf_width=w/2-.10
        x0=0 if side < 0 else -leaf_width
        x1=leaf_width if side < 0 else 0
        seg=[((x0,0,.14),(x1,0,.14)),((x0,0,h-.04),(x1,0,h-.04)),
             ((x0,0,.14),(x0,0,h-.04)),((x1,0,.14),(x1,0,h-.04)),
             ((x0,0,.14),(x1,0,h-.04))]
        frame=batch_beams(a,f"Gate_leaf_{side}_frame_separate",seg,.07,m["frame"])
        frame.parent=pivot
        sheet=plane(a,f"Gate_leaf_{side}_chain_separate",[(x0,0,.14),(x1,0,.14),(x1,0,h-.04),(x0,0,h-.04)],m["chain"],uv_scale=1)
        sheet.parent=pivot
    return a


def concrete_barrier(m):
    a=Asset("concrete_barrier",(-4.8,-23,0))
    length=2.8
    profile=[(-.50,0),(.50,0),(.36,.48),(.23,1.05),(-.23,1.05),(-.36,.48)]
    verts=[]
    for x in (-length/2,length/2): verts += [(x,y,z) for y,z in profile]
    faces=[(5,4,3,2,1,0),tuple(range(6,12))]
    for i in range(6):
        j=(i+1)%6;faces.append((i,j,6+j,6+i))
    mesh_object(a,"Concrete_jersey_barrier",verts,faces,m["concrete"],uv_scale=.55)
    for x in (-.85,0,.85): box(a,f"Weathered_reflector_{x}",(x,-.37,.52),(.35,.018,.12),m["yellow"])
    return a


def antenna_mast(m):
    a=Asset("antenna_mast",(.1,-23,0))
    height=10
    box(a,"Antenna_concrete_base",(0,0,.15),(1.45,1.45,.3),m["concrete"])
    seg=[]
    for x in (-.48,.48):
        for y in (-.48,.48): seg.append(((x,y,.3),(x*.32,y*.32,height)))
    for i in range(7):
        z0=.35+i*(height-.35)/7; z1=.35+(i+1)*(height-.35)/7
        s0=.48*(1-.68*(z0-.3)/(height-.3));s1=.48*(1-.68*(z1-.3)/(height-.3))
        for side in (-1,1):
            seg += [((-s0,side*s0,z0),(s1,side*s1,z1)),((s0,side*s0,z0),(-s1,side*s1,z1)),
                    ((side*s0,-s0,z0),(side*s1,s1,z1)),((side*s0,s0,z0),(side*s1,-s1,z1))]
    batch_beams(a,"Lattice_mast_steel",seg,.055,m["frame"])
    cylinder(a,"Antenna_tip",(0,0,10.75),.035,1.5,m["frame"],sides=10)
    for z in (8.4,9.5): beam(a,f"Antenna_cross_{z}",(-.55,0,z),(.55,0,z),.035,m["frame"])
    return a


def light_pole(m):
    a=Asset("light_pole",(2.8,-23,0))
    box(a,"Lamp_foundation",(0,0,.15),(.65,.65,.3),m["concrete"])
    cylinder(a,"Lamp_pole",(0,0,3.55),.09,7.0,m["frame"],sides=14)
    beam(a,"Lamp_arm",(0,0,7),(0,-1.15,7.35),.11,m["frame"])
    box(a,"Lamp_fixture",(0,-1.2,7.32),(.65,.75,.20),m["frame"])
    box(a,"Lamp_glass",(0,-1.2,7.20),(.5,.6,.04),m["lamp"])
    return a


def loose_panels(m):
    roof=Asset("roof_panel",(7,-23,0))
    box(roof,"Corrugated_roof_panel_separate",(0,0,.06),(3.0,4.0,.12),m["roof"],uv_scale=.4)
    wall=Asset("wall_panel",(12,-23,0))
    box(wall,"Corrugated_wall_panel_separate",(0,0,1.5),(3,.12,3),m["roof"],uv_scale=.4)
    for z in (.2,2.8): box(wall,f"Panel_brace_{z}",(0,-.08,z),(3,.07,.08),m["frame"])
    door=Asset("sliding_door_panel",(17,-23,0))
    box(door,"Sliding_door_leaf_separate",(0,0,2.5),(4,.16,5),m["roof"],uv_scale=.4)
    for z in (.25,2.5,4.75): box(door,f"Door_reinforcement_{z}",(0,-.11,z),(4,.08,.10),m["frame"])
    cylinder(door,"Door_pull_handle",(1.65,-.19,1.1),.05,.45,m["frame"],axis=(0,0,1),sides=12)


def runway(m):
    a=Asset("runway_10x10",(24,-12,0))
    box(a,"Runway_cracked_asphalt_module_10m",(0,0,-.10),(10,10,.20),m["asphalt"],uv_scale=.28)
    # Segmented inset markings look worn and remain independently editable.
    for i,(y,length) in enumerate([(-4.45,1.0),(-3.3,.95),(-2.25,.7),(-.65,1.55),(.3,.23),(1.25,1.1),(2.55,.8),(3.55,.95),(4.6,.45)]):
        box(a,f"Faded_runway_marking_{i}",(0,y,.007),(.24,length,.014),m["white"])
    # Flat dark crack strips with sparse weeds provide actual geometry above the photo texture.
    segments=[]
    for offset in (-3,2.3):
        p=(offset,-4.8,.014)
        for i in range(7):
            q=(offset+RANDOM.uniform(-.5,.5),-4.8+(i+1)*1.4,.014)
            segments.append((p,q));p=q
    batch_beams(a,"Surface_crack_strips",segments,.035,m["rubber"])
    for i in range(26):
        x=RANDOM.choice((-1,1))*RANDOM.uniform(3.9,4.85); y=RANDOM.uniform(-4.8,4.8)
        z=RANDOM.uniform(.12,.28)
        blade=box(a,f"Runway_edge_weed_{i}",(x,y,z/2),(.03,.025,z),m["grass"],rotation=(RANDOM.uniform(-.25,.25),RANDOM.uniform(-.25,.25),0))
    return a


def editor_marker(m, kind, stage):
    a=Asset("marker_"+kind,stage)
    colors={"infected":"marker_enemy","loot":"marker_loot","story":"marker_story"}
    # Visible helper geometry is intentionally separate from the empty.
    cylinder(a,"EDITOR_ONLY_colored_base",(0,0,.025),.36,.05,m[colors[kind]],sides=20)
    cylinder(a,"EDITOR_ONLY_stem",(0,0,.40),.04,.75,m[colors[kind]],sides=12)
    verts=[(-.18,-.18,.78),(.18,-.18,.78),(.18,.18,.78),(-.18,.18,.78),(0,0,1.18)]
    mesh_object(a,"EDITOR_ONLY_marker_tip",verts,[(3,2,1,0),(0,1,4),(1,2,4),(2,3,4),(3,0,4)],m[colors[kind]])
    a.marker("MARKER_"+kind.upper(),(0,0,0),kind+" placeholder only; no gameplay")
    return a


def import_nature(name, source, stage, scale=1, extra=()):
    a=Asset(name,stage)
    before=set(bpy.data.objects)
    path=ROOT / "assets/models/nature_real" / source
    result=bpy.ops.import_scene.gltf(filepath=str(path))
    if "FINISHED" not in result:
        raise RuntimeError(f"Could not import {path}")
    imported=set(bpy.data.objects)-before
    if not imported:
        raise RuntimeError(f"No objects imported from {path}")
    for obj in imported:
        for collection in list(obj.users_collection): collection.objects.unlink(obj)
        a.collection.objects.link(obj)
    roots=[obj for obj in imported if obj.parent not in imported]
    for obj in roots:
        obj.parent=a.root
        obj.location *= scale
        obj.scale *= scale
    # Copies share mesh and textures and are still separate editable objects.
    if len(roots)==1:
        for i,(x,y,s) in enumerate(extra):
            dup=roots[0].copy()
            dup.data=roots[0].data
            dup.name=f"{name}_instance_{i+1}"
            a.collection.objects.link(dup)
            dup.parent=a.root
            dup.location += Vector((x,y,0))
            dup.scale *= s
    a.root["source_credit"]="Poly Haven CC0; see kit README"
    return a


def import_abandoned_sedan():
    """Include the project's existing CC BY sedan as a bonus fourth wreck."""
    a=Asset("abandoned_sedan",(27,-8,0))
    before=set(bpy.data.objects)
    path=ROOT / "assets/models/props/abandoned_sedan.glb"
    result=bpy.ops.import_scene.gltf(filepath=str(path))
    if "FINISHED" not in result:
        raise RuntimeError(f"Could not import {path}")
    imported=set(bpy.data.objects)-before
    for obj in imported:
        for collection in list(obj.users_collection):collection.objects.unlink(obj)
        a.collection.objects.link(obj)
    roots=[obj for obj in imported if obj.parent not in imported]
    pivot=bpy.data.objects.new("Sedan_scale_and_orientation",None)
    a.collection.objects.link(pivot)
    pivot.parent=a.root
    pivot.scale=(.08,.08,.08)
    pivot.rotation_euler.z=math.pi/2
    pivot.location=(.214,-.052,.036)
    for obj in roots:
        obj.parent=pivot
    a.root["source_credit"]=("Abandoned Generic Sedan 2 by Rashad Ibrahimli; scaled and re-exported; "
                             "CC BY 4.0 https://creativecommons.org/licenses/by/4.0/; "
                             "https://sketchfab.com/3d-models/abandoned-generic-sedan-2-game-ready-db2df46c49f9441286c84c66208ef7ac")
    return a


def spruce_branch_cards(a, m):
    """Add spruce-like branch cards to the sparse CC0 pine trunk/branches."""
    verts=[];faces=[];branches=[]
    for level in range(13):
        z=1.45+level*.70
        radius=max(.4,3.7*(1-z/11.8))
        count=10 if level<9 else 8
        for i in range(count):
            angle=2*math.pi*(i/count)+level*.41+RANDOM.uniform(-.12,.12)
            r=radius*RANDOM.uniform(.80,1.12)
            direction=Vector((math.cos(angle),math.sin(angle),0))
            side=Vector((-direction.y,direction.x,0))*r*.34
            inner=Vector((0,0,z))+direction*.12
            outer=direction*r+Vector((0,0,z-r*.18))
            base=len(verts)
            verts += [tuple(inner-side*.22),tuple(outer-side),tuple(outer+side),tuple(inner+side*.22)]
            faces.append((base,base+1,base+2,base+3))
            branches.append((tuple(inner),tuple(outer)))
    obj=mesh_object(a,"Spruce_like_needle_cards_separate",verts,faces,m["needles"])
    uv=obj.data.uv_layers.active
    coords=((0,0),(0,1),(1,1),(1,0))
    for polygon in obj.data.polygons:
        for index,li in enumerate(polygon.loop_indices):uv.data[li].uv=coords[index]
    batch_beams(a,"Spruce_branch_stems_separate",branches,.035,m["brown"])


def presentation(m):
    # This floor, lighting and camera are NOT selected for individual GLB exports.
    verts,faces=box_data((104,70,.18))
    mesh=bpy.data.meshes.new("Display_ground_mesh")
    mesh.from_pydata(verts,[],faces);mesh.update();uv_project(mesh,.18)
    mesh.materials.append(m["concrete"])
    ground=world_object("DISPLAY ONLY - not part of any asset","MESH",mesh,(0,2,-.27))
    camera_data=bpy.data.cameras.new("Asset overview camera")
    cam=world_object("Asset overview camera","CAMERA",camera_data,(74,-102,83))
    target=Vector((-1,3,5.0))
    cam.rotation_euler=(target-cam.location).to_track_quat("-Z","Y").to_euler()
    camera_data.type="ORTHO";camera_data.ortho_scale=116
    bpy.context.scene.camera=cam
    light_data=bpy.data.lights.new("Cloudy daylight",type="SUN")
    light_data.energy=2.1;light_data.angle=math.radians(18)
    sun=world_object("Cloudy daylight","LIGHT",light_data,(0,0,28))
    sun.rotation_euler=(math.radians(26),math.radians(-27),math.radians(-28))
    return cam


def export_assets():
    print(f"Exporting {len(ASSETS)} independent GLBs",flush=True)
    for name,a in ASSETS.items():
        old_location=a.root.location.copy()
        a.root.location=(0,0,0)
        bpy.context.view_layer.update()
        bpy.ops.object.select_all(action="DESELECT")
        for obj in a.collection.objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active=a.root
        filepath=str(GLB_DIR/(name+".glb"))
        try:
            result=bpy.ops.export_scene.gltf(filepath=filepath,export_format="GLB",
                 use_selection=True,export_yup=True,export_apply=True,export_animations=False,
                 export_cameras=False,export_lights=False,export_extras=True)
            if "FINISHED" not in result:
                raise RuntimeError(f"Export failed for {name}: {result}")
        finally:
            a.root.location=old_location
        print(f"EXPORTED {name} ({os.path.getsize(filepath):,} bytes)",flush=True)


def render_preview(cam):
    scene=bpy.context.scene
    scene.render.engine="CYCLES"
    scene.cycles.samples=24
    scene.cycles.use_denoising=True
    scene.render.resolution_x=1800
    scene.render.resolution_y=1080
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="JPEG"
    scene.render.image_settings.quality=88
    scene.render.filepath=str(OUT/"airport_kit_preview.jpg")
    bpy.ops.render.render(write_still=True)
    # A second honest view of the real interior with its removable roof hidden.
    old_hides={}
    for name,asset in ASSETS.items():
        for obj in asset.collection.objects:
            hide = name != "hangar_large" or obj.name == "Roof_arched_separate" or obj.name.startswith("Roof_vent_")
            if hide:
                old_hides[obj]=obj.hide_render
                obj.hide_render=True
    old_location=cam.location.copy();old_rotation=cam.rotation_euler.copy()
    old_scale=cam.data.ortho_scale
    cam.location=Vector((-26+30,22-40,33))
    cam.rotation_euler=(Vector((-26,22,3))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.ortho_scale=54
    scene.render.resolution_x=1400;scene.render.resolution_y=1000
    scene.cycles.samples=20
    scene.render.filepath=str(OUT/"hangar_interior_preview.jpg")
    bpy.ops.render.render(write_still=True)
    for obj,hide in old_hides.items():obj.hide_render=hide
    old_hides={}
    for name,asset in ASSETS.items():
        for obj in asset.collection.objects:
            is_roof=(obj.name.startswith(("Roof_flat", "Roof_parapet", "Solar_", "Roof_vent_service")))
            hide=name != "service_building" or is_roof
            if hide:
                old_hides[obj]=obj.hide_render
                obj.hide_render=True
    cam.location=Vector((-31+24,-8-31,23))
    cam.rotation_euler=(Vector((-31,-8,1.5))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.ortho_scale=29
    scene.render.resolution_x=1200;scene.render.resolution_y=900
    scene.cycles.samples=18
    scene.render.filepath=str(OUT/"service_interior_preview.jpg")
    bpy.ops.render.render(write_still=True)
    for obj,hide in old_hides.items():obj.hide_render=hide
    cam.location=old_location;cam.rotation_euler=old_rotation;cam.data.ortho_scale=old_scale


def main():
    reset_scene()
    m=init_materials()
    hangar_large(m)
    hangar_small(m)
    control_tower(m)
    service_building(m)
    fuel_canopy(m);fuel_tank(m);fuel_pump(m)
    pickup(m,"pickup_olive",(9,-8,0),m["green"],roof_rack=True)
    pickup(m,"pickup_red",(15,-8,0),m["red"])
    pickup(m,"utility_truck",(21,-8,0),m["sand"],covered=True)
    import_abandoned_sedan()
    cargo_crate(m);cargo_pallet(m);rusty_barrel(m);wire_cage(m)
    fence_section(m);fence_gate(m);concrete_barrier(m);antenna_mast(m);light_pole(m)
    loose_panels(m)
    # Keep the display runway away from the three vehicles.
    r=runway(m);r.root.location=(27,-23,0)
    pine=import_nature("pine_tree","pine.glb",(38,-7,0),scale=.8)
    spruce_branch_cards(pine,m)
    import_nature("grass_clump","grass.glb",(34,-22,0),scale=1.4,
                  extra=((.28,.1,.8),(-.22,.14,.7),(.08,-.22,1)))
    import_nature("shrub","sorrel.glb",(37,-22,0),scale=13,
                  extra=((.45,.16,.9),(-.35,.10,.7)))
    import_nature("rock_cluster","rock_07.glb",(41,-22,0),scale=6,
                  extra=((.8,0,.6),(-.55,.2,.65)))
    editor_marker(m,"infected",(-22,-28,0))
    editor_marker(m,"loot",(-20.8,-28,0))
    editor_marker(m,"story",(-19.6,-28,0))
    cam=presentation(m)
    export_assets()
    # Pack textures from both the created and reused models into the native file.
    bpy.ops.file.pack_all()
    bpy.context.preferences.filepaths.save_version=0
    blend_path=str(OUT/"airport_kit.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print("Saved",blend_path,flush=True)
    if "--skip-render" not in sys.argv:
        render_preview(cam)
        print("Saved overview and interior previews",flush=True)
    print("DONE: airfield kit contains",len(ASSETS),"independent assets",flush=True)


if __name__=="__main__":
    main()
