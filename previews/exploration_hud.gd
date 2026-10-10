extends Node

## Isolated review scene. Only this scene seeds inventory and freezes the clock
## and NPCs. The normal hotel.tscn and every gameplay script remain unchanged.
const GameScene = preload("res://hotel.tscn")
const RunState = preload("res://game_state.gd")
var game: Node

func _ready() -> void:
	game = GameScene.instantiate()
	add_child(game)
	game.run_controller.start_new_run(424242)
	await get_tree().process_frame
	var controller = game.run_controller
	controller.set_process(false)
	controller.set_physics_process(false)
	for npc in get_tree().get_nodes_in_group("hotel_npc"):
		npc.set_process(false)
		npc.set_physics_process(false)
	for npc in controller.guard_nodes:
		npc.set_process(false)
		npc.set_physics_process(false)
	if controller.cleaner_node != null:
		controller.cleaner_node.set_process(false)
		controller.cleaner_node.set_physics_process(false)
	for item_id in ["staff_card", "instant_camera", "folding_trap"]:
		controller.state.add_item(RunState.CONTAINER_CARRY, item_id)
	game.player.selected_slot = 1
	controller.set_selected_slot(1)
	# Keep the real lobby spawn and view down its first corridor.
	game.player._pitch = -0.10
	game.player.camera.rotation.x = -0.10
	game.player._update_hud()
	game.hud.set_run_status(1, "day", 150.0, 0)
	game.hud.show_help("探索界面预览 · 时钟与巡逻已冻结\n1–4 选物品 · E 交互 · R 切换动作 · N 手记 · 按住 T 看表", 8.0)
