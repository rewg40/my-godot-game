class_name Inventory
extends Node
## Инвентарь игрока: 12 слотов, стеки по ItemDB.get_item(id).stack.
##
## Слот — обычный словарь {"id": String, "count": int}; это же представление
## уходит в сохранение, поэтому формат менять не нужно.

signal changed

const CAPACITY := 12
const HOTBAR_SIZE := 5

var slots: Array = []


func _ready() -> void:
	if slots.is_empty():
		slots.resize(CAPACITY)
		for i in CAPACITY:
			slots[i] = {}


func setup(start_items: Dictionary) -> void:
	slots.clear()
	slots.resize(CAPACITY)
	for i in CAPACITY:
		slots[i] = {}
	for id in start_items.keys():
		add(String(id), int(start_items[id]))
	changed.emit()


func add(id: String, amount: int = 1) -> int:
	if amount <= 0:
		return 0
	var stack_limit := int(ItemDB.get_item(id).get("stack", 1))
	var left := amount

	for i in CAPACITY:
		if left <= 0:
			break
		var slot: Dictionary = slots[i]
		if slot.is_empty() or String(slot.get("id", "")) != id:
			continue
		var space := stack_limit - int(slot.get("count", 0))
		if space <= 0:
			continue
		var moved := mini(space, left)
		slot["count"] = int(slot.get("count", 0)) + moved
		left -= moved

	for i in CAPACITY:
		if left <= 0:
			break
		var slot: Dictionary = slots[i]
		if not slot.is_empty():
			continue
		var moved := mini(stack_limit, left)
		slots[i] = {"id": id, "count": moved}
		left -= moved

	if left != amount:
		changed.emit()
	return left


func remove(id: String, amount: int = 1) -> bool:
	if count_of(id) < amount:
		return false
	var left := amount
	for i in CAPACITY:
		if left <= 0:
			break
		var slot: Dictionary = slots[i]
		if slot.is_empty() or String(slot.get("id", "")) != id:
			continue
		var have := int(slot.get("count", 0))
		var taken := mini(have, left)
		slot["count"] = have - taken
		left -= taken
		if int(slot["count"]) <= 0:
			slots[i] = {}
	changed.emit()
	return true


func count_of(id: String) -> int:
	var total := 0
	for slot in slots:
		if not slot.is_empty() and String(slot.get("id", "")) == id:
			total += int(slot.get("count", 0))
	return total


func has_items(cost: Dictionary) -> bool:
	for id in cost.keys():
		if count_of(String(id)) < int(cost[id]):
			return false
	return true


func consume(cost: Dictionary) -> bool:
	if not has_items(cost):
		return false
	for id in cost.keys():
		remove(String(id), int(cost[id]))
	return true


func slot_at(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	return slots[index]


func clear_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	var slot: Dictionary = slots[index]
	slots[index] = {}
	changed.emit()
	return slot


func is_full() -> bool:
	for slot in slots:
		if slot.is_empty():
			return false
	return true


func get_state() -> Array:
	var result := []
	for slot in slots:
		if slot.is_empty():
			result.append({})
		else:
			result.append({"id": String(slot["id"]), "count": int(slot["count"])})
	return result


func set_state(data: Array) -> void:
	slots.resize(CAPACITY)
	for i in CAPACITY:
		var slot: Dictionary = {}
		if i < data.size() and typeof(data[i]) == TYPE_DICTIONARY:
			var source: Dictionary = data[i]
			if not source.is_empty():
				slot = {"id": String(source.get("id", "cloth")), "count": int(source.get("count", 1))}
		slots[i] = slot
	changed.emit()
