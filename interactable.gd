class_name HotelInteractable
extends Node3D

var kind := ""
var host: Node = null
var data: Dictionary = {}

var pivot: Node3D = null
var door_theta := 0.0
var door_open := false
var inner_yaw := 0.0
var enabled := true


func _ready() -> void:
	add_to_group("interactable")


func get_actions(player: Node) -> Array:
	if not enabled:
		return []
	if host != null and host.has_method("get_interaction_options"):
		var offered = host.get_interaction_options(self, player)
		if offered is Array:
			return offered
	if kind == "door":
		return [{"id": "toggle", "label": "关门" if door_open else "开门", "duration": 0.0}]
	if kind == "wardrobe":
		return [{"id": "wardrobe", "label": "出来" if player.in_wardrobe else "躲进衣柜", "duration": 0.0}]
	return []


func get_prompt(player: Node) -> String:
	var options := get_actions(player)
	if options.is_empty():
		return ""
	var primary: Dictionary = options[0]
	var label := String(primary.get("label", "交互"))
	return "E  %s%s" % [label, "   R  ›" if options.size() > 1 else ""]


func interact(player: Node) -> void:
	var options := get_actions(player)
	if options.is_empty():
		return
	perform_action(String(options[0].get("id", "")), player)


func perform_action(action_id: String, player: Node) -> void:
	if not enabled:
		return
	if host != null and host.has_method("handle_interaction"):
		host.handle_interaction(self, action_id, player)
		return
	if kind == "door" and action_id == "toggle":
		set_door_open(not door_open)
	elif kind == "wardrobe" and action_id == "wardrobe":
		if player.in_wardrobe:
			player.exit_wardrobe()
		else:
			player.enter_wardrobe(global_position, inner_yaw)


func set_door_open(open: bool, instant := false) -> void:
	if kind != "door" or pivot == null:
		return
	door_open = open
	var target := door_theta + (1.45 if door_open else 0.0)
	if instant:
		pivot.rotation.y = target
		return
	var tween := get_tree().create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(pivot, "rotation:y", target, 0.28)


func set_enabled(value: bool) -> void:
	enabled = value
	for child in get_children():
		if child is Area3D:
			child.set_deferred("monitoring", value)
			child.set_deferred("monitorable", value)
