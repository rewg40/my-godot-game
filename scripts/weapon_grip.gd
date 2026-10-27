extends SkeletonModifier3D

# The shared survivor rig has open hands in its original clips. Curl the right
# fingers after animation playback while an item is equipped; Skeleton3D blends
# the modifier without changing the underlying animation resources.
const FINGER_CURL := [0.95, 1.25, 0.75]
var finger_bones: Array[Dictionary] = []

func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for finger in ["index", "middle", "ring", "pinky"]:
		for segment in range(3):
			var bone := skeleton.find_bone("%s_0%d_r" % [finger, segment + 1])
			if bone >= 0:
				finger_bones.append({"index": bone, "angle": FINGER_CURL[segment]})

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for entry in finger_bones:
		var bone: int = entry.index
		var pose := skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, pose * Quaternion(Vector3.RIGHT, entry.angle))
