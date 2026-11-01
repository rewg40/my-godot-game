class_name DayNight
extends Node3D
## Смена суток: солнце, луна, небо, туман и звёзды.
##
## Время живёт в GameState (его же сохраняем), а этот узел только двигает
## источники света и подкрашивает небо. Ночь здесь по-настоящему опасна:
## зомби видят дальше, а тепло уходит быстрее.

const DAY_SKY_TOP := Color(0.20, 0.42, 0.72)
const DAY_SKY_HORIZON := Color(0.66, 0.75, 0.82)
const NIGHT_SKY_TOP := Color(0.012, 0.025, 0.055)
const NIGHT_SKY_HORIZON := Color(0.05, 0.075, 0.13)
const GOLDEN := Color(0.95, 0.55, 0.32)
const FOG_DAY := Color(0.62, 0.68, 0.72)
const FOG_NIGHT := Color(0.05, 0.07, 0.11)

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var environment: Environment
var sky_material: ProceduralSkyMaterial
var stars: StarField
var night_factor := 0.0


func setup(env: Environment, sky_mat: ProceduralSkyMaterial, stars_node: StarField) -> void:
	environment = env
	sky_material = sky_mat
	stars = stars_node
	_build_lights()
	_apply(GameState.time_of_day)


func _process(delta: float) -> void:
	if not GameState.run_active:
		return
	GameState.advance_time(delta)
	_apply(GameState.time_of_day)


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.04
	sun.shadow_blur = 1.5
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.68, 0.95)
	moon.light_energy = 0.35
	moon.shadow_enabled = false
	add_child(moon)


func _apply(time_of_day: float) -> void:
	var angle := (time_of_day - 0.25) * TAU
	var elevation := sin(angle)
	var daylight := clampf(elevation * 2.4 + 0.12, 0.0, 1.0)
	var golden := clampf(1.0 - absf(elevation) * 4.0, 0.0, 1.0)
	night_factor = clampf(1.0 - daylight * 1.3, 0.0, 1.0)

	sun.rotation_degrees = Vector3(-rad_to_deg(angle), -42.0, 0.0)
	sun.light_energy = clampf(elevation, 0.0, 1.0) * 1.25
	sun.light_color = Color(1.0, 0.94, 0.82).lerp(GOLDEN, golden * 0.8)
	sun.visible = elevation > -0.02

	moon.rotation_degrees = Vector3(-rad_to_deg(angle + PI), 36.0, 0.0)
	moon.light_energy = clampf(-elevation, 0.0, 1.0) * 0.45
	moon.visible = elevation < 0.12

	if sky_material != null:
		sky_material.sky_top_color = NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, daylight)
		sky_material.sky_horizon_color = NIGHT_SKY_HORIZON.lerp(DAY_SKY_HORIZON, daylight)
		sky_material.sky_horizon_color = sky_material.sky_horizon_color.lerp(GOLDEN, golden * 0.4)
		sky_material.ground_horizon_color = sky_material.sky_horizon_color
		sky_material.ground_bottom_color = Color(0.04, 0.05, 0.06)
		sky_material.sky_energy_multiplier = lerpf(0.4, 1.0, daylight)

	if environment != null:
		environment.ambient_light_energy = lerpf(0.4, 1.0, daylight)
		environment.fog_light_color = FOG_NIGHT.lerp(FOG_DAY, daylight).lerp(GOLDEN, golden * 0.25)
		environment.fog_density = lerpf(0.02, 0.0055, daylight)

	if stars != null:
		stars.set_night_factor(night_factor)
