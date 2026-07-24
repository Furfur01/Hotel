extends SceneTree

## Headless integration coverage for the two-day run controller.
##
## The suite drives state transitions plus a small set of synthetic input and
## physical-door checks; failures therefore cover both controller branches and
## the real-time interaction contract.
##
## Run from the project root:
##   godot --headless --log-file /tmp/run_controller_test.log \
##     --path . --script res://tests/run_controller_test.gd

const MainScene = preload("res://hotel.tscn")
const RunState = preload("res://game_state.gd")

var _failures: Array[String] = []
var _assertion_count := 0
var _test_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("RUN_CONTROLLER_TEST start")
	await _test_safe_vacant_room_advances_to_day_two()
	await _test_lucky_rented_room_advances_without_crisis()
	await _test_ratchet_strap_skips_night_and_is_consumed()
	await _test_returning_tenant_clears_suitcase_and_starts_lead()
	await _test_third_daytime_capture_confiscates_and_ends_run()
	await _test_night_capture_is_game_over()
	await _test_tenant_kill_creates_cleanup_and_cleanup_completes()
	await _test_day_two_settlement_completes_prototype()
	await _test_day_change_detaches_old_floor()
	_test_night_lead_uses_total_budget()
	await _test_invalid_room_at_expiry_fails()
	await _test_day_two_wake_room_is_safe_and_stable()
	await _test_unclean_night_timeout_fails()
	await _test_normal_and_strapped_door_semantics()
	await _test_notebook_does_not_pause_timer()
	await _test_other_live_overlays_do_not_pause_timer()
	await _test_wing_scoped_access_and_power()
	await _test_context_actions_are_immediate_and_compact()
	await _test_door_action_animation_lifecycle()
	await _test_knock_auto_records_and_chases()
	await _test_closed_room_and_origin_protect_loose_items()
	await _test_night_cabinet_cannot_be_armed()
	await _test_cleaner_returns_item_and_alerts_guard()
	await _test_tenant_is_killed_by_deployed_trap()

	print("RUN_CONTROLLER_TEST summary tests=%d assertions=%d failures=%d" % [
		_test_count,
		_assertion_count,
		_failures.size(),
	])
	if _failures.is_empty():
		print("RUN_CONTROLLER_TEST all branches passed")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_safe_vacant_room_advances_to_day_two() -> void:
	_test_count += 1
	var context := await _new_runtime(1101)
	if not _runtime_ready(context, "safe vacant"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var room_id := _first_valid_guest(controller)
	_set_room_truth(controller, room_id, RunState.ASSIGNMENT_VACANT, RunState.PRESENCE_NONE, false)
	_place_player_in_room(controller, room_id)
	controller._settle_room(room_id, false)
	await _wait_frames(2)
	_check(controller.state.day_index == 2, "safe vacant: expected Day 2")
	_check(controller.state.phase == RunState.PHASE_DAY, "safe vacant: expected daytime after transition")
	_check(not controller._run_ended, "safe vacant: Day 1 success must not end the prototype")
	await _free_runtime(context)


func _test_lucky_rented_room_advances_without_crisis() -> void:
	_test_count += 1
	var context := await _new_runtime(1102)
	if not _runtime_ready(context, "lucky rented"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var room_id := _first_valid_guest(controller)
	_set_room_truth(controller, room_id, RunState.ASSIGNMENT_RENTED, RunState.PRESENCE_AWAY, false)
	_place_player_in_room(controller, room_id)
	controller._settle_room(room_id, false)
	await _wait_frames(2)
	_check(controller.state.day_index == 2, "lucky rented: a non-returning tenant should advance to Day 2")
	_check(controller.state.phase == RunState.PHASE_DAY, "lucky rented: should not enter a night crisis")
	_check(not controller._tenant_spawned, "lucky rented: returning tenant must not spawn")
	await _free_runtime(context)


func _test_ratchet_strap_skips_night_and_is_consumed() -> void:
	_test_count += 1
	var context := await _new_runtime(1103)
	if not _runtime_ready(context, "strap settlement"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var room_id := _first_valid_guest(controller)
	_set_room_truth(controller, room_id, RunState.ASSIGNMENT_RENTED, RunState.PRESENCE_INSIDE, true)
	var added: Dictionary = controller.state.add_item(RunState.CONTAINER_CARRY, "ratchet_strap")
	_check(bool(added.get("ok", false)), "strap settlement: setup item should fit in carry inventory")
	_place_player_in_room(controller, room_id)
	controller._settle_room(room_id, true)
	await _wait_frames(2)
	_check(controller.state.day_index == 2, "strap settlement: barricading should advance to Day 2")
	_check(controller.state.phase == RunState.PHASE_DAY, "strap settlement: barricading should skip night")
	_check(not _contains_item(controller.state.inventory, "ratchet_strap"), "strap settlement: strap must be one-use")
	await _free_runtime(context)


func _test_returning_tenant_clears_suitcase_and_starts_lead() -> void:
	_test_count += 1
	var context := await _new_runtime(1104)
	if not _runtime_ready(context, "returning tenant"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var room_id := _first_valid_guest(controller)
	_set_room_truth(controller, room_id, RunState.ASSIGNMENT_RENTED, RunState.PRESENCE_AWAY, true)
	var packed: Dictionary = controller.state.add_item(RunState.CONTAINER_SUITCASE, "instant_camera")
	_check(bool(packed.get("ok", false)), "returning tenant: suitcase setup item should fit")
	var carried: Dictionary = controller.state.set_suitcase_carried(true)
	_check(bool(carried.get("ok", false)), "returning tenant: suitcase should be carryable for settlement")
	_place_player_in_room(controller, room_id)
	controller._settle_room(room_id, false)
	_check(controller.state.phase == RunState.PHASE_NIGHT_LEAD, "returning tenant: wrong room should enter five-second lead")
	_check(float(controller.state.timers.lead) > 0.0, "returning tenant: lead timer should be positive")
	_check(_all_slots_empty(controller.state.suitcase_inventory), "returning tenant: suitcase contents must be cleared")
	_check(controller.state.suitcase_exists, "returning tenant: suitcase shell should remain")
	_check(controller.selected_room_id == room_id, "returning tenant: crisis should retain the selected room")
	_check(controller.guard_nodes.size() == 2, "Pac-Man roles: night crisis should have two guards")
	if controller.guard_nodes.size() == 2:
		_check(controller.guard_nodes[0].pursuit_role == HotelNPC.ROLE_CHASER, "Pac-Man roles: first guard should chase the current position")
		_check(controller.guard_nodes[1].pursuit_role == HotelNPC.ROLE_AMBUSHER, "Pac-Man roles: second guard should predict the next junction")
		controller.player.velocity = Vector3(4.0, 0.0, 0.0)
		var predicted: Vector3 = controller.guard_nodes[1]._pursuit_target()
		_check(predicted.x > controller.player.global_position.x + 4.0, "Pac-Man roles: ambusher target should lead a moving player")
	await _free_runtime(context)


func _test_third_daytime_capture_confiscates_and_ends_run() -> void:
	_test_count += 1
	var context := await _new_runtime(1105)
	if not _runtime_ready(context, "third capture"):
		await _free_runtime(context)
		return
	var controller = context.controller
	controller.state.add_item(RunState.CONTAINER_CARRY, "lockpick")
	controller.state.add_item(RunState.CONTAINER_SUITCASE, "industrial_cleaner")
	var initial_time := float(controller.state.timers.day)
	controller.player.global_position = controller.floor.get_room_spawn_position(_first_valid_guest(controller))
	controller.npc_caught(&"guard")
	await controller.hud.capture_scare_finished
	_check(controller.player.global_position.distance_to(controller.floor.get_lobby_spawn_position()) < 0.1, "day capture: player should teleport to the lobby only after the scare finishes")
	controller.npc_caught(&"guard")
	await controller.hud.capture_scare_finished
	_check(controller.state.strikes == 2, "third capture: first two captures should remain recoverable")
	_check(float(controller.state.timers.day) <= initial_time - 30.0, "third capture: first two captures should cost 15 seconds each")
	controller.npc_caught(&"guard")
	await controller.hud.capture_scare_finished
	_check(controller.state.strikes == 3, "third capture: strike counter should reach three")
	_check(controller.state.phase == RunState.PHASE_BLACK_ROOM, "third capture: expected black_room phase")
	_check(controller.state.day_index == 3, "third capture: calendar should jump forward two days")
	_check(_all_slots_empty(controller.state.inventory), "third capture: carry inventory should be confiscated")
	_check(_all_slots_empty(controller.state.suitcase_inventory), "third capture: suitcase inventory should be confiscated")
	_check(controller._run_ended, "third capture: current two-day prototype should end")
	await _free_runtime(context)


func _test_night_capture_is_game_over() -> void:
	_test_count += 1
	var context := await _new_runtime(1106)
	if not _runtime_ready(context, "night capture"):
		await _free_runtime(context)
		return
	var controller = context.controller
	controller.state.begin_night(false)
	controller.npc_caught(&"guard")
	await controller.hud.capture_scare_finished
	_check(controller.state.phase == RunState.PHASE_GAME_OVER, "night capture: guard contact should set game_over")
	_check(controller._run_ended, "night capture: run should end immediately")
	await _free_runtime(context)


func _test_tenant_kill_creates_cleanup_and_cleanup_completes() -> void:
	_test_count += 1
	var context := await _new_runtime(1107)
	if not _runtime_ready(context, "tenant cleanup"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var room_id := _first_valid_guest(controller)
	var kill_position: Vector3 = controller.floor.get_room_spawn_position(room_id)
	controller.state.begin_night(false)
	controller.selected_room_id = room_id
	controller.tenant_killed(null, kill_position, "folding_trap")
	_check(controller._tenant_defeated, "tenant cleanup: tenant kill should set defeated marker")
	_check(_valid_kind(controller._corpse_node, "corpse"), "tenant cleanup: kill should create a corpse marker")
	_check(_valid_kind(controller._stain_node, "stain"), "tenant cleanup: kill should create a blood-stain marker")

	var stain = controller._stain_node
	controller._wrap_corpse(controller._corpse_node, false)
	_check(_valid_kind(controller._corpse_node, "wrapped_corpse"), "tenant cleanup: wrapping should replace the corpse marker")
	controller._pickup_body(controller._corpse_node)
	_check(controller.state.carried_world_object == "body", "tenant cleanup: wrapped body should occupy both hands")
	var disposal_points: Array = controller.state.current_manifest.get("disposal_points", [])
	_check(not disposal_points.is_empty(), "tenant cleanup: manifest should provide a disposal point")
	if not disposal_points.is_empty():
		var disposal: Dictionary = disposal_points[0]
		controller._dispose_body(String(disposal.get("room_id", "")))
	_check(controller._corpse_disposed, "tenant cleanup: valid disposal should mark corpse complete")
	controller._clean_stain(stain, false)
	_check(controller._stain_cleaned, "tenant cleanup: cleaning should mark stain complete")
	_check(controller.state.day_index == 2, "tenant cleanup: completing both requirements should finish Day 1")
	await _wait_frames(2)
	_check(controller.state.phase == RunState.PHASE_DAY, "tenant cleanup: successful cleanup should load Day 2")
	await _free_runtime(context)


func _test_day_two_settlement_completes_prototype() -> void:
	_test_count += 1
	var context := await _new_runtime(1108)
	if not _runtime_ready(context, "Day 2 completion"):
		await _free_runtime(context)
		return
	var controller = context.controller
	controller.previous_guest_ordinal = 0
	controller.load_day(2)
	await _wait_frames(2)
	var room_id := _first_guest_other_than(controller, controller.current_previous_room_id)
	_check(not room_id.is_empty(), "Day 2 completion: a new guest room should exist")
	if not room_id.is_empty():
		_set_room_truth(controller, room_id, RunState.ASSIGNMENT_VACANT, RunState.PRESENCE_NONE, false)
		_place_player_in_room(controller, room_id)
		controller._settle_room(room_id, false)
	_check(controller.state.phase == RunState.PHASE_COMPLETE, "Day 2 completion: success should set complete phase")
	_check(controller.state.day_index == 2, "Day 2 completion: must not expose Day 3")
	_check(controller._run_ended, "Day 2 completion: prototype should end")
	await _free_runtime(context)


func _test_day_change_detaches_old_floor() -> void:
	_test_count += 1
	var context := await _new_runtime(1109)
	if not _runtime_ready(context, "floor lifecycle"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var old_floor = controller.floor
	controller.load_day(2)
	_check(not is_instance_valid(old_floor) or not old_floor.is_inside_tree(), "floor lifecycle: old floor must leave the tree immediately")
	await _wait_frames(2)
	_check(controller.floor != old_floor, "floor lifecycle: controller should own a fresh Floor node")
	_check(controller.floor != null and controller.floor.is_inside_tree(), "floor lifecycle: replacement floor should be in the tree")
	_check(controller.floor_host.get_child_count() == 1, "floor lifecycle: FloorHost should contain exactly one day floor")
	await _free_runtime(context)


func _test_night_lead_uses_total_budget() -> void:
	_test_count += 1
	var state = RunState.new(1201)
	state.begin_night(true)
	state.tick(2.0)
	_check(is_equal_approx(float(state.timers.lead), 3.0), "night budget: lead should count down")
	_check(is_equal_approx(float(state.timers.night), 118.0), "night budget: five-second lead must consume total night time")


func _test_invalid_room_at_expiry_fails() -> void:
	_test_count += 1
	var context := await _new_runtime(1202)
	if not _runtime_ready(context, "invalid expiry"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var function_id: String = controller.floor.get_function_room_id("storage")
	_place_player_in_room(controller, function_id)
	controller._on_day_timer_expired()
	_check(controller._run_ended, "invalid expiry: function room must end the run")
	_check(controller.state.phase == RunState.PHASE_GAME_OVER, "invalid expiry: expected game_over phase")
	await _free_runtime(context)


func _test_day_two_wake_room_is_safe_and_stable() -> void:
	_test_count += 1
	var context := await _new_runtime(1203)
	if not _runtime_ready(context, "Day 2 wake"):
		await _free_runtime(context)
		return
	var controller = context.controller
	controller.previous_guest_ordinal = 0
	controller.previous_room_number = "E-299"
	controller.load_day(2)
	await _wait_frames(2)
	var wake_id: String = controller.current_previous_room_id
	_check(not wake_id.is_empty(), "Day 2 wake: previous room should map to new floor")
	_check(String(controller.floor.get_room_descriptor(wake_id).get("display_number", "")) == "E-299", "Day 2 wake: visible room identity should persist")
	_set_room_truth(controller, wake_id, RunState.ASSIGNMENT_RENTED, RunState.PRESENCE_INSIDE, true)
	controller._check_day_intrusion()
	_check(controller.state.strikes == 0, "Day 2 wake: previous room must be an intrusion-safe spawn")
	await _free_runtime(context)


func _test_unclean_night_timeout_fails() -> void:
	_test_count += 1
	var context := await _new_runtime(1204)
	if not _runtime_ready(context, "unclean timeout"):
		await _free_runtime(context)
		return
	var controller = context.controller
	controller.state.begin_night(false)
	controller._tenant_defeated = true
	controller._corpse_disposed = false
	controller._stain_cleaned = false
	controller.state.timers.night = 0.0
	controller._process(0.0)
	_check(controller._run_ended, "unclean timeout: unfinished scene must end the run")
	_check(controller.state.phase == RunState.PHASE_GAME_OVER, "unclean timeout: expected game_over")
	await _free_runtime(context)


func _test_normal_and_strapped_door_semantics() -> void:
	_test_count += 1
	var context := await _new_runtime(1205)
	if not _runtime_ready(context, "door semantics"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var room_id := _first_valid_guest(controller)
	var descriptor: Dictionary = controller.floor.get_room_descriptor(room_id)
	var door = controller.floor.door_nodes.get(room_id)
	var corridor: Vector2i = descriptor.corridor_tile
	var tile: Vector2i = descriptor.door_tile
	var corridor_world: Vector3 = controller.floor.cell_pos(corridor.x, corridor.y)
	var room_world: Vector3 = controller.floor.cell_pos(tile.x, tile.y)
	door.set_door_open(false, true)
	_check(controller.floor.ensure_npc_passage(corridor_world, room_world), "door semantics: ordinary closed door should yield to a pursuer")
	_check(door.door_open, "door semantics: pursuer should open an ordinary door")
	controller.floor.seal_door(door, 10.0)
	_check(not controller.floor.ensure_npc_passage(corridor_world, room_world), "door semantics: strapped door must block NPC passage")
	door.data["sealed_until"] = 0.0
	_check(controller.floor.ensure_npc_passage(corridor_world, room_world), "door semantics: expired strap should release passage")
	await _free_runtime(context)


func _test_notebook_does_not_pause_timer() -> void:
	_test_count += 1
	var context := await _new_runtime(1206)
	if not _runtime_ready(context, "live notebook"):
		await _free_runtime(context)
		return
	var controller = context.controller
	controller.player.notebook_open = true
	controller.player.refresh_notebook_data()
	var before := float(controller.state.timers.day)
	controller._process(1.0)
	_check(float(controller.state.timers.day) <= before - 0.99, "live notebook: timer must continue while open")
	await _free_runtime(context)


func _test_other_live_overlays_do_not_pause_timer() -> void:
	_test_count += 1
	var context := await _new_runtime(1212)
	if not _runtime_ready(context, "live overlays"):
		await _free_runtime(context)
		return
	var controller = context.controller

	controller.player.suitcase_open = true
	controller.hud.set_suitcase([], true)
	var before := float(controller.state.timers.day)
	controller._process(0.5)
	_check(float(controller.state.timers.day) <= before - 0.49, "live overlays: suitcase must not pause time")
	controller.player.suitcase_open = false
	controller.hud.set_suitcase([], false)

	controller.player.debug_map_open = true
	controller.player._update_debug_map()
	before = float(controller.state.timers.day)
	controller._process(0.5)
	_check(float(controller.state.timers.day) <= before - 0.49, "live overlays: debug map must not pause time")
	controller.player.debug_map_open = false
	controller.player._update_debug_map()

	controller.player._set_watch_open(true)
	before = float(controller.state.timers.day)
	controller._process(0.5)
	_check(float(controller.state.timers.day) <= before - 0.49, "live overlays: raised watch must not pause time")
	controller.player._set_watch_open(false)
	await _free_runtime(context)


func _test_wing_scoped_access_and_power() -> void:
	_test_count += 1
	var context := await _new_runtime(1213)
	if not _runtime_ready(context, "wing-scoped tools"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var room_by_wing: Dictionary = {}
	for descriptor_value in controller.floor.room_descriptors:
		var descriptor: Dictionary = descriptor_value
		var wing := String(descriptor.get("wing", ""))
		if not wing.is_empty() and not room_by_wing.has(wing):
			room_by_wing[wing] = String(descriptor.get("room_id", ""))
	var wings: Array = room_by_wing.keys()
	_check(wings.size() >= 2, "wing-scoped tools: generated floor needs at least two occupied wings")
	if wings.size() < 2:
		await _free_runtime(context)
		return
	var active_wing := String(wings[0])
	var other_wing := String(wings[1])
	controller.player.global_position = controller.floor.get_room_spawn_position(String(room_by_wing[active_wing]))
	controller._staff_access_time = 5.0
	controller._staff_access_wing = active_wing
	_check(is_equal_approx(controller.guard_personal_space(1.3), 0.48), "wing-scoped tools: staff access should reduce guard range in its wing")
	controller.player.global_position = controller.floor.get_room_spawn_position(String(room_by_wing[other_wing]))
	_check(is_equal_approx(controller.guard_personal_space(1.3), 1.3), "wing-scoped tools: staff access must not cross into another wing")

	controller._disable_lights(20.0, active_wing)
	var active_dimmed := false
	var other_preserved := false
	for light_value in controller.floor.lights:
		var omni: OmniLight3D = light_value.omni
		var light_wing: String = controller.floor.get_wing_at_world(omni.global_position)
		if light_wing == active_wing:
			active_dimmed = active_dimmed or omni.light_energy <= 0.031
		elif light_wing == other_wing:
			other_preserved = other_preserved or omni.light_energy > 0.031
	_check(active_dimmed, "wing-scoped tools: electrician kit should dim lights in the active wing")
	_check(other_preserved, "wing-scoped tools: electrician kit should preserve lights in other wings")

	var function_room_id := ""
	for descriptor_value in controller.floor.room_descriptors:
		var descriptor: Dictionary = descriptor_value
		if String(descriptor.get("room_type", "guest")) != "guest":
			function_room_id = String(descriptor.get("room_id", ""))
			break
	var kit_added: Dictionary = controller.state.add_item(RunState.CONTAINER_CARRY, "electrician_kit")
	_check(bool(kit_added.get("ok", false)), "wing-scoped tools: electrician kit should fit for the facility test")
	var function_door = controller.floor.door_nodes.get(function_room_id)
	var has_electronic_unlock := false
	if function_door != null:
		for action_value in function_door.get_actions(controller.player):
			if String((action_value as Dictionary).get("id", "")) == "unlock_electrician":
				has_electronic_unlock = true
				break
	_check(has_electronic_unlock, "wing-scoped tools: locked function rooms should expose the electronic unlock")
	if function_door != null:
		controller.perform_floor_action(controller.floor, function_door, "unlock_electrician", controller.player)
		_check(not bool(function_door.data.get("locked", true)), "wing-scoped tools: electrician kit should open one electronic facility")
	await _free_runtime(context)


func _test_context_actions_are_immediate_and_compact() -> void:
	_test_count += 1
	var context := await _new_runtime(1207)
	if not _runtime_ready(context, "compact context action"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var room_id := _first_valid_guest(controller)
	var door = controller.floor.door_nodes.get(room_id)
	door.data["locked"] = false
	door.set_door_open(false, true)
	controller.player.current_interact = door
	controller.player._context_target = door
	controller.player.context_options = door.get_actions(controller.player)
	var door_action_ids: Array[String] = []
	for action_value in controller.player.context_options:
		door_action_ids.append(String((action_value as Dictionary).get("id", "")))
	_check(not door_action_ids.has("register_plate"), "automatic notebook: doors must not require a separate plate-record action")
	controller.player.context_index = 0
	controller.player._execute_context_action()
	_check(door.door_open, "compact action: pressing E should execute the primary zero-duration action immediately")
	controller.player.context_options = door.get_actions(controller.player)
	controller.player.context_index = 0
	var selected_before: int = controller.player.selected_slot
	controller.player._cycle_context_action()
	_check(controller.player.context_index == 1, "compact action: R should cycle to the next contextual action")
	_check(controller.player.selected_slot == selected_before, "compact action: cycling actions must not change inventory slot")
	_check(controller.hud.get_node_or_null("ActionWheel") == null, "compact action: radial overlay must never be constructed")
	_check(controller.player._footstep_streams.size() == 5, "sound: player should load five carpet footstep variations")
	controller.on_player_action_started("knock", door)
	await _wait_frames(1)
	_check(not controller.floor.find_children("WorldSFX", "AudioStreamPlayer3D", true, false).is_empty(), "sound: knocking should spawn a positional world sound")
	controller.perform_floor_action(controller.floor, door, "observe", controller.player)
	var auto_entry: Dictionary = controller.state.get_notebook_entry(room_id)
	_check(not auto_entry.is_empty() and bool(auto_entry.checked.get("doorstep", false)), "automatic notebook: finishing a test must create and fill its room entry")
	for interactable_value in controller.floor.get_tree().get_nodes_in_group("interactable"):
		if controller.floor.is_ancestor_of(interactable_value) and String(interactable_value.kind) == "bed" and String(interactable_value.data.get("room_id", "")) == room_id:
			var bed_action_ids: Array[String] = []
			for action_value in interactable_value.get_actions(controller.player):
				bed_action_ids.append(String((action_value as Dictionary).get("id", "")))
			_check(not bed_action_ids.has("inspect_room"), "room flow: beds must not expose the removed interior-inspection action")
			break
	await _free_runtime(context)


func _test_knock_auto_records_and_chases() -> void:
	_test_count += 1
	var context := await _new_runtime(1210)
	if not _runtime_ready(context, "knock pursuit"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var inside_id := ""
	var empty_id := ""
	for room_value in controller.state.current_manifest.get("guest_rooms", []):
		var room: Dictionary = room_value
		if String(room.get("presence", "")) == RunState.PRESENCE_INSIDE and inside_id.is_empty():
			inside_id = String(room.get("room_id", ""))
		elif String(room.get("presence", "")) != RunState.PRESENCE_INSIDE and empty_id.is_empty():
			empty_id = String(room.get("room_id", ""))
	_check(not inside_id.is_empty() and not empty_id.is_empty(), "knock pursuit: manifest must offer answered and unanswered doors")
	if not inside_id.is_empty():
		controller._handle_knock(inside_id)
		var answered: Dictionary = controller.state.get_notebook_entry(inside_id)
		_check(bool(answered.checked.get("knock", false)), "knock pursuit: answered knock must be recorded automatically")
		_check(controller.tenant_node != null and controller._knock_chase_time > 0.0, "knock pursuit: an occupant must burst out and start a timed chase")
		controller._tick_knock_chase(controller.KNOCK_CHASE_SECONDS + 0.1)
		_check(controller.tenant_node == null and controller._knock_chase_time == 0.0, "knock pursuit: surviving the chase must dismiss the occupant")
	if not empty_id.is_empty():
		controller._handle_knock(empty_id)
		var unanswered: Dictionary = controller.state.get_notebook_entry(empty_id)
		_check(String(unanswered.evidence.get("knock", "")) == RunState.KNOCK_NO_RESPONSE, "knock pursuit: silence must be stored as the raw no-response result")
		_check(controller.tenant_node == null, "knock pursuit: an unanswered door must not spawn a pursuer")
	await _free_runtime(context)


func _test_door_action_animation_lifecycle() -> void:
	_test_count += 1
	var context := await _new_runtime(1212)
	if not _runtime_ready(context, "door action animation"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var player = controller.player
	var room_id := _first_valid_guest(controller)
	var door = controller.floor.door_nodes.get(room_id)
	_check(door != null, "door action animation: guest door must exist")
	if door == null:
		await _free_runtime(context)
		return
	_set_room_truth(controller, room_id, RunState.ASSIGNMENT_VACANT, RunState.PRESENCE_NONE, false)
	door.data["locked"] = false
	door.set_door_open(false, true)
	var knock_option: Dictionary = {}
	var listen_option: Dictionary = {}
	for action_value in door.get_actions(player):
		var option := action_value as Dictionary
		if String(option.get("id", "")) == "knock":
			knock_option = option
		elif String(option.get("id", "")) == "listen":
			listen_option = option
	_check(not knock_option.is_empty(), "door action animation: knock option must exist")
	_check(not listen_option.is_empty(), "door action animation: listen option must exist")
	player._execute_action(door, knock_option)
	_check(player.active_action_id() == "knock", "door action animation: real interaction path must start the timed knock")
	_check(player.is_door_interaction_animating(), "door action animation: knock must display the foreground hand")
	_check(player.door_action_sprite.texture != null and player.door_action_sprite.texture.get_size() == Vector2(512, 320), "door action animation: low-resolution 8-frame sheet must load")
	_check(player.door_action_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "door action animation: hand frames must use nearest filtering")
	var first_frame: int = player.door_action_sprite.frame
	player._tick_door_interaction(0.18)
	_check(player.door_action_sprite.frame != first_frame, "door action animation: knock must advance through distinct poses")
	player.cancel_timed_action("")
	_check(not player.is_door_interaction_animating(), "door action animation: cancel must hide the foreground hand")
	var cancelled_entry: Dictionary = controller.state.get_notebook_entry(room_id)
	_check(cancelled_entry.is_empty() or not bool(cancelled_entry.get("checked", {}).get("knock", false)), "door action animation: cancelling must not complete or record the knock")

	var open_option: Dictionary = {}
	for action_value in door.get_actions(player):
		var option := action_value as Dictionary
		if String(option.get("id", "")) == "open_door":
			open_option = option
			break
	player._execute_action(door, open_option)
	_check(door.door_open, "door action animation: zero-duration open must keep its immediate gameplay result")
	_check(player.is_door_interaction_animating(), "door action animation: zero-duration open must still play a short one-shot")
	player._tick_door_interaction(0.5)
	_check(not player.is_door_interaction_animating(), "door action animation: open one-shot must clean itself up")

	door.set_door_open(false, true)
	player._execute_action(door, knock_option)
	player._tick_timed_action(3.1)
	var completed_entry: Dictionary = controller.state.get_notebook_entry(room_id)
	_check(bool(completed_entry.get("checked", {}).get("knock", false)), "door action animation: finished knock must retain automatic recording")
	player._tick_door_interaction(0.6)
	_check(not player.is_door_interaction_animating(), "door action animation: completed knock must not leave a stuck overlay")

	var neutral_camera_position: Vector3 = player.camera.position
	var neutral_camera_roll: float = player.camera.rotation.z
	player._execute_action(door, listen_option)
	_check(player.active_action_id() == "listen", "listen lean: real interaction path must start listening")
	_check(player.is_door_interaction_animating(), "listen lean: camera-only action must have an active lifecycle")
	_check(not player.door_action_sprite.visible, "listen lean: listening must not draw a fake ear or hand overlay")
	player._tick_door_interaction(0.5)
	_check(player.camera.position.distance_to(neutral_camera_position) > 0.08, "listen lean: camera must move toward the door")
	_check(absf(player.camera.rotation.z - neutral_camera_roll) > deg_to_rad(2.0), "listen lean: camera must visibly roll sideways")
	player.cancel_timed_action("")
	_check(player.camera.position.distance_to(neutral_camera_position) < 0.001 and absf(player.camera.rotation.z - neutral_camera_roll) < 0.001, "listen lean: cancel must restore the exact camera pose")

	player._execute_action(door, listen_option)
	player._tick_door_interaction(0.5)
	player._tick_timed_action(2.1)
	var listened_entry: Dictionary = controller.state.get_notebook_entry(room_id)
	_check(bool(listened_entry.get("checked", {}).get("listen", false)), "listen lean: completed listening must retain automatic recording")
	_check(player.camera.position.distance_to(neutral_camera_position) < 0.001 and absf(player.camera.rotation.z - neutral_camera_roll) < 0.001, "listen lean: completion must restore the exact camera pose")

	player._execute_action(door, listen_option)
	player._tick_door_interaction(0.5)
	player.reset_transient_floor_state()
	_check(not player.is_door_interaction_animating(), "listen lean: floor reset must end the camera-only animation")
	_check(player.camera.position.distance_to(neutral_camera_position) < 0.001 and absf(player.camera.rotation.z - neutral_camera_roll) < 0.001, "listen lean: floor reset must restore the exact camera pose")
	await _free_runtime(context)


func _test_closed_room_and_origin_protect_loose_items() -> void:
	_test_count += 1
	var context := await _new_runtime(1208)
	if not _runtime_ready(context, "loose item visibility"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var room_id := _first_valid_guest(controller)
	var room_position: Vector3 = controller.floor.get_room_clear_position(room_id, 0.4)
	var origin: Vector3 = controller.floor.get_lobby_spawn_position()
	var marker = controller.floor.spawn_item_pickup("alarm_clock", room_position, room_id, origin)
	controller.floor.set_room_door_open(room_id, false)
	_check(not controller.floor.get_loose_items().has(marker), "loose item: closed guest room must protect cache")
	controller.floor.set_room_door_open(room_id, true)
	_check(controller.floor.get_loose_items().has(marker), "loose item: open room should expose displaced cache")
	marker.global_position = origin
	_check(not controller.floor.get_loose_items().has(marker), "loose item: object already at origin must not trap cleaner AI")
	marker.visible = false
	marker.global_position += Vector3(2.0, 0.0, 0.0)
	_check(not controller.floor.get_loose_items().has(marker), "loose item: carried invisible object must be ignored")
	await _free_runtime(context)


func _test_night_cabinet_cannot_be_armed() -> void:
	_test_count += 1
	var context := await _new_runtime(1209)
	if not _runtime_ready(context, "night cabinet"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var room_id := _first_valid_guest(controller)
	var cabinet = null
	for node in controller.floor.get_tree().get_nodes_in_group("interactable"):
		if controller.floor.is_ancestor_of(node) and String(node.kind) == "cabinet" and String(node.data.get("room_id", "")) == room_id:
			cabinet = node
			break
	controller.state.begin_night(false)
	controller.perform_floor_action(controller.floor, cabinet, "arm_cabinet", controller.player)
	_check(not bool(controller.floor.get_room_runtime(room_id).get("cabinet_armed", false)), "night cabinet: traps must be prepared during daytime")
	await _free_runtime(context)


func _test_cleaner_returns_item_and_alerts_guard() -> void:
	_test_count += 1
	var context := await _new_runtime(1210)
	if not _runtime_ready(context, "cleaner logistics"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var origin: Vector3 = controller.floor.get_lobby_spawn_position()
	var marker = controller.floor.spawn_item_pickup("alarm_clock", origin + Vector3(2.0, 0.2, 0.0), "", origin)
	controller.cleaner_node.global_position = marker.global_position
	controller.cleaner_node._loose_target = marker
	controller.cleaner_node._tick_cleaner(0.05)
	_check(marker.global_position.distance_to(origin) <= 0.01, "cleaner logistics: displaced loose item should return to origin")
	controller.cleaner_report(origin)
	var guard_alerted := false
	for guard in controller.guard_nodes:
		guard_alerted = guard_alerted or guard._incident_active
	_check(guard_alerted, "cleaner logistics: report should dispatch a guard")
	await _free_runtime(context)


func _test_tenant_is_killed_by_deployed_trap() -> void:
	_test_count += 1
	var context := await _new_runtime(1211)
	if not _runtime_ready(context, "tenant trap"):
		await _free_runtime(context)
		return
	var controller = context.controller
	var room_id := _first_valid_guest(controller)
	controller.selected_room_id = room_id
	controller.state.begin_night(false)
	controller._tenant_spawned = false
	controller._spawn_returning_tenant()
	_check(controller.tenant_node != null, "tenant trap: returning tenant should spawn")
	if controller.tenant_node != null:
		var trap = controller.floor.spawn_deployed_trap(controller.tenant_node.global_position)
		controller.floor._check_night_hazards()
		_check(controller._tenant_defeated, "tenant trap: deployed trap should kill only the returning tenant")
		_check(_valid_kind(controller._corpse_node, "corpse"), "tenant trap: kill should create cleanup corpse")
		_check(not is_instance_valid(trap) or trap.is_queued_for_deletion(), "tenant trap: deployed trap should be consumed")
	await _free_runtime(context)


func _new_runtime(seed_value: int) -> Dictionary:
	var game_root = MainScene.instantiate()
	root.add_child(game_root)
	await _wait_frames(1)
	var controller = game_root.get_node_or_null("RunController")
	if controller != null:
		controller.start_new_run(seed_value)
	await _wait_frames(2)
	return {
		"game_root": game_root,
		"controller": controller,
	}


func _free_runtime(context: Dictionary) -> void:
	var game_root = context.get("game_root")
	if game_root != null and is_instance_valid(game_root):
		game_root.queue_free()
	await _wait_frames(2)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _runtime_ready(context: Dictionary, label: String) -> bool:
	var controller = context.get("controller")
	var ready := controller != null and controller.state != null and controller.floor != null
	_check(ready, "%s: controller/floor failed to become ready" % label)
	return ready


func _first_valid_guest(controller) -> String:
	if controller == null or controller.floor == null:
		return ""
	var guest_ids: Array[String] = controller.floor.get_guest_room_ids()
	return "" if guest_ids.is_empty() else guest_ids[0]


func _first_guest_other_than(controller, excluded_room_id: String) -> String:
	if controller == null or controller.floor == null:
		return ""
	for room_id in controller.floor.get_guest_room_ids():
		if String(room_id) != excluded_room_id:
			return String(room_id)
	return ""


func _set_room_truth(
	controller,
	room_id: String,
	assignment: String,
	presence: String,
	returns_tonight: bool
) -> void:
	var rooms: Array = controller.state.current_manifest.get("guest_rooms", [])
	for index in range(rooms.size()):
		var room: Dictionary = rooms[index]
		if String(room.get("room_id", "")) != room_id:
			continue
		room["assignment"] = assignment
		room["presence"] = presence
		room["returns_tonight"] = returns_tonight
		rooms[index] = room
		controller.state.current_manifest["guest_rooms"] = rooms
		return
	_check(false, "test setup: room truth not found for %s" % room_id)


func _place_player_in_room(controller, room_id: String) -> void:
	controller.player.global_position = controller.floor.get_room_spawn_position(room_id)
	controller.player.safe_pos = controller.player.global_position
	controller.player.velocity = Vector3.ZERO


func _contains_item(slots: Array, item_id: String) -> bool:
	for slot in slots:
		if slot is Dictionary and String(slot.get("item_id", "")) == item_id:
			return true
	return false


func _all_slots_empty(slots: Array) -> bool:
	for slot in slots:
		if slot != null:
			return false
	return true


func _valid_kind(node, expected_kind: String) -> bool:
	return node != null and is_instance_valid(node) and String(node.kind) == expected_kind


func _check(condition: bool, message: String) -> void:
	_assertion_count += 1
	if not condition:
		_failures.append(message)
