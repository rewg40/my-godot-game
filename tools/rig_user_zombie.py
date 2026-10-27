#!/usr/bin/env python3
"""Skin the supplied static zombie and add restrained, procedural clips.

Input is a simplified copy of the user-provided glTF, not the original. Bones
are fitted to its existing hunched pose; translations and rotations preserve
that pose at bind time. Requires numpy and scipy. Coordinates below are in source units.
"""
import json, math, struct, sys
import numpy as np
from scipy.sparse import coo_matrix

SOURCE, DEST = sys.argv[1:3]
data = open(SOURCE, 'rb').read()
magic, version, total = struct.unpack_from('<4sII', data)
assert magic == b'glTF' and version == 2 and total == len(data)
json_size = struct.unpack_from('<I', data, 12)[0]
gltf = json.loads(data[20:20 + json_size])
binary_start = 20 + json_size + 8
binary_size = struct.unpack_from('<I', data, 20 + json_size)[0]
bin_data = bytearray(data[binary_start:binary_start + binary_size])

# The source's specular-color factor is outside the glTF extension's valid
# range. Removing that optional extension retains the three original PBR maps
# and avoids relying on inconsistent importer behavior.
for material in gltf.get('materials', []):
    extensions = material.get('extensions', {})
    extensions.pop('KHR_materials_specular', None)
    if not extensions: material.pop('extensions', None)
gltf['extensionsUsed'] = [x for x in gltf.get('extensionsUsed', []) if x != 'KHR_materials_specular']
gltf['extensionsRequired'] = [x for x in gltf.get('extensionsRequired', []) if x != 'KHR_materials_specular']
for key in ('extensionsUsed', 'extensionsRequired'):
    if not gltf[key]: gltf.pop(key)
primitive = gltf['meshes'][0]['primitives'][0]
assert len(gltf['meshes']) == 1 and len(gltf['meshes'][0]['primitives']) == 1
assert not gltf.get('skins') and not gltf.get('animations')

def view_accessor(index):
    a = gltf['accessors'][index]; v = gltf['bufferViews'][a['bufferView']]
    dtype = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a['componentType']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    size = np.dtype(dtype).itemsize
    return np.ndarray((a['count'], width), dtype, bin_data,
        offset=v.get('byteOffset', 0) + a.get('byteOffset', 0),
        strides=(v.get('byteStride', width * size), size))

triangles = view_accessor(primitive['indices']).copy().reshape(-1, 3)
positions = view_accessor(primitive['attributes']['POSITION'])
normals = view_accessor(primitive['attributes']['NORMAL'])
# The supplied mesh has a +90 degree X node rotation. Bake that rotation and
# scale its existing ~1.03 m height to ~1.72 m. +Z is the zombie's face.
p = positions.copy()[:, [0, 2, 1]] * np.array([1.0, -1.0, 1.0], dtype=np.float32)
n = normals.copy()[:, [0, 2, 1]] * np.array([1.0, -1.0, 1.0], dtype=np.float32)
SCALE = 1.72 / float(p[:,1].max() - p[:,1].min())
base_y = float(p[:,1].min())
# Recenter the soles on y=0 for the existing collision capsule.
p[:,1] -= base_y
positions[:] = p * SCALE
normals[:] = n
if 'TANGENT' in primitive['attributes']:
    tangents = view_accessor(primitive['attributes']['TANGENT'])
    rotated = tangents.copy()[:, [0, 2, 1, 3]]
    rotated[:, 1] *= -1
    # Degenerate UV triangles occasionally have no MikkTSpace tangent. Use
    # a unit vector orthogonal to the normal instead of an invalid zero.
    invalid = np.linalg.norm(rotated[:, :3], axis=1) < 1e-8
    fallback_axis = np.zeros((int(invalid.sum()), 3), dtype=np.float32)
    bad_normals = n[invalid]
    fallback_axis[np.arange(len(bad_normals)),
                  np.where(np.abs(bad_normals[:, 0]) < .9, 0, 1)] = 1.0
    fallback = np.cross(bad_normals, fallback_axis)
    fallback /= np.linalg.norm(fallback, axis=1, keepdims=True)
    rotated[invalid, :3] = fallback
    tangents[:] = rotated
    del tangents
pa = gltf['accessors'][primitive['attributes']['POSITION']]
pa['min'] = positions.min(axis=0).astype(float).tolist()
pa['max'] = positions.max(axis=0).astype(float).tolist()
# Release numpy views before extending the underlying bytearray.
del positions, normals

def bone(name, parent, x, y, z):
    return (name, parent, np.array([x, y - base_y, z], dtype=np.float32) * SCALE)

bones = [
    bone('Hips', -1,       .000, .505, -.045),
    bone('Spine', 0,       .000, .615, -.045),
    bone('Chest', 1,       .000, .755, -.025),
    bone('Neck', 2,        .100, .865,  .080),
    bone('Head', 3,        .140, .930,  .130),
    bone('UpperArmL', 2,   .135, .795, -.035),
    bone('LowerArmL', 5,   .175, .600, -.090),
    bone('HandL', 6,       .170, .415, -.100),
    bone('UpperArmR', 2,  -.120, .815, -.020),
    bone('LowerArmR', 8,  -.200, .640,  .095),
    bone('HandR', 9,      -.215, .525,  .120),
    bone('UpperLegL', 0,   .060, .490, -.045),
    bone('LowerLegL', 11,  .135, .275,  .050),
    bone('FootL', 12,      .200, .040, -.080),
    bone('UpperLegR', 0,  -.060, .490, -.045),
    bone('LowerLegR', 14, -.150, .300,  .070),
    bone('FootR', 15,     -.250, .040,  .025),
]

# Five anatomical chains, including a parent joint at each shoulder and hip.
# Selecting the closest chain prevents the nearby hand and leg from sharing
# unrelated weights, while blending each joint into its direct parent/child.
centers = np.array([b[2] for b in bones], np.float32)
def endpoint(x,y,z):
    return np.array([x, y-base_y, z], dtype=np.float32) * SCALE
chains = [
    ([0, 1, 2, 3, 4], endpoint(.14, 1.05, .13)),
    ([2, 5, 6, 7], endpoint(.17, .365, -.10)),
    ([2, 8, 9, 10], endpoint(-.215, .465, .12)),
    ([0, 11, 12, 13], endpoint(.20, .02, .02)),
    ([0, 14, 15, 16], endpoint(-.25, .02, .12)),
]
verts = p * SCALE
N = len(verts)
best_dist = np.full(N, np.inf, np.float32)
best_joint = np.zeros(N, np.uint16)
best_next = np.zeros(N, np.uint16)
best_blend = np.zeros(N, np.float32)
# Use closest line segment, with a smooth blend at joints. Every vertex has at
# most two influences and the full mesh always sums to exactly 1.
for chain, tail in chains:
    for segment, joint in enumerate(chain):
        start = centers[joint]
        end = centers[chain[segment+1]] if segment + 1 < len(chain) else tail
        axis = end - start
        t = np.clip(((verts-start) @ axis) / np.dot(axis,axis), 0, 1)
        dist = np.sum((verts-(start+t[:,None]*axis))**2, axis=1)
        # Parent segments overlap at the branch point; prefer the torso there.
        mask = dist < best_dist
        parent = chain[segment-1] if segment else joint
        following = chain[segment+1] if segment+1 < len(chain) else joint
        joint_a = np.where(t < .25, parent, joint).astype(np.uint16)
        joint_b = np.where(t < .25, joint, following).astype(np.uint16)
        x1 = np.clip((t + .25) / .5, 0, 1)
        x2 = np.clip((t - .75) / .5, 0, 1)
        blend = np.where(t < .25, x1*x1*(3-2*x1), x2*x2*(3-2*x2))
        best_dist[mask] = dist[mask]
        best_joint[mask] = joint_a[mask]
        best_next[mask] = joint_b[mask]
        best_blend[mask] = blend[mask]

# Smooth weights along actual mesh edges. A nearest-axis assignment alone
# makes triangles stretch if the two endpoints choose different limb chains.
# Weld identical positions for smoothing only so UV seams share weights.
_, seam_ids = np.unique(np.round(verts, 5), axis=0, return_inverse=True)
point_count = seam_ids.max() + 1
initial = np.zeros((N, len(bones)), dtype=np.float32)
initial[np.arange(N),best_joint] += 1-best_blend
initial[np.arange(N),best_next] += best_blend
welded = np.zeros((point_count, len(bones)), dtype=np.float32)
np.add.at(welded, seam_ids, initial)
welded /= np.bincount(seam_ids)[:, None]
t = seam_ids[triangles]
r = np.concatenate([t[:,0],t[:,1],t[:,2],t[:,1],t[:,2],t[:,0],np.arange(point_count)])
c = np.concatenate([t[:,1],t[:,2],t[:,0],t[:,0],t[:,1],t[:,2],np.arange(point_count)])
adjacency = coo_matrix((np.ones(len(r), dtype=np.float32),(r,c)),shape=(point_count,point_count)).tocsr()
adjacency.data[:] = 1.0
adjacency = adjacency.multiply(1/np.asarray(adjacency.sum(axis=1))).tocsr()
for _ in range(80):
    welded = 0.5*welded + 0.5*(adjacency @ welded)
full_weights = welded[seam_ids]
order = np.argsort(full_weights,axis=1)[:, -4:][:,::-1]
weights = np.take_along_axis(full_weights,order,axis=1).astype('<f4')
weights /= weights.sum(axis=1,keepdims=True)
joint_values = order.astype('<u2')
assert np.allclose(weights.sum(axis=1),1.0)

# Append aligned binary data and a glTF accessor.
def accessor(array, typ, component, target=None, bounds=False):
    while len(bin_data) % 4: bin_data.append(0)
    offset = len(bin_data)
    raw = array.tobytes()
    bin_data.extend(raw)
    view = {'buffer': 0, 'byteOffset': offset, 'byteLength': len(raw)}
    if target is not None: view['target'] = target
    gltf['bufferViews'].append(view)
    a = {'bufferView': len(gltf['bufferViews'])-1, 'componentType': component,
         'count': len(array), 'type': typ}
    if bounds:
        a['min'] = array.min(axis=0).astype(float).tolist()
        a['max'] = array.max(axis=0).astype(float).tolist()
    gltf['accessors'].append(a)
    return len(gltf['accessors'])-1

primitive['attributes']['JOINTS_0'] = accessor(joint_values, 'VEC4', 5123, 34962)
primitive['attributes']['WEIGHTS_0'] = accessor(weights, 'VEC4', 5126, 34962)

# The bind pose has translation-only bones; its inverse matrices therefore
# undo only those world-space translations. Matrices are stored column-major.
inverse = np.repeat(np.eye(4, dtype='<f4')[None,:,:], len(bones), axis=0)
inverse[:,0:3,3] = -centers
ibm = accessor(inverse.transpose(0,2,1).copy(), 'MAT4', 5126)

# Mesh and skeleton share the glTF scene root, avoiding transformed-mesh bind
# discrepancies in Godot's importer. Bone order equals JOINTS_0 indices.
gltf['nodes'] = [{'name': 'UserZombieMesh', 'mesh': 0, 'skin': 0}]
for i,(name,parent,pos) in enumerate(bones):
    local = pos - centers[parent] if parent >= 0 else pos
    gltf['nodes'].append({'name': name, 'translation': local.astype(float).tolist()})
for i,(_,parent,_) in enumerate(bones):
    if parent >= 0:
        gltf['nodes'][parent+1].setdefault('children', []).append(i+1)
gltf['scenes'][gltf.get('scene',0)]['nodes'] = [0, 1]
gltf['skins'] = [{'name':'ZombieRig', 'inverseBindMatrices':ibm,
                   'skeleton':1, 'joints':list(range(1,len(bones)+1))}]

# Rotations are authored around the already-posed bind skeleton. Positive X
# moves a hanging arm/leg backward; negative X reaches in the +Z direction.
def quat_xyz(x=0.0,y=0.0,z=0.0):
    cx,sx = math.cos(x/2),math.sin(x/2)
    cy,sy = math.cos(y/2),math.sin(y/2)
    cz,sz = math.cos(z/2),math.sin(z/2)
    return [sx*cy*cz-cx*sy*sz, cx*sy*cz+sx*cy*sz,
            cx*cy*sz-sx*sy*cz, cx*cy*cz+sx*sy*sz]

def add_clip(name, duration, pose, steps=12):
    ts = np.linspace(0, duration, steps+1, dtype='<f4')
    time_accessor = accessor(ts.reshape(-1,1), 'SCALAR', 5126, bounds=True)
    channels = []; samplers = []
    for bone_index in range(len(bones)):
        keys = [quat_xyz(*pose(float(t), bone_index)) for t in ts]
        if not any(abs(v) > 1e-7 for key in keys for v in key[:3]): continue
        values = np.array(keys, dtype='<f4')
        out = accessor(values, 'VEC4', 5126)
        samplers.append({'input':time_accessor,'output':out,'interpolation':'LINEAR'})
        channels.append({'sampler':len(samplers)-1,'target':{'node':bone_index+1,'path':'rotation'}})
    gltf.setdefault('animations',[]).append({'name':name,'samplers':samplers,'channels':channels})

def idle(t,i):
    phase = 2*math.pi*t/2.4
    slow = math.sin(phase); alt = math.sin(phase+0.7)
    table = {0:(0.015*slow,0,0.025*slow), 1:(0.025*slow,0,-0.025*slow),
             2:(0.025*alt,0.03*slow,0), 3:(0.015*slow,0,0.02*alt),
             4:(-0.025*slow,0,0.035*slow), 5:(0.055*slow,0,0),
             8:(-0.045*slow,0,0), 6:(0.025*alt,0,0), 9:(-0.02*alt,0,0)}
    return table.get(i,(0,0,0))

def locomotion(duration, speed):
    def pose(t,i):
        phase=2*math.pi*t/duration
        wave=math.sin(phase); twice=math.sin(phase*2)
        table={0:(0.015*twice,0,0.035*wave),1:(0.025*twice,0,-0.04*wave),
          2:(0.04*twice,0.06*wave,0), 4:(-0.05*twice,0,0.04*wave),
          5:(-0.24*speed*wave,0,0.035), 8:(0.20*speed*wave,0,-0.035),
          6:(0.08*speed*wave,0,0), 9:(-0.07*speed*wave,0,0),
          11:(0.24*speed*wave,0,0), 14:(-0.24*speed*wave,0,0),
          12:(0.07*speed*(1+wave),0,0), 15:(0.07*speed*(1-wave),0,0),
          13:(-0.04*speed*wave,0,0),16:(0.04*speed*wave,0,0)}
        return table.get(i,(0,0,0))
    return pose

def attack(t,i):
    # Reach forward rapidly, then return to the original hunched bind pose.
    t = t / .55
    amount = min(t/.28, 1.0) if t < .28 else max(0.0, (1-t)/.72)
    amount = amount*amount*(3-2*amount)
    table={0:(-.06*amount,0,0),1:(-.07*amount,0,0),2:(-.10*amount,0,0),
           4:(.07*amount,0,0),5:(-.72*amount,0,.08*amount),
           8:(-.64*amount,0,-.08*amount),6:(.20*amount,0,0),9:(.16*amount,0,0)}
    return table.get(i,(0,0,0))

add_clip('ZombieIdle', 2.4, idle)
add_clip('ZombieWalk', 1.1, locomotion(1.1,1.0))
add_clip('Run', .65, locomotion(.65,1.25))
add_clip('ZombieAttack', .55, attack)

while len(bin_data)%4: bin_data.append(0)
gltf['buffers'][0]['byteLength'] = len(bin_data)
encoded = json.dumps(gltf, separators=(',',':')).encode()
encoded += b' ' * (-len(encoded)%4)
length = 12+8+len(encoded)+8+len(bin_data)
with open(DEST,'wb') as out:
    out.write(struct.pack('<4sII', b'glTF',2,length))
    out.write(struct.pack('<I4s',len(encoded),b'JSON')); out.write(encoded)
    out.write(struct.pack('<I4s',len(bin_data),b'BIN\x00')); out.write(bin_data)
print(f'{N} vertices, {len(bones)} bones, {len(gltf["animations"])} clips; {length} bytes')
