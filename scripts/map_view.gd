extends Control

const UI = preload("res://scripts/ui_style.gd")
const GROUND = preload("res://assets/environment/island_ground.png")
var world

func _ready() -> void:
	custom_minimum_size = Vector2(870, 470)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var map_rect = Rect2(Vector2.ZERO, size)
	draw_texture_rect(GROUND, map_rect, false)
	draw_rect(map_rect, Color(0.03, 0.08, 0.08, 0.23))
	for mark in world.map_markers():
		var point: Vector2 = _map_point(mark["position"])
		draw_circle(point, 5.0, Color("ecd09a"))
		draw_arc(point, 8.0, 0, TAU, 20, Color("173633"), 2.0)
		draw_string(UI.FONT_BOLD, point + Vector2(10, -6), mark["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("fff2cf"))
	var goal = _map_point(world.objective_position())
	draw_arc(goal, 12.0, 0, TAU, 20, Color("f7d171"), 3.0)
	var player_pos = _map_point(world.world_to_map(world.player.global_position))
	draw_circle(player_pos, 6.0, Color("e66e53"))
	draw_arc(player_pos, 9.0, 0, TAU, 20, Color.WHITE, 2.0)

func _map_point(point: Vector2) -> Vector2:
	return Vector2(point.x / 3200.0 * size.x, point.y / 2200.0 * size.y)
