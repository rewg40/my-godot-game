#!/usr/bin/env python3
"""Rig the user's static T-pose hero with the existing CC0 survivor skeleton.

The original downloaded model has UVs/PBR maps but no skin or animation. This
script fits it to the already-licensed Quaternius rig and transfers smooth
weights from the existing male survivor surface. Its original geometry and
maps remain recognizable; the known Idle/Walk/Run/Jump/Punch/SwordSlash clips
and hand bones make the new main character usable without changing NPCs.

Requires NumPy and SciPy. Run after optimize_uploaded_model.cjs:
    python tools/rig_user_hero.py optimized.glb assets/models/hero/user_hero.glb
"""
from __future__ import annotations

import copy
import json
import struct
import sys
from pathlib import Path

import numpy as np
from scipy.sparse import coo_matrix
from scipy.spatial import cKDTree
from scipy.spatial.transform import Rotation

TEMPLATE = Path("assets/models/survivors/male.glb")


def read_glb(path):
    raw = Path(path).read_bytes()
    magic, version, length = struct.unpack_from("<4sII", raw)
    if magic != b"glTF" or version != 2 or length != len(raw):
        raise ValueError(f"Invalid GLB: {path}")
    n, kind = struct.unpack_from("<I4s", raw, 12)
    if kind != b"JSON":
        raise ValueError("Missing GLB JSON chunk")
    gltf = json.loads(raw[20:20+n])
    nbin, kind = struct.unpack_from("<I4s", raw, 20+n)
    if kind != b"BIN\0":
        raise ValueError("Missing GLB binary buffer")
    return gltf, bytearray(raw[28+n:28+n+nbin])


def view_accessor(gltf, data, index):
    a = gltf["accessors"][index]
    v = gltf["bufferViews"][a["bufferView"]]
    dtype = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}[a["componentType"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
    size = np.dtype(dtype).itemsize
    return np.ndarray((a["count"], width), dtype, data,
                      offset=v.get("byteOffset", 0) + a.get("byteOffset", 0),
                      strides=(v.get("byteStride", width * size), size))


def append_accessor(gltf, data, array, typ, component, target=None):
    while len(data) % 4:
        data.append(0)
    offset = len(data)
    raw = array.tobytes()
    data.extend(raw)
    view = {"buffer": 0, "byteOffset": offset, "byteLength": len(raw)}
    if target is not None:
        view["target"] = target
    gltf["bufferViews"].append(view)
    gltf["accessors"].append({"bufferView": len(gltf["bufferViews"]) - 1,
                              "componentType": component, "count": len(array), "type": typ})
    return len(gltf["accessors"]) - 1


def transfer_weights(vertices, triangles, template, template_data):
    source = template["meshes"][2]["primitives"][0]["attributes"]
    template_vertices = view_accessor(template, template_data, source["POSITION"]).copy()
    source_joints = view_accessor(template, template_data, source["JOINTS_0"]).copy()
    source_weights = view_accessor(template, template_data, source["WEIGHTS_0"]).copy()
    joint_count = len(template["skins"][0]["joints"])
    full_template = np.zeros((len(template_vertices), joint_count), dtype=np.float32)
    for column in range(4):
        np.add.at(full_template, (np.arange(len(template_vertices)), source_joints[:, column]), source_weights[:, column])

    # Both models face +Z in a T-pose. Their proportions are close but the new
    # palms face forward, whereas the template palms face down. Query the rig
    # in its own palm coordinates so finger weights select the correct digits;
    # only the weight lookup is transformed, not the supplied visible geometry.
    lookup = vertices.copy()
    arm = (vertices[:, 1] > 1.20) & (np.abs(vertices[:, 0]) > 0.23)
    amount = np.clip((np.abs(vertices[:, 0]) - .23) / .40, 0, 1)
    lookup[arm, 2] -= .060 * amount[arm]
    hand_blend = np.clip((np.abs(vertices[:, 0]) - .62) / .10, 0, 1)
    hand_blend *= (vertices[:, 1] > 1.25)
    # Inverse of the wrist + 90-degree palm fit in fit_skeleton_to_palms().
    palm_y = 1.456 - (vertices[:, 2] - .045)
    palm_z = -.065 + (vertices[:, 1] - 1.435)
    palm_x = np.sign(vertices[:, 0]) * (.706 + np.abs(vertices[:, 0]) - .68)
    lookup[:, 0] = lookup[:, 0] * (1 - hand_blend) + palm_x * hand_blend
    lookup[:, 1] = lookup[:, 1] * (1 - hand_blend) + palm_y * hand_blend
    lookup[:, 2] = lookup[:, 2] * (1 - hand_blend) + palm_z * hand_blend
    distances, indices = cKDTree(template_vertices).query(lookup, k=6, workers=1)
    influence = 1.0 / np.maximum(distances, .006) ** 2
    influence /= influence.sum(axis=1, keepdims=True)
    initial = np.einsum("nk,nkj->nj", influence.astype(np.float32), full_template[indices])

    # UV seams have duplicate positions. Smooth across actual mesh edges and
    # welded seam positions, preventing long, stretched triangles at joints.
    _, seam_ids = np.unique(np.round(vertices, 5), axis=0, return_inverse=True)
    point_count = int(seam_ids.max()) + 1
    welded = np.zeros((point_count, joint_count), dtype=np.float32)
    np.add.at(welded, seam_ids, initial)
    welded /= np.bincount(seam_ids)[:, None]
    t = seam_ids[triangles]
    row = np.concatenate([t[:, 0], t[:, 1], t[:, 2], t[:, 1], t[:, 2], t[:, 0], np.arange(point_count)])
    col = np.concatenate([t[:, 1], t[:, 2], t[:, 0], t[:, 0], t[:, 1], t[:, 2], np.arange(point_count)])
    adjacency = coo_matrix((np.ones(len(row), dtype=np.float32), (row, col)), shape=(point_count, point_count)).tocsr()
    adjacency.data[:] = 1.0
    adjacency = adjacency.multiply(1 / np.asarray(adjacency.sum(axis=1))).tocsr()
    for _ in range(40):
        welded = 0.5 * welded + 0.5 * (adjacency @ welded)
    full = welded[seam_ids]
    order = np.argsort(full, axis=1)[:, -4:][:, ::-1]
    weights = np.take_along_axis(full, order, axis=1).astype("<f4")
    totals = weights.sum(axis=1, keepdims=True)
    if np.any(totals < 1e-6):
        raise ValueError("Some vertices have no transferred weights")
    weights /= totals
    return order.astype("u1"), weights


def fit_skeleton_to_palms(template, data):
    """Fit wrist/finger pivots to the uploaded palms without altering the mesh.

    The uploaded palms face +Z in the bind pose, while the CC0 template's
    palms face down. Rotate just the finger chains into the new palm plane,
    update inverse binds, and preserve each animation's rotation relative to
    its original rest orientation. Arm and body animations remain unchanged.
    """
    nodes = template["nodes"]
    by_name = {node.get("name"): i for i, node in enumerate(nodes)}
    parents = {child: i for i, node in enumerate(nodes) for child in node.get("children", [])}

    def global_matrices():
        cache = {}
        def world(i):
            if i not in cache:
                node = nodes[i]
                matrix = np.eye(4)
                matrix[:3, :3] = Rotation.from_quat(node.get("rotation", [0, 0, 0, 1])).as_matrix()
                matrix[:3, :3] @= np.diag(node.get("scale", [1, 1, 1]))
                matrix[:3, 3] = node.get("translation", [0, 0, 0])
                cache[i] = world(parents[i]) @ matrix if i in parents else matrix
            return cache[i]
        for i in range(len(nodes)):
            world(i)
        return cache

    before = global_matrices()
    twist = Rotation.from_euler("x", -90, degrees=True).as_matrix()
    adjusted_roots = {}
    for suffix, sign in (("l", 1), ("r", -1)):
        hand = by_name[f"hand_{suffix}"]
        old_hand = before[hand]
        new_hand = old_hand.copy()
        new_hand[:3, 3] = [sign * .68, 1.435, .045]
        local_position = np.linalg.inv(before[parents[hand]]) @ np.r_[new_hand[:3, 3], 1.0]
        nodes[hand]["translation"] = local_position[:3].tolist()
        for finger in ("index", "middle", "ring", "pinky", "thumb"):
            root = by_name[f"{finger}_01_{suffix}"]
            old_local = Rotation.from_quat(nodes[root].get("rotation", [0, 0, 0, 1]))
            wanted = before[root].copy()
            wanted[:3, :3] = twist @ before[root][:3, :3]
            wanted[:3, 3] = new_hand[:3, 3] + twist @ (before[root][:3, 3] - old_hand[:3, 3])
            local = np.linalg.inv(new_hand) @ wanted
            new_local = Rotation.from_matrix(local[:3, :3])
            nodes[root]["translation"] = local[:3, 3].tolist()
            nodes[root]["rotation"] = new_local.as_quat().tolist()
            adjusted_roots[root] = new_local * old_local.inv()

    # Animation rotation values are absolute local quaternions, so multiply
    # by the rest-frame change for each affected finger root.
    changed_accessors = set()
    for animation in template["animations"]:
        for channel in animation["channels"]:
            joint = channel["target"]["node"]
            if joint not in adjusted_roots or channel["target"]["path"] != "rotation":
                continue
            output = animation["samplers"][channel["sampler"]]["output"]
            if output in changed_accessors:
                raise ValueError("Unexpected shared finger animation accessor")
            values = view_accessor(template, data, output)
            values[:] = (adjusted_roots[joint] * Rotation.from_quat(values.copy())).as_quat()
            changed_accessors.add(output)
    after = global_matrices()
    matrices = view_accessor(template, data, template["skins"][0]["inverseBindMatrices"])
    for i, joint in enumerate(template["skins"][0]["joints"]):
        matrices[i] = np.linalg.inv(after[joint]).T.reshape(16).astype(np.float32)


def main(source, destination):
    model, data = read_glb(source)
    template, template_data = read_glb(TEMPLATE)
    if len(model["meshes"]) != 1 or len(model["meshes"][0]["primitives"]) != 1 or model.get("skins"):
        raise ValueError("Expected the unrigged user hero")
    primitive = model["meshes"][0]["primitives"][0]
    attributes = primitive["attributes"]
    triangles = view_accessor(model, data, primitive["indices"]).copy().reshape(-1, 3)
    positions = view_accessor(model, data, attributes["POSITION"])
    normals = view_accessor(model, data, attributes["NORMAL"])
    # The supplied node is rotated +90 degrees on X. Bake that transform and
    # scale to the 1.82 m survivor rig, with soles at zero.
    p = positions.copy()[:, [0, 2, 1]] * np.array([1, -1, 1], dtype=np.float32)
    n = normals.copy()[:, [0, 2, 1]] * np.array([1, -1, 1], dtype=np.float32)
    p[:, 1] -= p[:, 1].min()
    p *= 1.82 / float(p[:, 1].max())
    positions[:] = p
    normals[:] = n
    if "TANGENT" in attributes:
        tangents = view_accessor(model, data, attributes["TANGENT"])
        rotated = tangents.copy()[:, [0, 2, 1, 3]]
        rotated[:, 1] *= -1
        invalid = np.linalg.norm(rotated[:, :3], axis=1) < 1e-8
        axes = np.zeros((int(invalid.sum()), 3), dtype=np.float32)
        bad_normals = n[invalid]
        axes[np.arange(len(bad_normals)), np.where(np.abs(bad_normals[:, 0]) < .9, 0, 1)] = 1.0
        fallback = np.cross(bad_normals, axes)
        fallback /= np.maximum(np.linalg.norm(fallback, axis=1, keepdims=True), 1e-8)
        rotated[invalid, :3] = fallback
        tangents[:] = rotated
        del tangents
    position_accessor = model["accessors"][attributes["POSITION"]]
    position_accessor["min"] = p.min(axis=0).astype(float).tolist()
    position_accessor["max"] = p.max(axis=0).astype(float).tolist()
    joints, weights = transfer_weights(p, triangles, template, template_data)
    fit_skeleton_to_palms(template, template_data)
    # Release numpy views before extending the bytearray.
    del positions, normals
    attributes["JOINTS_0"] = append_accessor(model, data, joints, "VEC4", 5121, 34962)
    attributes["WEIGHTS_0"] = append_accessor(model, data, weights, "VEC4", 5126, 34962)

    # Copy only the template's inverse bind matrices and animation accessors.
    # Its meshes, materials and textures are not part of the new hero.
    needed_accessors = {template["skins"][0]["inverseBindMatrices"]}
    for animation in template["animations"]:
        for sampler in animation["samplers"]:
            needed_accessors.add(sampler["input"])
            needed_accessors.add(sampler["output"])
    needed_views = {template["accessors"][i]["bufferView"] for i in needed_accessors}
    view_remap = {}
    for index in sorted(needed_views):
        view = copy.deepcopy(template["bufferViews"][index])
        start = view.get("byteOffset", 0)
        chunk = template_data[start:start + view["byteLength"]]
        while len(data) % 4:
            data.append(0)
        view["byteOffset"] = len(data)
        data.extend(chunk)
        view_remap[index] = len(model["bufferViews"])
        model["bufferViews"].append(view)
    accessor_remap = {}
    for index in sorted(needed_accessors):
        accessor = copy.deepcopy(template["accessors"][index])
        accessor["bufferView"] = view_remap[accessor["bufferView"]]
        accessor_remap[index] = len(model["accessors"])
        model["accessors"].append(accessor)

    skin = copy.deepcopy(template["skins"][0])
    old_joints = skin["joints"]
    root_node = template["scenes"][template.get("scene", 0)]["nodes"][0]
    included = set(old_joints) | {root_node}
    old_nodes = sorted(included)
    remap = {old: i + 1 for i, old in enumerate(old_nodes)}
    model["nodes"] = [{"name": "SuppliedHeroMesh", "mesh": 0, "skin": 0}]
    for old in old_nodes:
        node = copy.deepcopy(template["nodes"][old])
        if "children" in node:
            node["children"] = [remap[c] for c in node["children"] if c in included]
            if not node["children"]:
                node.pop("children")
        node.pop("mesh", None)
        node.pop("skin", None)
        model["nodes"].append(node)
    skin["joints"] = [remap[x] for x in old_joints]
    if "skeleton" in skin:
        skin["skeleton"] = remap[skin["skeleton"]]
    skin["inverseBindMatrices"] = accessor_remap[skin["inverseBindMatrices"]]
    model["skins"] = [skin]
    model["scenes"][model.get("scene", 0)]["nodes"] = [0, remap[root_node]]
    model["animations"] = []
    for animation in template["animations"]:
        animation = copy.deepcopy(animation)
        for sampler in animation["samplers"]:
            sampler["input"] = accessor_remap[sampler["input"]]
            sampler["output"] = accessor_remap[sampler["output"]]
        for channel in animation["channels"]:
            channel["target"]["node"] = remap[channel["target"]["node"]]
        model["animations"].append(animation)
    # The removed invalid optional extension must not be advertised as used.
    model.pop("extensionsUsed", None)
    model.pop("extensionsRequired", None)
    while len(data) % 4:
        data.append(0)
    model["buffers"][0]["byteLength"] = len(data)
    encoded = json.dumps(model, separators=(",", ":")).encode()
    encoded += b" " * (-len(encoded) % 4)
    length = 12 + 8 + len(encoded) + 8 + len(data)
    Path(destination).parent.mkdir(parents=True, exist_ok=True)
    with open(destination, "wb") as out:
        out.write(struct.pack("<4sII", b"glTF", 2, length))
        out.write(struct.pack("<I4s", len(encoded), b"JSON")); out.write(encoded)
        out.write(struct.pack("<I4s", len(data), b"BIN\0")); out.write(data)
    print(f"{len(p)} vertices, {len(old_joints)} joints, {len(model['animations'])} animation clips; {length} bytes")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: python tools/rig_user_hero.py optimized.glb output.glb")
    main(*sys.argv[1:])
