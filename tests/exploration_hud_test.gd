extends SceneTree

const PreviewScene = preload("res://previews/exploration_hud.tscn")
var failures := 0
var assertions := 0
var capture_finished := false

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error(message)

func _key(player: Node, code: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	player._unhandled_input(event)

func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/" + filename + ".png")

func _run() -> void:
	var preview = PreviewScene.instantiate()
	root.add_child(preview)
	for i in range(8):
		await process_frame
	var player = preview.game.player
	var hud = preview.game.hud
	var controller = preview.game.run_controller
	# Keep the same real floor/camera for every screenshot and before/after.
	player.set_process(false)
	player.set_physics_process(false)
	hud.show_help("", 0.0)
	hud.help_panel.visible = false
	hud.set_prompt("E  拿起旅行箱   R  ›")
	hud.set_stamina(72.0, 100.0, true)
	for i in range(30):
		await process_frame
	await _capture("hotel_exploration_after")
	if "--capture-only" in OS.get_cmdline_user_args():
		hud.hud_root.visible = false
		await _capture("hotel_exploration_scene")
		preview.queue_free()
		await process_frame
		quit()
		return

	_check(hud.inventory_slots.size() == 4, "four carry slots remain")
	_check(hud.status_panel == null, "do not restore an always-on status bar")
	_check(hud.prompt_label.text == "E  拿起旅行箱   R  ›", "preserve raw action text")
	for index in range(4):
		_key(player, KEY_1 + index)
		player._update_hud()
		_check(controller.selected_slot == index, "1–4 updates controller selection")
		_check(hud._carry_selected[index], "selection reflected in HUD")
	_check(hud._carry_selected[2] and hud._carry_selected[3], "linked two-slot item highlights both cells")
	_check(hud.inventory_icon_textures[3].modulate.a < 0.5, "secondary two-hand icon stays dim")
	_check(hud.carry_title.text == "折叠致命陷阱", "secondary slot displays same item title")
	await _capture("hotel_exploration_two_handed")

	_key(player, KEY_N)
	_check(hud.notebook_overlay.visible and not hud.inventory_panel.visible and not hud.prompt_panel.visible, "N opens notebook and hides exploration UI")
	_check(not hud.exploration_shortcuts.visible and not hud.exploration_shade.visible, "new chrome hidden behind notebook")
	_check(hud.notebook_source_marks.size() == 56, "retain every notebook evidence binding")
	await _capture("hotel_exploration_notebook")
	_key(player, KEY_N)
	_check(hud.inventory_panel.visible, "N restores carry HUD")
	_key(player, KEY_T)
	_check(hud.watch_overlay.visible and not hud.stamina_panel.visible, "T hold shows real watch")
	await _capture("hotel_exploration_watch")
	_key(player, KEY_T, false)
	_check(not hud.watch_overlay.visible and hud.stamina_panel.visible, "T release restores exploration")
	hud.set_suitcase(controller.get_suitcase_slots_for_ui(), true)
	_check(hud.suitcase_overlay.visible and not hud.prompt_panel.visible, "suitcase blocks interaction prompt")
	hud.set_suitcase([], false)
	hud.set_map_open(true)
	_check(not hud.inventory_panel.visible, "debug map hides carry HUD")
	hud.set_map_open(false)
	hud.show_end("失败", "test")
	_check(hud.end_overlay.visible and not hud.inventory_panel.visible, "end overlay hides carry HUD")
	hud.hide_end()
	hud.set_inventory([], 0, false)
	_check(hud.carry_title.text == "空手" and not hud.carry_hint.text.contains("F"), "empty inventory offers no use hint")
	hud.set_inventory([{"item_id":"body", "uid":99, "anchor":true, "reserved":true, "display_name":"尸体", "slot_cost":2}], 0, true)
	_check(hud.inventory_icon_labels[0].text == "双手" and not hud.carry_hint.text.contains("F"), "iconless reserved body still has visible carry feedback")
	hud.set_inventory(controller.get_carry_slots_for_ui(), 1, true)
	hud.set_stamina(10.0, 100.0, true)
	hud.set_prompt("贴门听  1.5s")
	await process_frame
	await process_frame
	_check(hud.stamina_fill_style.bg_color == hud.DANGER, "low stamina uses danger color")
	_check(hud.prompt_label.text == "贴门听  1.5s" and hud.prompt_panel.modulate.a == 1.0, "timed action text remains intact and fully visible")
	await _capture("hotel_exploration_low_stamina")
	hud.capture_scare_finished.connect(func(): capture_finished = true)
	hud.play_capture_scare(&"guard")
	await create_timer(1.0).timeout
	_check(capture_finished, "capture completion signal reaches listeners")
	print("EXPLORATION_HUD_TEST assertions=%d failures=%d" % [assertions, failures])
	preview.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
