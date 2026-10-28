extends Node3D
## Автосборка города на острове: спрайты зданий и актёры ставятся на поверхность
## острова рейкастом вниз. Масштаб острова задаётся в main.tscn (transform Island).

const CITY_DIR := "res://assets/city/"
const CAM_ROT := Vector3(-32.0, 45.0, 0.0)   # как у рендеров: изометрия 3/4
const PIXEL_SIZE := 0.015                    # 1024 px ≈ 15.4 юнита (5 этажей)
const ACTOR_SCALE := 1.8

## [файл без .png, доля радиуса по X, доля радиуса по Z, масштаб]
const LAYOUT := [
	["b29_skyscraper", 0.00, -0.05, 1.35],
	["b13_church", -0.18, -0.22, 0.90],
	["b01_apartment_5f_torn", -0.30, -0.05, 1.00],
	["b02_apartment_5f_entrance", -0.30, 0.15, 1.00],
	["b03_tower_9f_burnt", -0.12, 0.28, 1.10],
	["b04_tower_9f_leaning", 0.10, 0.30, 1.10],
	["b09_highrise_modern", 0.22, -0.18, 1.20],
	["b19_office_tower", 0.30, 0.02, 1.10],
	["b11_hospital", -0.42, -0.28, 1.00],
	["b12_school", -0.45, 0.05, 0.95],
	["b16_supermarket", -0.15, -0.38, 0.90],
	["b17_mall", 0.12, -0.40, 1.00],
	["b18_gasstation", 0.38, -0.30, 0.90],
	["b23_cinema", -0.05, 0.45, 0.90],
	["b24_hotel", 0.28, 0.28, 1.00],
	["b14_police", -0.28, 0.38, 0.90],
	["b15_firestation", -0.40, 0.28, 0.85],
	["b20_bank", 0.05, -0.25, 0.90],
	["b25_factory", 0.45, 0.15, 1.10],
	["b26_warehouse", 0.50, -0.05, 1.00],
	["b30_water_tower", -0.52, -0.15, 1.00],
	["b35_station", 0.15, 0.52, 1.00],
	["b40_crane", 0.55, 0.30, 1.20],
	["b05_house_2f_roof", -0.55, 0.35, 0.80],
	["b06_house_burnt", -0.60, 0.10, 0.80],
	["b07_cottage", -0.48, 0.48, 0.75],
	["b39_bus_stop", -0.08, -0.12, 0.80],
	["b45_checkpoint", 0.62, -0.20, 0.90],
]

## [путь к glb, доля радиуса по X, доля радиуса по Z]
const ACTORS := [
	["res://assets/models/character.glb", -0.05, 0.10],
	["res://assets/models/zombi.glb", 0.06, 0.16],
	["res://assets/models/zombi.glb", -0.10, 0.20],
	["res://assets/models/zombi.glb", 0.14, 0.05],
]

var _bounds := AABB()


func _ready() -> void:
	var island: Node3D = get_parent().get_node("Island")
	var meshes: Array[Node] = []
	if island is MeshInstance3D:
		meshes.append(island)
	meshes.append_array(island.find_children("*", "MeshInstance3D", true, false))
	var first := true
	for n in meshes:
		var mi := n as MeshInstance3D
		mi.create_trimesh_collision()
		var gaabb: AABB = mi.get_global_transform() * mi.get_aabb()
		_bounds = gaabb if first else _bounds.merge(gaabb)
		first = false
	await get_tree().physics_frame
	var ss := get_world_3d().direct_space_state
	var radius := maxf(_bounds.size.x, _bounds.size.z) * 0.5
	var center := _bounds.get_center()
	for spec in LAYOUT:
		_add_building(spec, ss, center, radius)
	for a in ACTORS:
		_add_actor(a, ss, center, radius)
	_setup_camera(center, radius)


func _ground_y(ss: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var from := Vector3(x, _bounds.end.y + 50.0, z)
	var to := Vector3(x, _bounds.position.y - 50.0, z)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var res := ss.intersect_ray(q)
	return res.position.y if res else 0.0


func _add_building(spec: Array, ss: PhysicsDirectSpaceState3D, center: Vector3, radius: float) -> void:
	var tex: Texture2D = load(CITY_DIR + str(spec[0]) + ".png")
	if tex == null:
		push_warning("city_placer: нет текстуры " + str(spec[0]))
		return
	var x := center.x + float(spec[1]) * radius
	var z := center.z + float(spec[2]) * radius
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.pixel_size = PIXEL_SIZE * float(spec[3])
	sp.rotation_degrees = CAM_ROT
	sp.shaded = true
	var y := _ground_y(ss, x, z)
	sp.position = Vector3(x, y + tex.get_height() * sp.pixel_size * 0.5, z)
	add_child(sp)


func _add_actor(a: Array, ss: PhysicsDirectSpaceState3D, center: Vector3, radius: float) -> void:
	var scene: PackedScene = load(str(a[0]))
	if scene == null:
		return
	var inst := scene.instantiate()
	var x := center.x + float(a[1]) * radius
	var z := center.z + float(a[2]) * radius
	inst.scale = Vector3(ACTOR_SCALE, ACTOR_SCALE, ACTOR_SCALE)
	inst.rotation_degrees = Vector3(0, randf() * 360.0, 0)
	add_child(inst)
	inst.position = Vector3(x, _ground_y(ss, x, z), z)


func _setup_camera(center: Vector3, radius: float) -> void:
	var cam: Camera3D = get_parent().get_node("Camera3D")
	if cam == null:
		return
	cam.current = true
	cam.fov = 45.0
	cam.position = center + Vector3(radius * 1.7, radius * 1.4, radius * 1.7)
	cam.look_at(center + Vector3(0, radius * 0.08, 0))
