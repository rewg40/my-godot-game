extends Node3D
## Базовая интерьерная сцена: спрайт-«задник» комнаты + пол с коллизией.
## start(player) вызывается контроллером при входе. Имя узла сцены совпадает с
## именем файла-изображения интерьера (i01_apartment_room и т.д.), поэтому
## текстура грузится как res://assets/city/<имя_сцены>.png.

const IMG_DIR := "res://assets/city/"
const CAM_ROT := Vector3(-32.0, 45.0, 0.0)
const PIXEL_SIZE := 0.022

var player: CharacterBody3D = null
var _img_name := ""

func _ready() -> void:
	add_to_group("interior")
	_img_name = _derive_img_name()
	_setup_room()

## Вызывается контроллером player.gd при входе в здание.
func start(p: CharacterBody3D) -> void:
	player = p
	if player:
		# Ставим персонажа «в комнату» перед задником, на высоте шага.
		player.global_position = Vector3(0, 1.0, 2.8)
		player.velocity = Vector3.ZERO

func _derive_img_name() -> String:
	# Имя сцены обычно "i01" или полное имя узла; берём полное имя узла.
	var n := name
	# Godot может переименовать узел при конфликте; ищем подстроку i\d\d
	var m := n
	return m.strip_edges()

func _setup_room() -> void:
	var tex: Texture2D = load(IMG_DIR + _img_name + ".png")
	if tex == null:
		push_warning("interior: нет текстуры " + IMG_DIR + _img_name + ".png")
		return
	var sp := Sprite3D.new()
	sp.name = "Backdrop"
	sp.texture = tex
	sp.pixel_size = PIXEL_SIZE
	sp.rotation_degrees = CAM_ROT
	sp.position = Vector3(0, tex.get_height() * PIXEL_SIZE * 0.5, 1.0)
	sp.shaded = true
	add_child(sp)
	# Пол с коллизией (StaticBody3D), чтобы игрок ходил по комнате.
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(9.0, 0.2, 9.0)
	col.shape = box
	floor_body.add_child(col)
	floor_body.position = Vector3(0, -0.1, 0)
	var vis := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(9.0, 0.2, 9.0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.20, 0.20, 0.21)
	bm.material = fm
	vis.mesh = bm
	vis.position = Vector3(0, -0.1, 0)
	floor_body.add_child(vis)
	add_child(floor_body)