class_name ModelProfiles
extends RefCounted
## Профили персонажей: какие файлы грузить, как масштабировать, как ставить руки.
##
## Нарезанные модели готовит tools/prepare_assets.py: он пишет GLB с пятью
## поверхностями (тело, две руки, две ноги) и рядом JSON с шарнирами и
## габаритами частей. Здесь — только то, что нужно движку.
##
## Цифры шарниров не дублируются: они читаются из *_parts.json, поэтому после
## смены модели достаточно перегенерировать ассеты.

const MEDIC := {
	"parts_model": "res://assets/models/character_parts.glb",
	"meta": "res://assets/models/character_parts.json",
	"scale": 1.75,
	"arm_rest_z": 78.0,   # запасной вариант: обычно угол приходит из JSON
	"fallback_color": Color(0.56, 0.62, 0.55),
	"fallback_height": 1.78,
}

const ZOMBIE := {
	"parts_model": "res://assets/models/zombie_parts.glb",
	"meta": "res://assets/models/zombie_parts.json",
	"scale": 1.75,
	"arm_rest_z": 0.0,    # запасной вариант: обычно угол приходит из JSON
	"fallback_color": Color(0.38, 0.44, 0.34),
	"fallback_height": 1.80,
}

const LIMB_IDS := ["arm_l", "arm_r", "leg_l", "leg_r"]
const BODY_ID := "body"

const PART_TITLES := {
	"body": "Тело",
	"arm_l": "Левая рука",
	"arm_r": "Правая рука",
	"leg_l": "Левая нога",
	"leg_r": "Правая нога",
}

## Прочность конечностей: меч снимает по единице, три удара — и конечность
## отрублена. Корпус зомби держит 1000 HP.
const LIMB_HP := 3.0


static func get_profile(kind: String) -> Dictionary:
	return MEDIC if kind == "medic" else ZOMBIE


static func part_title(part_id: String) -> String:
	return String(PART_TITLES.get(part_id, part_id))


static func has_parts(kind: String) -> bool:
	var profile := get_profile(kind)
	return ResourceLoader.exists(String(profile.get("parts_model", "")))
