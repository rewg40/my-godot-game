extends Control

const UI = preload("res://scripts/ui_style.gd")
const CHART = preload("res://assets/environment/user_island_navigation.png")
const MAP_SIZE := Vector2(3200.0, 2200.0)
const PLAYER_COLOR := Color("e8f0df")
const QUEST_COLOR := Color("f2ba58")
const BASE_COLOR := Color("d69a6b")
const WAYPOINT_COLOR := Color("7ed5e1")

var world
var minimap := false
var zoom := 1.0
var pan := Vector2.ZERO
var dragging := false
var moved := false
var drag_start := Vector2.ZERO
var redraw_timer := 0.0

func _ready() -> void:
	name = "MiniMap" if minimap else "IslandMap"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE if minimap else Control.MOUSE_FILTER_STOP
	queue_redraw()

func _process(delta: float) -> void:
	redraw_timer -= delta
	if redraw_timer <= 0.0:
		redraw_timer = 0.18
		queue_redraw()

func _chart_rect() -> Rect2:
	var texture_size := Vector2(CHART.get_width(), CHART.get_height())
	if minimap and is_instance_valid(world.player):
		# 600 map units = 48 metres across, kept centred on the survivor.
		var scale_factor := size.x / (600.0 / MAP_SIZE.x * texture_size.x)
		var player_pixel: Vector2 = world.player_map_position() / MAP_SIZE * texture_size
		return Rect2(size * 0.5 - player_pixel * scale_factor, texture_size * scale_factor)
	var scale_factor := minf(size.x / texture_size.x, size.y / texture_size.y) * zoom
	var dimensions := texture_size * scale_factor
	return Rect2((size - dimensions) * 0.5 + pan, dimensions)

func map_to_screen(point: Vector2) -> Vector2:
	var chart := _chart_rect()
	return chart.position + point / MAP_SIZE * chart.size

func screen_to_map(point: Vector2) -> Vector2:
	var chart := _chart_rect()
	return (point - chart.position) / chart.size * MAP_SIZE

func _inside(point: Vector2, margin: float = 0.0) -> bool:
	return Rect2(Vector2.ONE * margin, size - Vector2.ONE * margin * 2.0).has_point(point)

func _gui_input(event: InputEvent) -> void:
	if minimap:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var under_cursor := screen_to_map(event.position)
			zoom = clampf(zoom * (1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 1.0, 4.0)
			if zoom == 1.0:
				pan = Vector2.ZERO
			else:
				pan += event.position - map_to_screen(under_cursor)
			_clamp_pan()
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			world.set_waypoint(Vector2(-1.0, -1.0))
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				moved = false
				drag_start = event.position
			elif dragging:
				dragging = false
				var location := screen_to_map(event.position)
				if not moved and location.x >= 0.0 and location.x <= MAP_SIZE.x and location.y >= 0.0 and location.y <= MAP_SIZE.y:
					world.set_waypoint(location)
				queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		if event.position.distance_to(drag_start) > 4.0:
			moved = true
		if moved and zoom > 1.0:
			pan += event.relative
			_clamp_pan()
			queue_redraw()
		accept_event()

func _clamp_pan() -> void:
	var extent := size * maxf(0.0, zoom - 1.0) * 0.5
	pan.x = clampf(pan.x, -extent.x, extent.x)
	pan.y = clampf(pan.y, -extent.y, extent.y)

func _draw() -> void:
	if not is_instance_valid(world) or not is_instance_valid(world.player):
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("1a3033"))
	var chart := _chart_rect()
	var clipped := chart.intersection(Rect2(Vector2.ZERO, size))
	if clipped.has_area():
		var texture_size := Vector2(CHART.get_width(), CHART.get_height())
		var src := Rect2((clipped.position - chart.position) / chart.size * texture_size, clipped.size / chart.size * texture_size)
		draw_texture_rect_region(CHART, clipped, src)
	_draw_lake()
	_draw_bases()
	if not minimap:
		_draw_landmark("hotel", "Отель")
		_draw_landmark("safe", "Сейф")
		_draw_landmark("lighthouse", "Маяк")
		_draw_landmark("boat", "Лодка")
	var target: Vector2 = world.quest_map_position()
	_draw_marker(target, QUEST_COLOR, "Цель" if not minimap else "", false)
	if world.waypoint_map.x >= 0.0:
		_draw_marker(world.waypoint_map, WAYPOINT_COLOR, "Метка" if not minimap else "", true)
	_draw_player()
	draw_rect(Rect2(Vector2.ZERO, size), Color("8c9a80"), false, 2.0)
	var font := UI.FONT_BOLD
	draw_string(font, Vector2(9.0, 18.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ebefdf"))

func _draw_lake() -> void:
	var center: Vector2 = world.environment_3d.lake_map_position
	var points := PackedVector2Array()
	for i in range(48):
		var angle := TAU * float(i) / 48.0
		var radius := Vector2(8.0, 6.0) / world.MAP_SCALE
		points.append(map_to_screen(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)))
	draw_colored_polygon(points, Color("487b7b"))

func _draw_bases() -> void:
	if not is_instance_valid(world.building):
		return
	for piece in world.building.pieces.values():
		if not is_instance_valid(piece) or piece.data.get("type", "") != "foundation":
			continue
		var point: Vector2 = world.world_to_map(piece.global_position)
		var screen := map_to_screen(point)
		if _inside(screen, 3.0):
			draw_rect(Rect2(screen - Vector2(2.5, 2.5), Vector2(5, 5)), BASE_COLOR)

func _draw_landmark(id: String, label: String) -> void:
	var prop = world.find_prop(id)
	if not is_instance_valid(prop):
		return
	var screen := map_to_screen(world.world_to_map(prop.global_position))
	if not _inside(screen, 16.0):
		return
	draw_circle(screen, 3.0, Color("d3d6c2"))
	var font := UI.FONT_BOLD
	draw_string(font, screen + Vector2(7, -5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f2f0dc"))

func _draw_marker(point: Vector2, color: Color, label: String, diamond: bool) -> void:
	var screen := map_to_screen(point)
	if not _inside(screen, 8.0):
		return
	draw_circle(screen, 8.0, Color(0, 0, 0, 0.60))
	if diamond:
		draw_colored_polygon(PackedVector2Array([screen + Vector2(0,-6), screen + Vector2(6,0), screen + Vector2(0,6), screen + Vector2(-6,0)]), color)
	else:
		draw_circle(screen, 5.0, color)
	if not label.is_empty():
		var font := UI.FONT_BOLD
		draw_string(font, screen + Vector2(10, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("fbf4db"))

func _draw_player() -> void:
	var screen := map_to_screen(world.player_map_position())
	if not _inside(screen, 7.0):
		return
	var facing: Vector3 = world.player.facing
	var direction := Vector2(facing.x, facing.z).normalized()
	if direction.length_squared() < 0.01:
		direction = Vector2.UP
	var side := Vector2(-direction.y, direction.x)
	var triangle := PackedVector2Array([screen + direction * 9.0, screen - direction * 6.0 + side * 5.0, screen - direction * 6.0 - side * 5.0])
	draw_circle(screen, 10.0, Color(0, 0, 0, 0.65))
	draw_colored_polygon(triangle, PLAYER_COLOR)
