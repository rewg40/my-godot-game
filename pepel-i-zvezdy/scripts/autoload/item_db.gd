extends Node
## Автозагрузка «ItemDB»: предметы, рецепты и игровые классы.
##
## Все данные лежат в обычных словарях, поэтому баланс правится без захода
## в редактор. Поля предмета:
##   name   — подпись в интерфейсе;
##   kind   — med | food | water | material | weapon | placeable;
##   color  — цвет процедурной модели (если нет GLB);
##   stack  — максимальный размер стека;
##   desc   — описание;
##   use    — эффект при использовании: health / hunger / thirst / infection / warmth;
##   damage, cooldown — для оружия.

const DEFAULT_CLASS := "medic"

## Данные предметов.
var items := {
	"bandage": {
		"name": "Бинт",
		"kind": "med",
		"color": Color(0.87, 0.85, 0.79),
		"stack": 10,
		"desc": "Плотная ткань. Останавливает кровь, +25 HP.",
		"use": {"health": 25.0},
	},
	"antibiotics": {
		"name": "Антибиотики",
		"kind": "med",
		"color": Color(0.78, 0.86, 0.92),
		"stack": 5,
		"desc": "Гасят заражение на 45 единиц.",
		"use": {"infection": -45.0, "health": 5.0},
	},
	"canned_food": {
		"name": "Консервы",
		"kind": "food",
		"color": Color(0.72, 0.55, 0.32),
		"stack": 5,
		"desc": "Сытно и почти безопасно. +38 сытости.",
		"use": {"hunger": 38.0},
	},
	"water_clean": {
		"name": "Чистая вода",
		"kind": "water",
		"color": Color(0.55, 0.76, 0.88),
		"stack": 5,
		"desc": "Кипячёная вода. +40 жажды.",
		"use": {"thirst": 40.0},
	},
	"water_dirty": {
		"name": "Мутная вода",
		"kind": "water",
		"color": Color(0.42, 0.52, 0.45),
		"stack": 5,
		"desc": "Пахнет тиной. +32 жажды, +12 заражения.",
		"use": {"thirst": 32.0, "infection": 12.0},
	},
	"herb": {
		"name": "Трава-пепельница",
		"kind": "material",
		"color": Color(0.45, 0.62, 0.38),
		"stack": 20,
		"desc": "Горькая, но останавливает заражение. Основа лекарств.",
	},
	"cloth": {
		"name": "Тряпки",
		"kind": "material",
		"color": Color(0.66, 0.63, 0.57),
		"stack": 20,
		"desc": "Всё, что осталось от старой одежды.",
	},
	"wood": {
		"name": "Дерево",
		"kind": "material",
		"color": Color(0.45, 0.33, 0.22),
		"stack": 20,
		"desc": "Сучья и доски. Топливо и стройматериал.",
	},
	"scrap": {
		"name": "Металлолом",
		"kind": "material",
		"color": Color(0.55, 0.57, 0.6),
		"stack": 20,
		"desc": "Ржавые пластины. Из них выходят клинки.",
	},
	"stone": {
		"name": "Камень",
		"kind": "material",
		"color": Color(0.5, 0.5, 0.49),
		"stack": 20,
		"desc": "Осколки породы. Держат костёр.",
	},
	"pipe": {
		"name": "Труба",
		"kind": "weapon",
		"color": Color(0.6, 0.6, 0.62),
		"stack": 1,
		"damage": 18.0,
		"cooldown": 0.72,
		"desc": "Обрезок трубы. Бьёт больно, но недалеко.",
	},
	"torch": {
		"name": "Факел",
		"kind": "weapon",
		"color": Color(0.85, 0.55, 0.25),
		"stack": 1,
		"damage": 12.0,
		"cooldown": 0.8,
		"light": true,
		"desc": "Светит в темноте и годится как дубина.",
	},
	"sword": {
		"name": "Клинок «Дракон»",
		"kind": "weapon",
		"color": Color(0.72, 0.88, 0.95),
		"stack": 1,
		"damage": 44.0,
		"cooldown": 0.95,
		"model": "res://assets/models/sword.glb",
		"desc": "Тяжёлый клинок с бирюзовой рукоятью. Лучшее, что можно найти.",
	},
	"campfire_kit": {
		"name": "Набор для костра",
		"kind": "placeable",
		"color": Color(0.8, 0.48, 0.2),
		"stack": 3,
		"desc": "Камни, дерево и трут. Ставится на землю [E].",
	},
}

## Рецепты крафта. "station" = "fire" требует стоять рядом с костром.
## Рецепты крафта.
var recipes := [
	{"result": "bandage", "count": 2, "cost": {"cloth": 2, "herb": 1}, "station": ""},
	{"result": "torch", "count": 1, "cost": {"wood": 2, "cloth": 1}, "station": ""},
	{"result": "pipe", "count": 1, "cost": {"scrap": 4, "wood": 1}, "station": ""},
	{"result": "campfire_kit", "count": 1, "cost": {"wood": 6, "stone": 5}, "station": ""},
	{"result": "antibiotics", "count": 1, "cost": {"herb": 4, "scrap": 1}, "station": ""},
	{"result": "water_clean", "count": 1, "cost": {"water_dirty": 1}, "station": "fire"},
	{"result": "sword", "count": 1, "cost": {"scrap": 8, "wood": 2, "stone": 2}, "station": "fire"},
]

## Игровые классы. Множители применяются в survival/player.
## Игровые классы.
var classes := {
	"medic": {
		"name": "Медик",
		"tagline": "Перевязки и холодная голова",
		"desc": "Лечение на 50% сильнее, заражение набирается на 30% медленнее.",
		"color": Color(0.55, 0.8, 0.7),
		"heal_mult": 1.5,
		"infection_mult": 0.7,
		"damage_mult": 1.0,
		"damage_taken_mult": 1.0,
		"max_health": 100.0,
		"start": {"bandage": 3, "water_clean": 1, "herb": 2},
	},
	"engineer": {
		"name": "Инженер",
		"tagline": "Всё чинится, всё пригодится",
		"desc": "Крафт дешевле на 25%, инструменты и металл в стартовом наборе.",
		"color": Color(0.85, 0.72, 0.45),
		"heal_mult": 1.0,
		"infection_mult": 1.0,
		"damage_mult": 1.0,
		"damage_taken_mult": 1.0,
		"max_health": 100.0,
		"craft_mult": 0.75,
		"start": {"scrap": 4, "pipe": 1, "wood": 3},
	},
	"builder": {
		"name": "Строитель",
		"tagline": "Крепче камня",
		"desc": "+30 к максимальному здоровью, костёр можно ставить почти сразу.",
		"color": Color(0.72, 0.6, 0.5),
		"heal_mult": 1.0,
		"infection_mult": 1.0,
		"damage_mult": 1.0,
		"damage_taken_mult": 0.9,
		"max_health": 130.0,
		"start": {"campfire_kit": 1, "wood": 4, "stone": 3},
	},
	"military": {
		"name": "Военный",
		"tagline": "Считает удары и наносит их",
		"desc": "Урон в ближнем бою +30%, получаемый урон −20%.",
		"color": Color(0.65, 0.72, 0.55),
		"heal_mult": 0.9,
		"infection_mult": 1.0,
		"damage_mult": 1.3,
		"damage_taken_mult": 0.8,
		"max_health": 110.0,
		"start": {"pipe": 1, "bandage": 1},
	},
}

func get_item(id: String) -> Dictionary:
	return items.get(id, {})


func display_name(id: String) -> String:
	var item := get_item(id)
	return String(item.get("name", id))


func is_weapon(id: String) -> bool:
	return String(get_item(id).get("kind", "")) == "weapon"


func is_consumable(id: String) -> bool:
	return get_item(id).has("use")


func class_data(id: String) -> Dictionary:
	return classes.get(id, classes[DEFAULT_CLASS])


func class_ids() -> Array:
	return classes.keys()


## Полный список рецептов (для интерфейса крафта).
func all_recipes() -> Array:
	return recipes


## Стоимость рецепта с учётом скидки класса (инженер).
func recipe_cost(recipe: Dictionary, class_id: String) -> Dictionary:
	var mult := float(class_data(class_id).get("craft_mult", 1.0))
	var cost := {}
	for id in recipe["cost"].keys():
		cost[id] = maxi(1, int(ceil(float(recipe["cost"][id]) * mult)))
	return cost
