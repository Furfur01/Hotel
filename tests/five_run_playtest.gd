extends SceneTree

## Five deterministic, consecutive two-day pressure runs against the real main
## scene.  The driver uses generated pickups, door/cabinet/bed/cleanup action
## options and Player's timed-action callback path.  Movement time is charged
## from HotelFloor's real shortest paths at the conservative exhausted carry
## speed; an additional eight seconds is deliberately spent as control slack.

const MainScene = preload("res://hotel.tscn")
const RunState = preload("res://game_state.gd")

const RUN_COUNT := 5
const FIRST_SEED := 73001

var failures: Array[String] = []
var records: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("FIVE_RUN_PLAYTEST start runs=%d seeds=%d..%d" % [RUN_COUNT, FIRST_SEED, FIRST_SEED + RUN_COUNT - 1])
	for run_index in range(RUN_COUNT):
		var seed_value := FIRST_SEED + run_index
		var game_root = MainScene.instantiate()
		root.add_child(game_root)
		await _frames(2)
		var controller = game_root.get_node_or_null("RunController")
		if controller == null:
			_fail(seed_value, 0, "RunController missing")
			game_root.queue_free()
			await _frames(2)
			continue
		controller.start_new_run(seed_value)
		await _frames(3)
		for expected_day in [1, 2]:
			if controller.state == null or controller.floor == null or controller.state.day_index != expected_day:
				_fail(seed_value, expected_day, "day/floor failed to load")
				break
			var result := await _play_pressure_night(controller, seed_value, expected_day)
			records.append(result)
			if not bool(result.get("ok", false)):
				break
			if expected_day == 1:
				await _frames(4)
		if controller.state == null or controller.state.phase != RunState.PHASE_COMPLETE:
			_fail(seed_value, 2, "two-day run did not reach PHASE_COMPLETE")
		game_root.queue_free()
		await _frames(3)

	print("seed  day  room     disposal  day_used  theory  night_used  remaining  margin  result")
	for record in records:
		print("%d  %d    %-8s %-8s   %6.2f   %5.2f     %5.2f      %6.2f    %5.1f%%  %s" % [
			int(record.get("seed", 0)),
			int(record.get("day", 0)),
			String(record.get("room_number", "-")),
			String(record.get("disposal_number", "-")),
			float(record.get("day_used_seconds", 0.0)),
			float(record.get("theory_seconds", 0.0)),
			float(record.get("used_seconds", 0.0)),
			float(record.get("remaining_seconds", 0.0)),
			float(record.get("remaining_ratio", 0.0)) * 100.0,
			"PASS" if bool(record.get("ok", false)) else "FAIL",
		])
	print("FIVE_RUN_PLAYTEST summary runs=%d day_nights=%d failures=%d" % [RUN_COUNT, records.size(), failures.size()])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() and records.size() == RUN_COUNT * 2 else 1)


func _play_pressure_night(controller, seed_value: int, day: int) -> Dictionary:
	var room_id := _worst_dangerous_room(controller)
	if room_id.is_empty():
		_fail(seed_value, day, "no eligible returning-tenant room")
		return _record_failure(seed_value, day)
	# With five early guest rooms there may be only one away tenant, and that
	# tenant can legitimately roll "not returning".  This is the deliberate
	# worst-case night driver, so force that selected away tenant to return.
	_force_returning_tenant(controller, room_id)
	var solution: Dictionary = controller.theoretical_night_solution(room_id)
	if not bool(solution.get("ok", false)):
		_fail(seed_value, day, "theoretical route failed: %s" % solution)
		return _record_failure(seed_value, day)
	var disposal_id := String(solution.get("disposal_room_id", ""))
	var laundry_id: String = controller.floor.get_function_room_id("laundry")
	var start_position: Vector3 = controller.player.global_position
	var lobby_position: Vector3 = controller.floor.get_lobby_spawn_position()
	var laundry_descriptor: Dictionary = controller.floor.get_room_descriptor(laundry_id)
	var disposal_descriptor_before: Dictionary = controller.floor.get_room_descriptor(disposal_id)
	var room_descriptor_before: Dictionary = controller.floor.get_room_descriptor(room_id)
	var preparation_distance: float = float(controller.floor.path_distance_world(start_position, lobby_position))
	preparation_distance += controller.floor.path_distance_world(lobby_position, laundry_descriptor.center)
	if disposal_id != laundry_id:
		preparation_distance += controller.floor.path_distance_world(laundry_descriptor.center, disposal_descriptor_before.center)
		preparation_distance += controller.floor.path_distance_world(disposal_descriptor_before.center, room_descriptor_before.center)
	else:
		preparation_distance += controller.floor.path_distance_world(laundry_descriptor.center, room_descriptor_before.center)
	# Four metres per second is deliberately more conservative than an optimal
	# sprint/stamina schedule.  This charge makes every setup route legal inside
	# the real four-minute day even though the headless driver skips rendered walking.
	_advance_clock(controller, preparation_distance / 4.0)
	if controller.state.phase != RunState.PHASE_DAY:
		_fail(seed_value, day, "day preparation travel exceeded the clock")
		return _record_failure(seed_value, day)

	# Open the laundry using an actually generated public pick, then collect the
	# two guaranteed fast-cleanup tools through pickup action options.
	controller.player.global_position = laundry_descriptor.center
	controller.player.safe_pos = laundry_descriptor.center
	if not _open_locked_room(controller, laundry_id, seed_value, day):
		return _record_failure(seed_value, day)
	if not _take_generated_pickup(controller, "ratchet_strap", "laundry"):
		_fail(seed_value, day, "ratchet strap pickup missing")
		return _record_failure(seed_value, day)
	if not _take_generated_pickup(controller, "industrial_cleaner", "laundry"):
		_fail(seed_value, day, "industrial cleaner pickup missing")
		return _record_failure(seed_value, day)

	# The chosen disposal must be found during the day and its door must stay
	# usable at night.  This exercises the hidden-point discovery action.
	controller.player.global_position = disposal_descriptor_before.center
	controller.player.safe_pos = disposal_descriptor_before.center
	if not _open_locked_room(controller, disposal_id, seed_value, day):
		return _record_failure(seed_value, day)
	var facility = _find_interactable(controller.floor, "facility", disposal_id)
	if facility == null or not _run_action(controller, facility, "search_facility"):
		_fail(seed_value, day, "active disposal facility could not be searched")
		return _record_failure(seed_value, day)

	if not _open_locked_room(controller, room_id, seed_value, day):
		return _record_failure(seed_value, day)
	var cabinet = _find_interactable(controller.floor, "cabinet", room_id)
	controller.player.global_position = room_descriptor_before.center
	controller.player.safe_pos = room_descriptor_before.center
	if cabinet == null or not _run_action(controller, cabinet, "arm_cabinet"):
		_fail(seed_value, day, "cabinet could not be armed")
		return _record_failure(seed_value, day)
	var bed = _find_interactable(controller.floor, "bed", room_id)
	if bed == null:
		_fail(seed_value, day, "bed interaction missing")
		return _record_failure(seed_value, day)
	controller.player.global_position = controller.floor.get_room_spawn_position(room_id)
	controller.player.safe_pos = controller.player.global_position
	var day_used := RunState.DAY_SECONDS - float(controller.state.timers.day) + 1.0
	if not _run_action(controller, bed, "settle"):
		_fail(seed_value, day, "bed settle action failed")
		return _record_failure(seed_value, day)
	if controller.state.phase != RunState.PHASE_NIGHT_LEAD:
		_fail(seed_value, day, "danger room did not start night lead phase=%s player_room=%s truth=%s" % [
			controller.state.phase,
			controller.floor.get_room_id_at_world(controller.player.global_position),
			controller.state.find_room(room_id),
		])
		return _record_failure(seed_value, day)

	var night_start := float(controller.state.timers.night)
	_advance_clock(controller, RunState.NIGHT_LEAD_SECONDS)
	if controller.tenant_node == null or not is_instance_valid(controller.tenant_node):
		_fail(seed_value, day, "returning tenant did not spawn")
		return _record_failure(seed_value, day)
	var tenant_seconds := float(solution.get("tenant_distance", 0.0)) / RunState.TENANT_CHASE_SPEED
	_advance_clock(controller, tenant_seconds)
	var descriptor: Dictionary = controller.floor.get_room_descriptor(room_id)
	controller.tenant_node.global_position = descriptor.center
	controller.floor._check_night_hazards()
	if not controller._tenant_defeated:
		_fail(seed_value, day, "armed cabinet did not kill tenant")
		return _record_failure(seed_value, day)

	var stain = controller._stain_node
	var corpse = controller._corpse_node
	if stain == null or corpse == null:
		_fail(seed_value, day, "cleanup objects missing")
		return _record_failure(seed_value, day)
	if not _run_action(controller, stain, "clean_stain_spray"):
		_fail(seed_value, day, "fast stain cleanup failed")
		return _record_failure(seed_value, day)
	if not _run_action(controller, corpse, "wrap_corpse_strap"):
		_fail(seed_value, day, "fast corpse wrap failed")
		return _record_failure(seed_value, day)
	if not _run_action(controller, controller._corpse_node, "carry_corpse"):
		_fail(seed_value, day, "corpse pickup failed")
		return _record_failure(seed_value, day)

	_advance_clock(controller, float(solution.get("heavy_distance", 0.0)) / RunState.EXHAUSTED_HEAVY_SPEED)
	_advance_clock(controller, RunState.THEORY_CONTROL_BUFFER_SECONDS)
	var disposal = _find_interactable(controller.floor, "disposal", disposal_id)
	if disposal == null:
		_fail(seed_value, day, "disposal interaction missing")
		return _record_failure(seed_value, day)
	controller.player.global_position = disposal.global_position
	controller.player.safe_pos = disposal.global_position
	if not _run_action(controller, disposal, "dispose_body", false):
		_fail(seed_value, day, "body disposal action failed")
		return _record_failure(seed_value, day)
	var remaining := float(controller.state.timers.night)
	# Finish the already-counted disposal callback after capturing its deadline.
	controller.player._tick_timed_action(RunState.BODY_DISPOSE_SECONDS + 0.001)
	var used := night_start - remaining
	var margin_ratio := remaining / RunState.NIGHT_SECONDS
	var ok := used <= RunState.NIGHT_THEORY_MAX_SECONDS + 0.001 and margin_ratio >= 0.50 - 0.0001
	if not ok:
		_fail(seed_value, day, "used %.2fs, remaining %.2fs" % [used, remaining])
	var disposal_descriptor: Dictionary = controller.floor.get_room_descriptor(disposal_id) if controller.floor != null and is_instance_valid(controller.floor) else {}
	return {
		"ok": ok,
		"seed": seed_value,
		"day": day,
		"room_number": String(descriptor.get("display_number", room_id)),
		"disposal_number": String(disposal_descriptor.get("display_number", disposal_id)),
		"day_used_seconds": day_used,
		"theory_seconds": float(solution.get("fast_seconds", 0.0)),
		"used_seconds": used,
		"remaining_seconds": remaining,
		"remaining_ratio": margin_ratio,
	}


func _open_locked_room(controller, room_id: String, seed_value: int, day: int) -> bool:
	if room_id.is_empty():
		_fail(seed_value, day, "empty room id while opening")
		return false
	var door = controller.floor.door_nodes.get(room_id)
	if door == null:
		_fail(seed_value, day, "door missing for %s" % room_id)
		return false
	if bool(door.data.get("locked", false)):
		if not _take_generated_pickup(controller, "lockpick", "public"):
			_fail(seed_value, day, "public lockpick exhausted for %s" % room_id)
			return false
		if not _run_action(controller, door, "unlock_lockpick"):
			_fail(seed_value, day, "lockpick action failed for %s" % room_id)
			return false
	if not door.door_open and not _run_action(controller, door, "open_door"):
		_fail(seed_value, day, "open action failed for %s" % room_id)
		return false
	return true


func _take_generated_pickup(controller, item_id: String, zone: String) -> bool:
	for pickup in controller.floor.pickup_nodes:
		if pickup == null or not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
			continue
		if String(pickup.data.get("item_id", "")) != item_id:
			continue
		var room_id := String(pickup.data.get("room_id", ""))
		if zone == "public" and not room_id.is_empty():
			continue
		if zone == "laundry" and room_id != controller.floor.get_function_room_id("laundry"):
			continue
		return _run_action(controller, pickup, "pickup_item")
	return false


func _run_action(controller, target, action_id: String, finish := true) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var selected: Dictionary = {}
	for option_value in target.get_actions(controller.player):
		var option: Dictionary = option_value
		if String(option.get("id", "")) == action_id:
			selected = option
			break
	if selected.is_empty():
		return false
	var duration := float(selected.get("duration", 0.0))
	controller.player._execute_action(target, selected)
	if duration > 0.0:
		_advance_clock(controller, duration)
		if finish:
			controller.player._tick_timed_action(duration + 0.001)
	return true


func _advance_clock(controller, seconds: float) -> void:
	if seconds <= 0.0:
		return
	controller._process(seconds)


func _worst_dangerous_room(controller) -> String:
	var selected := ""
	var worst_seconds := -INF
	for room_id in controller.floor.get_guest_room_ids():
		if room_id == controller.current_previous_room_id:
			continue
		var truth: Dictionary = controller.state.find_room(room_id)
		if String(truth.get("assignment", "")) != RunState.ASSIGNMENT_RENTED:
			continue
		# An inside tenant would correctly catch the player during daytime cabinet
		# preparation.  The pressure route targets an away tenant who will return.
		if String(truth.get("presence", "")) != RunState.PRESENCE_AWAY:
			continue
		var solution: Dictionary = controller.theoretical_night_solution(room_id)
		if float(solution.get("fast_seconds", -INF)) > worst_seconds:
			worst_seconds = float(solution.get("fast_seconds", -INF))
			selected = room_id
	return selected


func _force_returning_tenant(controller, room_id: String) -> void:
	var rooms: Array = controller.state.current_manifest.get("guest_rooms", [])
	for index in range(rooms.size()):
		var room: Dictionary = rooms[index]
		if String(room.get("room_id", "")) != room_id:
			continue
		room["returns_tonight"] = true
		rooms[index] = room
		controller.state.current_manifest["guest_rooms"] = rooms
		return


func _find_interactable(floor, kind: String, room_id: String):
	for node in floor.get_tree().get_nodes_in_group("interactable"):
		if not floor.is_ancestor_of(node) or String(node.kind) != kind:
			continue
		if String(node.data.get("room_id", "")) == room_id:
			return node
	return null


func _record_failure(seed_value: int, day: int) -> Dictionary:
	return {"ok": false, "seed": seed_value, "day": day}


func _fail(seed_value: int, day: int, detail: String) -> void:
	failures.append("seed=%d day=%d %s" % [seed_value, day, detail])


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame
