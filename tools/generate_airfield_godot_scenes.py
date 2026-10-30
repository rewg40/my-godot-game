#!/usr/bin/env python3
"""Generate optional Godot scenes with passive colliders for the airfield kit.

Models remain standalone GLBs. These scenes do not touch the game world and
contain no game scripts. Boxes preserve entrances and the service room doorway.
"""
from pathlib import Path
import math

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / "assets/models/airport_kit"
OUTPUT = KIT / "godot_scenes"
OUTPUT.mkdir(parents=True, exist_ok=True)
MODEL_DIR = "res://assets/models/airport_kit/glb/"


def v3(x, y, z):
    return "Vector3(" + ", ".join(f"{v:.6f}".rstrip("0").rstrip(".") for v in (x, y, z)) + ")"


class Scene:
    def __init__(self, name):
        self.name = name
        self.models = []
        self.shapes = []

    def model(self, name, position=(0,0,0)):
        self.models.append((name, position))

    def box(self, name, position, size, rotation_z=0):
        # Coordinates accepted here are already in Godot X/Y-up/Z convention.
        assert min(size) > 0, f"Invalid dimensions for {self.name}/{name}"
        self.shapes.append((name, position, size, rotation_z))

    def blender_box(self, name, center, size):
        x,y,z = center; sx,sy,sz = size
        self.box(name, (x,z,-y), (sx,sz,sy))

    def sloped_roof(self, name, x0, y0, x1, y1, depth):
        # Godot's y is height; the unrotated box is horizontal along X.
        dx,dy=x1-x0,y1-y0
        length=math.hypot(dx,dy)
        self.box(name,((x0+x1)/2,(y0+y1)/2,0),(length+.08,.25,depth),math.atan2(dy,dx))

    def write(self):
        lines=[f'[gd_scene load_steps={1+len(self.models)+len(self.shapes)} format=3]', '']
        for i,(name,pos) in enumerate(self.models,1):
            lines.append(f'[ext_resource type="PackedScene" path="{MODEL_DIR}{name}.glb" id="model_{i}"]')
        lines.append('')
        for i,(name,pos,size,rot) in enumerate(self.shapes,1):
            lines += [f'[sub_resource type="BoxShape3D" id="shape_{i}"]',f'size = {v3(*size)}','']
        lines += [f'[node name="{self.name}" type="Node3D"]','']
        for i,(name,pos) in enumerate(self.models,1):
            lines += [f'[node name="Visual_{name}" parent="." instance=ExtResource("model_{i}")]']
            if pos != (0,0,0): lines.append(f'position = {v3(*pos)}')
            lines.append('')
        lines += ['[node name="Static_collision" type="StaticBody3D" parent="."]','']
        for i,(name,pos,size,rot) in enumerate(self.shapes,1):
            lines += [f'[node name="{name}" type="CollisionShape3D" parent="Static_collision"]',
                      f'position = {v3(*pos)}']
            if abs(rot) > 1e-8: lines.append(f'rotation = {v3(0,0,rot)}')
            lines += [f'shape = SubResource("shape_{i}")','']
        (OUTPUT / (self.name+'.tscn')).write_text('\n'.join(lines),encoding='utf-8')


def hangar(large=True):
    name='hangar_large' if large else 'hangar_small'
    s=Scene(name);s.model(name)
    w,d,h,door=(36,28,6,22) if large else (18,18,5.2,12)
    s.blender_box('Floor',(0,0,-.1),(w,d,.2))
    for side in (-1,1):
        s.blender_box(f'Side_wall_{side}',(side*(w/2-.12),0,h/2),(.24,d,h))
        pier=(w-door)/2
        s.blender_box(f'Front_pier_{side}',(side*(door/2+pier/2),-d/2+.12,h/2),(pier,.24,h))
        leaf=door/2
        s.blender_box(f'Parked_door_{side}',(side*(door/2+leaf/2),-d/2-.18,h/2-.10),(leaf,.20,h-.2))
    s.blender_box('Rear_wall',(0,d/2-.12,h/2),(w,.24,h))
    if large:
        rise=7
        for i in range(20):
            t0=math.pi*i/20;t1=math.pi*(i+1)/20
            s.sloped_roof(f'Roof_segment_{i:02d}',-w/2*math.cos(t0),h+rise*math.sin(t0),
                          -w/2*math.cos(t1),h+rise*math.sin(t1),d+.5)
        s.blender_box('Annex_floor',(-20.5,0,-.1),(5,20,.2))
        s.blender_box('Annex_outer_wall',(-22.88,0,1.75),(.24,20,3.5))
        s.blender_box('Annex_back',(-20.5,9.88,1.75),(5,.24,3.5))
        s.blender_box('Annex_front_left',(-22.15,-9.88,1.75),(1.7,.24,3.5))
        s.blender_box('Annex_front_right',(-18.85,-9.88,1.75),(1.7,.24,3.5))
        s.blender_box('Annex_door_header',(-20.5,-9.88,3),(1.6,.24,1))
    else:
        rise=3
        s.sloped_roof('Roof_left',-w/2,h,0,h+rise,d+.4)
        s.sloped_roof('Roof_right',0,h+rise,w/2,h,d+.4)
    s.write()


def front(s,w,d,h,door,window):
    """Separate wall pieces keep the door open; window glass blocks passage."""
    y=-d/2+.12
    for i,(l,r) in enumerate([(-w/2,door[0]),(door[1],window[0]),(window[1],w/2)]):
        s.blender_box(f'Front_wall_{i}',((l+r)/2,y,h/2),(r-l,.24,h))
    dh=2.45
    s.blender_box('Door_header',((door[0]+door[1])/2,y,(dh+h)/2),(door[1]-door[0],.24,h-dh))
    s.blender_box('Window_sill',((window[0]+window[1])/2,y,.5),(window[1]-window[0],.24,1))
    s.blender_box('Window_header',((window[0]+window[1])/2,y,(2.65+h)/2),(window[1]-window[0],.24,h-2.65))
    s.blender_box('Window_glass',((window[0]+window[1])/2,y,1.825),(window[1]-window[0],.05,1.65))
    width=door[1]-door[0]
    s.blender_box('Open_personnel_door',(door[0]-.07,-d/2-width/2,dh/2),(.12,width,dh))


def service_building():
    s=Scene('service_building');s.model('service_building')
    w,d,h=16,10,3.8
    s.blender_box('Floor',(0,0,-.1),(w,d,.2))
    front(s,w,d,h,(-4.8,-3.2),(1,5.3))
    s.blender_box('Back_wall',(0,d/2-.12,h/2),(w,.24,h))
    for side in (-1,1):s.blender_box(f'Side_wall_with_glass_{side}',(side*(w/2-.12),0,h/2),(.24,d,h))
    s.blender_box('Room_partition_front',(0,-3.25,h/2),(.16,3.5,h))
    s.blender_box('Room_partition_back',(0,3.25,h/2),(.16,3.5,h))
    s.blender_box('Room_partition_header',(0,0,(2.45+h)/2),(.16,3,h-2.45))
    s.blender_box('Roof',(0,0,h+.12),(w+.5,d+.5,.24))
    for y in (-4.25,4.25):s.blender_box(f'Awning_post_{y}',(11.1,y,1.48),(.13,.13,2.96))
    s.write()


def control_tower():
    s=Scene('control_tower');s.model('control_tower')
    w,d,h=14,10,3.7
    s.blender_box('Floor_ground',(0,0,-.12),(w,d,.24))
    front(s,w,d,h,(-4.6,-3),(0.4,4.8))
    s.blender_box('Back_wall',(0,d/2-.12,h/2),(w,.24,h))
    for side in (-1,1):s.blender_box(f'Side_wall_with_glass_{side}',(side*(w/2-.12),0,h/2),(.24,d,h))
    s.blender_box('Floor_upper_main',(-1.9,0,h),(10.2,d,.24))
    s.blender_box('Floor_upper_front',(5.1,-4.2,h),(3.8,1.6,.24))
    s.blender_box('Floor_upper_back',(5.1,4.3,h),(3.8,1.4,.24))
    s.blender_box('Stair_landing',(4.8,3,h),(1.55,1.2,.24))
    for i in range(18):
        z=(i+1)*h/18;y=-3.8+i*.36
        s.blender_box(f'Stair_step_{i+1:02d}',(4.8,y,z-.06),(1.55,.38,.12))
    top=9; sw=6.4; sd=6
    for x in (-sw/2,sw/2):s.blender_box(f'Shaft_side_with_glass_{x}',(x,0,(h+top)/2),(.24,sd,top-h))
    s.blender_box('Shaft_back',(0,sd/2,(h+top)/2),(sw,.24,top-h))
    for x in (-2.1,2.1):s.blender_box(f'Shaft_front_pier_{x}',(x,-sd/2,(h+top)/2),(2.2,.24,top-h))
    s.blender_box('Shaft_door_header',(0,-sd/2,(h+2.4+top)/2),(2,.24,top-h-2.4))
    s.blender_box('Observation_floor',(0,0,top),(10,8,.3))
    base=top+.15; ch=2.9
    for x in (-4.3,4.3):s.blender_box(f'Cabin_glass_side_{x}',(x,0,base+ch/2),(.08,6.5,ch))
    for y in (-3.25,3.25):s.blender_box(f'Cabin_glass_end_{y}',(0,y,base+ch/2),(8.6,.08,ch))
    s.blender_box('Cabin_roof',(0,0,base+ch+.15),(9.1,7,.3))
    s.write()


def fuel_station():
    s=Scene('fuel_station')
    s.model('fuel_canopy');s.model('fuel_tank',(-1,0,0));s.model('fuel_pump',(4.5,0,0))
    w,d,h=11,7,4.6
    for x in (-w/2+.2,w/2-.2):
        for y in (-d/2+.2,d/2-.2):s.blender_box(f'Canopy_post_{x}_{y}',(x,y,h/2),(.22,.22,h))
    s.blender_box('Canopy_roof',(0,0,h+.14),(w+.6,d+.6,.28))
    s.blender_box('Tank_approximate',(-1,0,1.65),(2.3,4.8,2.3))
    s.blender_box('Pump',(4.5,0,1),(.95,.65,2))
    s.write()


def fence():
    s=Scene('fence_section');s.model('fence_section')
    s.box('Fence',(0,1.2,0),(4,2.4,.12));s.write()
    s=Scene('fence_gate');s.model('fence_gate')
    for side in (-1,1):
        s.box(f'Post_{side}',(side*2.15,1.2,0),(.2,2.5,.2))
        s.box(f'Open_gate_leaf_{side}',(side*2.15,1.23,-1.02),(.12,2.2,2.04))
    s.write()


def runway():
    s=Scene('runway_10x10');s.model('runway_10x10')
    s.box('Runway_floor',(0,-.1,0),(10,.2,10));s.write()


def main():
    hangar(True);hangar(False);service_building();control_tower()
    fuel_station();fence();runway()
    print('Generated', len(list(OUTPUT.glob('*.tscn'))), 'Godot scenes with passive colliders')


if __name__ == '__main__':
    main()
