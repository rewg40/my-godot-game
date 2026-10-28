extends Node3D
## Разрушенный городской район на острове: площадка 60 x 60 м с травяным
## покрытием, повторяющим рельеф, асфальтовой улицей, четырьмя полноценными
## 3D-руинами (GLB, восстановленными из чанков ветки arena/3014eb04),
## фасадными коробками и плоскими домами-спрайтами по периметру.
##
## Площадка выбрана скриптом по данным высот: самый плоский участок травяного
## квадранта в отрыве от спавна и квестовых точек (центр 79.5, 123.0).
## Все вертикали берутся из environment_3d.height_at(), поэтому посадка
## совпадает с рельефом, навигацией и миникартой 1:1.

const SITE := Vector2(79.5, 123.0)     # центр площадки в координатах острова
const PAD := 30.0                      # половина стороны, 60 x 60 м
const ROAD_WIDTH := 5.5
const GRASS_TEX := "res://assets/environment/textures/grass_short.jpg"
const ASPHALT_TEX := "res://assets/environment/textures/asphalt.jpg"

## Полноценные 3D-руины: модель, локальная позиция, поворот, масштаб.
## Модели юнит-размера (высота 0.57-0.70), масштаб даёт городские метры.
const RUINS := [
		{"model": "res://assets/city_3d/ruined_building_3f_a.glb", "at": Vector2(-15.0, -10.0), "yaw": 5.0, "scale": 15.0},
		{"model": "res://assets/city_3d/ruined_building_3f_b.glb", "at": Vector2(12.0, -10.5), "yaw": -8.0, "scale": 14.5},
		{"model": "res://assets/city_3d/ruined_building_2f.glb", "at": Vector2(-11.0, 10.5), "yaw": 171.0, "scale": 12.5},
		{"model": "res://assets/city_3d/ruined_building_3f_c.glb", "at": Vector2(13.0, 11.0), "yaw": 186.0, "scale": 14.0},
]

## Фасадные коробки: текстура, позиция, размер (Ш x В x Г).
const FACADES := [
		{"tex": "res://assets/city/facade_tower6.png", "at": Vector2(-20.0, -21.0), "size": Vector3(11, 19.0, 9)},
		{"tex": "res://assets/city/facade_w4.png", "at": Vector2(-4.0, -22.0), "size": Vector3(12, 13.0, 9)},
		{"tex": "res://assets/city/facade_store2.png", "at": Vector2(12.0, -21.5), "size": Vector3(10, 5.5, 8)},
		{"tex": "res://assets/city/facade_w2.png", "at": Vector2(24.0, -20.0), "size": Vector3(12, 8.0, 9)},
		{"tex": "res://assets/city/facade_house1.png", "at": Vector2(1.0, 21.5), "size": Vector3(9, 7.0, 8)},
]

## Дома-спрайты по периметру (ракурс как в city_placer: наклон -32°, поворот 45°).
const SPRITES := [
		{"tex": "res://assets/city/b01_apartment_5f_torn.png", "at": Vector2(-26.0, -2.0), "scale": 1.0},
		{"tex": "res://assets/city/b02_apartment_5f_entrance.png", "at": Vector2(-25.0, 12.0), "scale": 1.0},
		{"tex": "res://assets/city/b03_tower_9f_burnt.png", "at": Vector2(2.0, -25.5), "scale": 1.1},
		{"tex": "res://assets/city/b04_tower_9f_leaning.png", "at": Vector2(18.0, -24.5), "scale": 1.1},
		{"tex": "res://assets/city/b05_house_2f_roof.png", "at": Vector2(-24.0, 22.0), "scale": 0.8},
		{"tex": "res://assets/city/b06_house_burnt.png", "at": Vector2(-9.0, 24.0), "scale": 0.8},
		{"tex": "res://assets/city/b07_cottage.png", "at": Vector2(25.5, 14.0), "scale": 0.75},
		{"tex": "res://assets/city/b08_townhouse.png", "at": Vector2(-25.5, -15.0), "scale": 0.9},
		{"tex": "res://assets/city/b09_highrise_modern.png", "at": Vector2(26.0, -14.0), "scale": 1.2},
		{"tex": "res://assets/city/b10_dormitory.png", "at": Vector2(5.0, 23.5), "scale": 1.0},
]

const SPRITE_PIXEL_SIZE := 0.018
const SPRITE_BASE_SCALE := 0.62

var _env: Node3D


func setup(env: Node3D) -> void:
		_env = env


func _ready() -> void:
		_build_pad()
		_build_road()
		_build_ruins()
		_build_facades()
		_build_sprites()


func _add_flat_collision(layer: MeshInstance3D, body_name: String) -> void:
		## Лёгкая коллизия плоского слоя: игрок стоит на слое, а не в нём.
		var body := StaticBody3D.new()
		body.name = body_name
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = layer.mesh.create_trimesh_shape()
		body.add_child(shape)
		layer.add_child(body)

func _ground(local: Vector2) -> float:
		return _env.height_at(SITE.x + local.x, SITE.y + local.y)


func _make_material(tex_path: String, uv_scale: float) -> StandardMaterial3D:
		var material := StandardMaterial3D.new()
		material.albedo_texture = load(tex_path)
		material.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
		material.roughness = 0.95
		return material


## Травяная площадка, повторяющая рельеф сеткой 16 x 16.
func _build_pad() -> void:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var steps := 16
		var cell := PAD * 2.0 / steps
		for iz in range(steps):
				for ix in range(steps):
						var x0 := -PAD + ix * cell
						var z0 := -PAD + iz * cell
						var corners := [
								Vector3(x0, _ground(Vector2(x0, z0)) + 0.07, z0),
								Vector3(x0 + cell, _ground(Vector2(x0 + cell, z0)) + 0.07, z0),
								Vector3(x0 + cell, _ground(Vector2(x0 + cell, z0 + cell)) + 0.07, z0 + cell),
								Vector3(x0, _ground(Vector2(x0, z0 + cell)) + 0.07, z0 + cell),
						]
						for tri in [[0, 1, 2], [0, 2, 3]]:
								for idx in tri:
										var v: Vector3 = corners[idx]
										surface.set_normal(Vector3.UP)
										surface.set_uv(Vector2(v.x, v.z) * 0.5)
										surface.add_vertex(v)
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "CityPad"
		mesh_inst.mesh = surface.commit()
		mesh_inst.material_override = _make_material(GRASS_TEX, 1.0)
		_add_flat_collision(mesh_inst, "CityPadBody")
		add_child(mesh_inst)


## Асфальтовая улица через площадку вдоль X, чуть выше травы.
func _build_road() -> void:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var steps := 20
		var cell := PAD * 2.0 / steps
		var half := ROAD_WIDTH * 0.5
		for ix in range(steps):
				var x0 := -PAD + ix * cell
				var corners := [
						Vector3(x0, _ground(Vector2(x0, -half)) + 0.13, -half),
						Vector3(x0 + cell, _ground(Vector2(x0 + cell, -half)) + 0.13, -half),
						Vector3(x0 + cell, _ground(Vector2(x0 + cell, half)) + 0.13, half),
						Vector3(x0, _ground(Vector2(x0, half)) + 0.13, half),
				]
				for tri in [[0, 1, 2], [0, 2, 3]]:
						for idx in tri:
								var v: Vector3 = corners[idx]
								surface.set_normal(Vector3.UP)
								surface.set_uv(Vector2(v.x, v.z) * 0.45)
								surface.add_vertex(v)
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "CityRoad"
		mesh_inst.mesh = surface.commit()
		mesh_inst.material_override = _make_material(ASPHALT_TEX, 1.0)
		_add_flat_collision(mesh_inst, "CityRoadBody")
		add_child(mesh_inst)


## Четыре восстановленные 3D-руины с триангулированной коллизией.
func _build_ruins() -> void:
		for ruin in RUINS:
				var packed := load(ruin["model"]) as PackedScene
				if packed == null:
						push_error("Модель руины не найдена: %s" % ruin["model"])
						continue
				var root := packed.instantiate() as Node3D
				var y := _ground(ruin["at"]) - 0.25
				root.position = Vector3(SITE.x + ruin["at"].x, y, SITE.y + ruin["at"].y)
				root.rotation_degrees.y = ruin["yaw"]
				root.scale = Vector3.ONE * ruin["scale"]
				var mesh_inst := root.find_children("*", "MeshInstance3D", true, false)
				if mesh_inst.is_empty():
						root.queue_free()
						continue
				var source := mesh_inst[0] as MeshInstance3D
				var body := StaticBody3D.new()
				body.collision_layer = 1
				body.collision_mask = 0
				var shape := CollisionShape3D.new()
				shape.shape = source.mesh.create_trimesh_shape()
				body.add_child(shape)
				root.add_child(body)
				root.add_to_group("city_building")
				add_child(root)


## Фасадные коробки с тёмной крышкой-заглушкой и простой коллизией.
func _build_facades() -> void:
		for item in FACADES:
				var size: Vector3 = item["size"]
				var ground := _ground(item["at"])
				var origin := Vector3(SITE.x + item["at"].x, ground + size.y * 0.5 - 0.2, SITE.y + item["at"].y)
				var mesh_inst := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = size
				mesh_inst.mesh = box
				mesh_inst.material_override = _make_material(item["tex"], 1.0)
				mesh_inst.position = origin
				var roof := MeshInstance3D.new()
				var cap := BoxMesh.new()
				cap.size = Vector3(size.x + 0.4, 0.3, size.z + 0.4)
				roof.mesh = cap
				roof.position = Vector3(0, size.y * 0.5 + 0.15, 0)
				var roof_material := StandardMaterial3D.new()
				roof_material.albedo_color = Color(0.16, 0.15, 0.14)
				roof_material.roughness = 1.0
				roof.material_override = roof_material
				mesh_inst.add_child(roof)
				var body := StaticBody3D.new()
				body.collision_layer = 1
				body.collision_mask = 0
				var shape := CollisionShape3D.new()
				var box_shape := BoxShape3D.new()
				box_shape.size = size + Vector3(0, 0.4, 0)
				shape.shape = box_shape
				body.add_child(shape)
				mesh_inst.add_child(body)
				mesh_inst.add_to_group("city_building")
				add_child(mesh_inst)


## Плоские дома-спрайты: та же логика, что city_placer, плюс коллизия-стенка.
func _build_sprites() -> void:
		for item in SPRITES:
				var texture := load(item["tex"]) as Texture2D
				if texture == null:
						continue
				var sprite := Sprite3D.new()
				sprite.texture = texture
				sprite.pixel_size = SPRITE_PIXEL_SIZE
				var final_scale: float = item["scale"] * SPRITE_BASE_SCALE
				sprite.scale = Vector3.ONE * final_scale
				sprite.rotation_degrees = Vector3(-32.0, 45.0, 0.0)
				var height := texture.get_height() * SPRITE_PIXEL_SIZE * final_scale
				var width := texture.get_width() * SPRITE_PIXEL_SIZE * final_scale
				sprite.position = Vector3(SITE.x + item["at"].x, _ground(item["at"]) + height * 0.5 - 0.3, SITE.y + item["at"].y)
				add_child(sprite)
				# Коллизия-стенка в плоскости спрайта, чтобы игрок не проходил насквозь.
				var body := StaticBody3D.new()
				body.collision_layer = 1
				body.collision_mask = 0
				body.position = sprite.position
				body.rotation_degrees.y = 45.0
				var shape := CollisionShape3D.new()
				var box_shape := BoxShape3D.new()
				box_shape.size = Vector3(width * 0.6, height, 1.2)
				shape.shape = box_shape
				body.add_child(shape)
				add_child(body)
				body.add_to_group("city_building")
