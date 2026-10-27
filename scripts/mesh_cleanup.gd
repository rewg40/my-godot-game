extends RefCounted

# Godot 4.3's dummy renderer can report a stale mesh RID when an instanced
# MeshInstance3D is freed headlessly (godotengine/godot#86806). Detach meshes
# before disposal in headless tests; the real renderer keeps normal ownership.
static func before_free(node: Node) -> void:
	if DisplayServer.get_name() != "headless" or not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		(node as MeshInstance3D).mesh = null
	elif node is MultiMeshInstance3D:
		(node as MultiMeshInstance3D).multimesh = null
	for child in node.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).mesh = null
	for child in node.find_children("*", "MultiMeshInstance3D", true, false):
		(child as MultiMeshInstance3D).multimesh = null
