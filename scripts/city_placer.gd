extends Node3D
## Автосборка разрушенного города на острове из спрайтов-фасадов.
## Каждое здание — Sprite3D с фиксированным ракурсом (-32°, 45°), сажается на
## поверхность рейкастом вниз. Дома с внутренними интерьерами получают Area3D
## -дверь у входа: при попадании персонажа сигналится entry_requested.
##
## Масштаб: PIXEL_SIZE задан так, что 1024px ≈ 5 этажей (~15 м). RADIUS —
## радиус зоны города относительно центра острова; координаты в LAYOUT —
## доли этого радиуса (x, z).

const CITY_DIR := "res://assets/city/"
const CAM_ROT := Vector3(-32.0, 45.0, 0.0)
const PIXEL_SIZE := 0.018
## Доля радиуса, на которой вход считается «перед зданием».
const DOOR_FRONT := 0.55

## [файл без .png, доля X, доля Z, масштаб, интерьер(имя сцены или "")]
const LAYOUT := [
	# --- жилые ---
	["b01_apartment_5f_torn", -0.30, -0.05, 1.00, "i02_stairwell"],
	["b02_apartment_5f_entrance", -0.30, 0.15, 1.00, "i01_apartment_room"],
	["b03_tower_9f_burnt", -0.12, 0.28, 1.10, ""],
	["b04_tower_9f_leaning", 0.10, 0.30, 1.10, ""],
	["b05_house_2f_roof", -0.55, 0.35, 0.80, "i01_apartment_room"],
	["b06_house_burnt", -0.60, 0.10, 0.80, ""],
	["b07_cottage", -0.48, 0.48, 0.75, ""],
	["b08_townhouse", -0.35, 0.42, 0.90, ""],
	["b09_highrise_modern", 0.22, -0.18, 1.20, "i07_lobby"],
	["b10_dormitory", -0.42, 0.50, 1.00, "i02_stairwell"],
	# --- общественные и коммерческие ---
	["b11_hospital", -0.42, -0.28, 1.00, "i04_hospital_corridor"],
	["b12_school", -0.45, 0.05, 0.95, "i05_classroom"],
	["b13_church", -0.18, -0.22, 0.90, ""],
	["b14_police", -0.28, 0.38, 0.90, ""],
	["b15_firestation", -0.40, 0.28, 0.85, ""],
	["b16_supermarket", -0.15, -0.38, 0.90, "i10_shop_interior"],
	["b17_mall", 0.12, -0.40, 1.00, "i10_shop_interior"],
	["b18_gasstation", 0.38, -0.30, 0.90, ""],
	["b19_office_tower", 0.30, 0.02, 1.10, "i07_lobby"],
	["b20_bank", 0.05, -0.25, 0.90, "i07_lobby"],
	["b21_pharmacy", -0.10, 0.08, 0.85, "i10_shop_interior"],
	["b22_cafe", -0.13, 0.18, 0.80, "i10_shop_interior"],
	["b23_cinema", -0.05, 0.45, 0.90, "i07_lobby"],
	["b24_hotel", 0.28, 0.28, 1.00, "i11_hotel_room"],
	["b25_factory", 0.45, 0.15, 1.10, "i09_factory_interior"],
	["b26_warehouse", 0.50, -0.05, 1.00, "i09_factory_interior"],
	["b27_depot", 0.48, 0.25, 1.00, ""],
	["b28_stadium", 0.18, 0.50, 1.20, ""],
	# --- инфраструктура (без интерьеров) ---
	["b29_skyscraper", 0.00, -0.05, 1.35, ""],
	["b30_water_tower", -0.52, -0.15, 1.00, ""],
	["b31_chimneys", -0.55, -0.35, 1.00, ""],
	["b32_cooling_tower", -0.55, -0.05, 1.00, ""],
	["b33_tv_tower", 0.55, -0.38, 1.00, ""],
	["b34_elevator", -0.25, -0.45, 1.00, ""],
	["b35_station", 0.15, 0.52, 1.00, "i06_subway_platform"],
	["b36_metro", -0.20, -0.30, 0.90, "i06_subway_platform"],
	["b37_parking", 0.35, -0.45, 1.00, "i08_parking_interior"],
	["b38_autoshop", 0.40, -0.15, 0.90, ""],
	["b39_bus_stop", -0.08, -0.12, 0.80, ""],
	["b40_crane", 0.55, 0.30, 1.20, ""],
	["b41_unfinished", -0.05, 0.40, 1.00, ""],
	["b42_bridge", 0.60, 0.10, 1.20, ""],
	["b43_overpass", 0.60, -0.28, 1.20, ""],
	["b44_tunnel", 0.05, 0.12, 1.00, "i12_tunnel_interior"],
	["b45_checkpoint", 0.62, -0.20, 0.90, ""],
	["b46_wall", 0.55, -0.10, 1.00, ""],
]

var _bounds := AABB()
var _doors: Array[Dictionary] = []

signal entry_requested(interior_name: String, building_name: String)

func _ready() -> void:
	var island: Node3D = get_parent().get_node("Island")
	var meshes: Array[Node] = []
	if island is MeshInstance3D:
		meshes.append(island)
	meshes.append_array(island.find_children("*", "MeshInstance3D", true, false))
	var first := true
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
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

func _ground_y(ss: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var from := Vector3(x, _bounds.end.y + 60.0, z)
	var to := Vector3(x, _bounds.position.y - 60.0, z)
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
	var h := tex.get_height() * sp.pixel_size
	sp.position = Vector3(x, y + h * 0.5, z)
	add_child(sp)
	var interior: String = str(spec[4])
	if not interior.is_empty():
		_add_door(sp, x, y, z, h, interior, str(spec[0]))

func _add_door(sp: Sprite3D, x: float, y: float, z: float, h: float, interior: String, bname: String) -> void:
	# Дверь ставится перед фасадом. Фасад развёрнут по CAM_ROT; «внешняя»
	# нормаль в плоскости XZ примерно вдоль поворота спрайта.
	var area := Area3D.new()
	area.name = "Door_" + bname
	var body := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.6, h * 0.45, 2.6)
	body.shape = shape
	area.add_child(body)
	area.position = Vector3(x, y + h * 0.22, z)
	area.rotation_degrees = CAM_ROT * Vector3(0, 1, 0)
	var d: Dictionary = {"area": area, "interior": interior, "building": bname}
	area.set_meta("interior", interior)
	area.set_meta("building", bname)
	area.body_entered.connect(_on_door_body_entered)
	add_child(area)
	_door_areas.append(area)

var _door_areas: Array[Area3D] = []

func _on_door_body_entered(body: Node3D) -> void:
	if body.name.begins_with("Player"):
		emit_signal("entry_requested", body.get_meta("interior", ""), body.get_meta("building", ""))