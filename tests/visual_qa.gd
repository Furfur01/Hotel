extends SceneTree

## Manual/CI-friendly native 1920x1080 render probe.  Run with the normal Metal
## renderer (not --headless) so the saved PNGs exercise the shipped UI path.

const MainScene = preload("res://hotel.tscn")
const RunState = preload("res://game_state.gd")
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_root = MainScene.instantiate()
	root.add_child(game_root)
	await _frames(4)
	var controller = game_root.get_node("RunController")
	controller.start_new_run(424242)
	await _frames(4)
	var first_door: Node = controller.floor.door_nodes.values()[0] if not controller.floor.door_nodes.is_empty() else null
	var world_plate := first_door.get_node_or_null("RoomPlateText") as Label3D if first_door != null else null
	_expect(world_plate != null, "guest doors must expose a room-plate label")
	if world_plate != null:
		_expect(not world_plate.no_depth_test, "fluorescent room plates must respect wall depth and never render through walls")
	controller.set_process(false)
	controller.set_physics_process(false)
	game_root.hud.help_panel.visible = false
	var pickup_forward: Vector3 = -controller.player.global_transform.basis.z
	pickup_forward.y = 0.0
	pickup_forward = pickup_forward.normalized()
	var pickup_position: Vector3 = Vector3(controller.player.global_position) + pickup_forward * 1.3 + Vector3(0.0, 0.24, 0.0)
	var first_pickup: Node3D = controller.floor.spawn_item_pickup("lockpick", pickup_position, "")
	controller.player._pitch = -0.48
	controller.player.camera.rotation.x = controller.player._pitch
	await _frames(3)
	var world_sprite := first_pickup.get_node_or_null("WorldItemSprite") as Sprite3D
	_expect(world_sprite != null, "ground pickup must use WorldItemSprite")
	if world_sprite != null:
		_expect(world_sprite.texture.get_size() == Vector2(64, 64), "ground pickup must use 64x64 pixel texture")
		_expect(world_sprite.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS, "ground pickup must use nearest mipmap filtering")
	await _capture("/tmp/hotel_ui_world_pickup_1080.png")
	first_pickup.visible = false
	if controller.suitcase_node != null:
		controller.suitcase_node.visible = false
	var records_marker: Node3D = null
	for interactable_value in controller.floor.get_tree().get_nodes_in_group("interactable"):
		if controller.floor.is_ancestor_of(interactable_value) and String(interactable_value.kind) == "records":
			records_marker = interactable_value as Node3D
			records_marker.visible = false
			break
	var preview_right: Vector3 = controller.player.global_transform.basis.x.normalized()
	var preview_center: Vector3 = Vector3(controller.player.global_position) + pickup_forward * 3.2
	var tenant = controller._spawn_npc("tenant", PackedVector3Array([preview_center]), true)
	var preview_npcs: Array = [controller.guard_nodes[0], controller.cleaner_node, tenant]
	for preview_index in range(preview_npcs.size()):
		var preview_npc = preview_npcs[preview_index]
		preview_npc.global_position = preview_center + preview_right * (float(preview_index) - 1.0) * 0.72
		preview_npc.set_process(false)
		preview_npc.set_physics_process(false)
	controller.player._pitch = -0.12
	controller.player.camera.rotation.x = controller.player._pitch
	await _capture("/tmp/hotel_nextbot_characters_1080.png")
	for preview_npc in preview_npcs:
		preview_npc.visible = false
	if controller.suitcase_node != null:
		controller.suitcase_node.visible = true
	if records_marker != null:
		records_marker.visible = true

	for item_id in ["staff_card", "instant_camera", "folding_trap"]:
		controller.state.add_item(RunState.CONTAINER_CARRY, item_id)
	controller.player._update_hud()
	_expect(game_root.hud.inventory_slots.size() == 4, "carry HUD must contain exactly four slots")
	_expect(game_root.hud.stamina_panel.find_children("*", "Label", true, false).is_empty(), "stamina HUD must be a bar with no labels")
	for icon: TextureRect in game_root.hud.inventory_icon_textures:
		if icon.texture != null:
			_expect(icon.texture.get_size() == Vector2(32, 32), "carry icon must use 32x32 pixel texture")
			_expect(icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "carry icon must use nearest filtering")
	_expect(game_root.hud.status_panel == null, "default HUD must not build a top status bar")
	await _capture("/tmp/hotel_ui_inventory_1080.png")

	game_root.hud.set_run_status(1, "白天", 90.0, 0)
	game_root.hud.set_watch_open(true)
	_expect(not game_root.hud.inventory_panel.visible, "watch view must hide the carry slots")
	_expect(not game_root.hud.stamina_panel.visible, "watch view must hide the stamina bar")
	for part: ColorRect in game_root.hud.reticle_parts:
		_expect(not part.visible, "watch view must hide the reticle")
	await _capture("/tmp/hotel_ui_watch_green_1080.png")
	game_root.hud.set_run_status(1, "白天", 30.0, 0)
	await _capture("/tmp/hotel_ui_watch_red_1080.png")
	game_root.hud.set_watch_open(false)

	game_root.hud.set_run_status(1, "白天", 90.0, 1)
	await _frames(20)
	await _capture("/tmp/hotel_ui_strike_1_1080.png")
	game_root.hud.set_run_status(1, "白天", 90.0, 2)
	await _frames(20)
	await _capture("/tmp/hotel_ui_strike_2_1080.png")
	game_root.hud.set_run_status(1, "白天", 90.0, 0)
	await _frames(30)

	var notebook_entries: Array = []
	for index in range(5):
		var room_number := 201 + index
		var evidence: Array = []
		match index % 4:
			0:
				evidence = ["vacant", "vacant", null, "no_response"]
			1:
				evidence = ["rented", null, "rented", "rented"]
			2:
				evidence = [null, "rented", null, "no_response"]
			_:
				evidence = ["vacant", null, null, "no_response"]
		notebook_entries.append({
			"room_number": room_number,
			"sources": evidence,
			"map_position": Vector2(0.25 if index % 2 == 0 else 0.75, 0.18 + float(index) * 0.15),
		})
	controller.player.notebook_open = true
	game_root.hud.set_notebook(notebook_entries, true)
	_expect(game_root.hud.notebook_source_marks.size() == 56, "notebook must expose four raw test marks for each of fourteen rows")
	_expect(game_root.hud.notebook_map_plates.size() == 14, "investigation map must expose one fluorescent plate per notebook row")
	var notebook_paper := game_root.hud.notebook_overlay.get_node_or_null("FieldNotebookPaper") as TextureRect
	_expect(notebook_paper != null, "notebook must use the generated pixel-art paper asset")
	if notebook_paper != null:
		_expect(notebook_paper.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS, "pixel notebook must use nearest-neighbour sampling")
	for label_value in game_root.hud.notebook_overlay.find_children("*", "Label", true, false):
		var label := label_value as Label
		for forbidden in ["房间调查笔记", "实时记录", "证据票", "判定", "空置", "出租", "未定", "可落脚", "有人", "待确认", "票", "✓", "×"]:
			_expect(not label.text.contains(forbidden), "notebook contains forbidden UI text: %s" % forbidden)
	await _capture("/tmp/hotel_ui_notebook_1080.png")

	controller.player.notebook_open = false
	game_root.hud.set_notebook([], false)
	_expect(game_root.hud.get_node_or_null("ActionWheel") == null, "radial action UI must not be constructed")
	controller.player.set_process(false)
	controller.player.set_physics_process(false)
	game_root.hud.set_prompt("E  开门   R  ›")
	await _capture("/tmp/hotel_ui_context_action_1080.png")
	game_root.hud.set_prompt("")
	var door_action_sprite := controller.player.door_action_sprite as Sprite2D
	_expect(door_action_sprite != null, "player must expose the first-person door-action sprite")
	if door_action_sprite != null:
		_expect(door_action_sprite.texture != null and door_action_sprite.texture.get_size() == Vector2(512, 320), "door action sheet must contain eight low-resolution 128x160 frames")
		_expect(door_action_sprite.hframes == 4 and door_action_sprite.vframes == 2, "door action sheet must use a 4x2 frame grid")
		_expect(door_action_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "door action frames must remain crisp nearest-neighbour pixels")
		_expect(is_equal_approx(door_action_sprite.scale.x, round(door_action_sprite.scale.x)) and door_action_sprite.scale.x >= 3.0, "door action frames must use a large integer FPS-style scale")
		var displayed_size := Vector2(128.0, 160.0) * door_action_sprite.scale
		var qa_viewport_size := Vector2(root.get_viewport().get_visible_rect().size)
		_expect(displayed_size.y >= qa_viewport_size.y * 0.65 and displayed_size.x >= qa_viewport_size.x * 0.28, "door action foreground must occupy substantially more of the screen")
	var door_action_layer := controller.player.get_node_or_null("DoorActionLayer") as CanvasLayer
	_expect(door_action_layer != null and door_action_layer.layer == 10, "door action must render below notebook/watch HUD overlays")
	if first_door != null:
		var room_id := String(first_door.data.get("room_id", ""))
		var descriptor: Dictionary = controller.floor.descriptor_by_id.get(room_id, {})
		var corridor_tile: Vector2i = descriptor.get("corridor_tile", Vector2i.ZERO)
		var corridor_position: Vector3 = controller.floor.cell_pos(corridor_tile.x, corridor_tile.y)
		controller.player.global_position = corridor_position + Vector3(0.0, 0.04, 0.0)
		var door_target := Vector3(first_door.global_position.x, controller.player.global_position.y, first_door.global_position.z)
		controller.player.look_at(door_target, Vector3.UP)
		controller.player._yaw = controller.player.rotation.y
		controller.player._pitch = -0.04
		controller.player.camera.rotation.x = controller.player._pitch
	controller.player.play_door_interaction("knock", 0.5)
	await _capture("/tmp/hotel_door_knock_01_1080.png")
	controller.player._tick_door_interaction(0.09)
	await _capture("/tmp/hotel_door_knock_02_1080.png")
	controller.player._tick_door_interaction(0.09)
	await _capture("/tmp/hotel_door_knock_03_1080.png")
	controller.player.stop_door_interaction()
	var neutral_camera_position: Vector3 = controller.player.camera.position
	var neutral_camera_roll: float = controller.player.camera.rotation.z
	controller.player.play_door_interaction("listen", 2.0)
	_expect(not door_action_sprite.visible, "listening must use only camera motion, with no fake ear overlay")
	controller.player._tick_door_interaction(0.20)
	await _capture("/tmp/hotel_door_listen_01_1080.png")
	controller.player._tick_door_interaction(0.30)
	await _capture("/tmp/hotel_door_listen_02_1080.png")
	controller.player._tick_door_interaction(1.00)
	await _capture("/tmp/hotel_door_listen_03_1080.png")
	controller.player._tick_door_interaction(0.35)
	await _capture("/tmp/hotel_door_listen_04_1080.png")
	_expect(controller.player.camera.position.distance_to(neutral_camera_position) > 0.02, "listen hold must move the camera toward the door")
	_expect(absf(controller.player.camera.rotation.z - neutral_camera_roll) > deg_to_rad(0.5), "listen hold must tilt the camera sideways")
	controller.player.stop_door_interaction()
	_expect(controller.player.camera.position.distance_to(neutral_camera_position) < 0.001 and absf(controller.player.camera.rotation.z - neutral_camera_roll) < 0.001, "stopping listen must restore the camera")
	controller.player.set_process(true)
	controller.player.set_physics_process(true)

	for item_id in ["lockpick", "alarm_clock", "ratchet_strap", "industrial_cleaner"]:
		controller.state.add_item(RunState.CONTAINER_SUITCASE, item_id)
	controller.player.suitcase_open = true
	controller.player.refresh_suitcase_data()
	await _capture("/tmp/hotel_ui_suitcase_1080.png")
	controller.player.suitcase_open = false
	controller.player.refresh_suitcase_data()

	controller.player.debug_map_open = true
	controller.player._update_debug_map()
	await _capture("/tmp/hotel_ui_debug_map_1080.png")
	controller.player.debug_map_open = false
	controller.player._update_debug_map()
	_expect(game_root.hud.capture_hit_player.stream != null, "capture scare must load its CC0 impact sound")
	_expect(game_root.hud.capture_static_player.stream != null, "capture scare must load its CC0 radio-static layer")
	game_root.hud.play_capture_scare(&"guard")
	await _frames(5)
	await _capture("/tmp/hotel_ui_capture_scare_1080.png")
	await game_root.hud.capture_scare_finished

	game_root.hud.show_end("两日原型完成", "你带着旅行箱离开了酒店。\nDay 3–7 与正式目标将在后续玩法讨论中加入。")
	await _capture("/tmp/hotel_ui_end_1080.png")

	print("VISUAL_QA wrote twenty captures to /tmp and res://artifacts/visual_qa failures=%d" % _failures.size())
	game_root.queue_free()
	await _frames(3)
	quit(0 if _failures.is_empty() else 1)


func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var viewport_size := Vector2i(image.get_width(), image.get_height())
	var supported_sizes := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
	if viewport_size not in supported_sizes:
		push_error("VISUAL_QA wrong viewport size %dx%d" % [image.get_width(), image.get_height()])
	var resolved_path := path
	if viewport_size != Vector2i(1920, 1080):
		resolved_path = path.replace("_1080.png", "_%dx%d.png" % [viewport_size.x, viewport_size.y])
	image.save_png(resolved_path)
	var artifact_path := ProjectSettings.globalize_path("res://artifacts/visual_qa/%s" % resolved_path.get_file())
	image.save_png(artifact_path)


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("VISUAL_QA: " + message)
