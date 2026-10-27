extends Node3D

# Small original buildings assembled from 3D primitives and CC0 photographic
# materials. They replace toy-like city blocks while keeping quest locations.
const PLANKS = preload("res://assets/environment/textures/planks_diff_1k.jpg")
const BRICK = preload("res://assets/environment/textures/brick_diff_1k.jpg")
const CONCRETE = preload("res://assets/environment/textures/concrete_diff_1k.jpg")
const METAL = preload("res://assets/environment/textures/metal_diff_1k.jpg")

var wood: StandardMaterial3D
var brick: StandardMaterial3D
var concrete: StandardMaterial3D
var roof: StandardMaterial3D
var dark: StandardMaterial3D
var glass: StandardMaterial3D

func build(industrial: bool, variant: int = 0) -> void:
	wood = _textured(PLANKS, Color("aca69a"), Vector3(1.6, 1.3, 1))
	brick = _textured(BRICK, Color("9a9184"), Vector3(2.2, 1.5, 1))
	concrete = _textured(CONCRETE, Color("a19f92"), Vector3(1.4, 1.2, 1))
	roof = _textured(METAL, Color("77796c"), Vector3(1.8, 1.8, 1))
	dark = _solid(Color("383d3b"))
	glass = _solid(Color("3b4e50"))
	if industrial:
		_build_industrial(variant)
	else:
		_build_house(variant)

func _textured(texture: Texture2D, tint: Color, repeat: Vector3) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = tint
	material.uv1_scale = repeat
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.roughness = 1.0
	return material

func _solid(color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.96
	return material

func _box(size: Vector3, pos: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var shape = BoxMesh.new()
	shape.size = size
	shape.material = material
	var instance = MeshInstance3D.new()
	instance.mesh = shape
	instance.position = pos
	instance.rotation = rotation
	add_child(instance)
	return instance

func _window(x: float, y: float, z: float, width: float, boarded: bool = false) -> void:
	# Decorative front plate, dark recessed glazing, mullions and scrap boards.
	_box(Vector3(width + 0.18, 1.10, 0.10), Vector3(x, y, z), wood)
	_box(Vector3(width, 0.91, 0.12), Vector3(x, y, z + 0.04), glass)
	_box(Vector3(0.07, 0.95, 0.14), Vector3(x, y, z + 0.08), dark)
	_box(Vector3(width, 0.07, 0.14), Vector3(x, y, z + 0.08), dark)
	if boarded:
		_box(Vector3(width + 0.12, 0.16, 0.13), Vector3(x, y + 0.15, z + 0.12), wood, Vector3(0, 0, 0.12))
		_box(Vector3(width + 0.1, 0.14, 0.13), Vector3(x, y - 0.23, z + 0.13), wood, Vector3(0, 0, -0.16))

func _build_house(variant: int) -> void:
	var w = 4.7
	var depth = 4.0
	var height = 2.65
	var wall = wood if variant % 2 == 0 else concrete
	_box(Vector3(w + 0.25, 0.24, depth + 0.24), Vector3(0, 0.12, 0), concrete)
	_box(Vector3(w, height, depth), Vector3(0, height / 2.0 + 0.24, 0), wall)
	var front = depth / 2.0 + 0.02
	_box(Vector3(0.92, 1.95, 0.11), Vector3(-0.72, 1.23, front), dark)
	_box(Vector3(0.73, 1.78, 0.13), Vector3(-0.72, 1.23, front + 0.04), wood)
	_window(1.15, 1.75, front, 1.12, variant % 2 == 0)
	_window(-1.75, 1.75, front, 0.65, true)
	_box(Vector3(w + 0.4, 0.15, 0.9), Vector3(0, 0.30, front + 0.38), wood)
	# Two textured roof slopes leave the gable silhouette visible from above.
	var rise = 1.0
	var slope_angle = atan(rise / (w * 0.5))
	var slope_len = sqrt(pow(w * 0.5 + 0.3, 2) + pow(rise, 2))
	var roof_y = height + 0.24 + rise * 0.5
	_box(Vector3(slope_len, 0.16, depth + 0.6), Vector3(-w * 0.25, roof_y, 0), roof, Vector3(0, 0, slope_angle))
	_box(Vector3(slope_len, 0.16, depth + 0.6), Vector3(w * 0.25, roof_y, 0), roof, Vector3(0, 0, -slope_angle))
	_box(Vector3(0.48, 1.05, 0.48), Vector3(-1.2, height + 1.03, -0.5), brick)
	_box(Vector3(0.7, 0.15, 0.72), Vector3(-1.2, height + 1.58, -0.5), concrete)

func _build_industrial(variant: int) -> void:
	var width = 5.8
	var depth = 4.8
	var height = 4.2
	_box(Vector3(width, height, depth), Vector3(0, height * 0.5, 0), brick if variant % 2 == 0 else concrete)
	_box(Vector3(width + 0.25, 0.22, depth + 0.25), Vector3(0, height + 0.05, 0), roof)
	_box(Vector3(width + 0.4, 0.24, depth + 0.4), Vector3(0, 0.12, 0), concrete)
	var front = depth * 0.5 + 0.02
	_box(Vector3(1.20, 2.30, 0.12), Vector3(-0.6, 1.28, front), dark)
	_box(Vector3(1.0, 2.10, 0.14), Vector3(-0.6, 1.28, front + 0.05), roof)
	_window(1.48, 1.55, front, 1.15, true)
	_window(-1.75, 3.25, front, 1.0, false)
	_window(0.0, 3.25, front, 1.0, true)
	_window(1.75, 3.25, front, 1.0, false)
	# Broken boards and a small rooftop ventilation box.
	_box(Vector3(1.0, 0.8, 0.85), Vector3(1.45, height + 0.50, -0.65), roof)
	_box(Vector3(1.15, 0.1, 0.95), Vector3(1.45, height + 0.95, -0.65), dark)
