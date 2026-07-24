class_name HotelRunController
extends Node

const RunState = preload("res://game_state.gd")
const FloorScript = preload("res://hotel.gd")
const NPCScript = preload("res://hotel_npc.gd")
const MAX_HEAVY_DISPOSAL_DISTANCE := 70.0 # 35 s at the exhausted 2 m/s speed.
const SFX_KNOCK := "res://assets/audio/kenney/impactWood_heavy_002.ogg"
const SFX_LOCKPICK := "res://assets/audio/kenney/impactMetal_light_003.ogg"
const SFX_PRYBAR := "res://assets/audio/kenney/impactMetal_heavy_003.ogg"
const KNOCK_CHASE_SECONDS := 14.0

var game_root: Node = null
var floor_host: Node3D = null
var player: CharacterBody3D = null
var hud: HotelHUD = null
var state: HotelRunState
var floor: HotelFloor = null

var selected_slot := 0
var suitcase_node: HotelInteractable = null
var carried_world_node: HotelInteractable = null
var guard_nodes: Array[HotelNPC] = []
var cleaner_node: HotelNPC = null
var tenant_node: HotelNPC = null

var previous_guest_ordinal := -1
var previous_room_number := ""
var current_previous_room_id := ""
var selected_room_id := ""
var _last_player_room_id := ""
var _room_intrusion_latch := ""

var _transitioning := false
var _run_ended := false
var _capture_sequence_active := false
var _tenant_spawned := false
var _tenant_defeated := false
var _corpse_disposed := false
var _stain_cleaned := false
var _corpse_node: HotelInteractable = null
var _stain_node: HotelInteractable = null
var _last_phase := ""

var _lights_disabled_time := 0.0
var _lights_disabled_wing := ""
var _staff_access_time := 0.0
var _staff_access_wing := ""
var _original_light_energy: Dictionary = {}
var _item_origin_anchors: Dictionary = {}
var _knock_chase_time := 0.0
var _knock_chase_room_id := ""


func configure(p_game_root: Node, p_floor_host: Node3D, p_player: CharacterBody3D, p_hud: HotelHUD) -> void:
	game_root = p_game_root
	floor_host = p_floor_host
	player = p_player
	hud = p_hud
	player.configure_runtime(self, hud)


func _ready() -> void:
	set_process(true)


func start_new_run(run_seed := 0) -> void:
	_cleanup_floor()
	state = RunState.new(run_seed)
	previous_guest_ordinal = -1
	previous_room_number = ""
	current_previous_room_id = ""
	selected_room_id = ""
	_transitioning = false
	_run_ended = false
	_capture_sequence_active = false
	_knock_chase_time = 0.0
	_knock_chase_room_id = ""
	_last_phase = ""
	if player != null:
		player.set_process(true)
		player.set_physics_process(true)
	_item_origin_anchors = {}
	if hud != null:
		hud.hide_end()
	load_day(1)


func load_day(day: int) -> void:
	if floor_host == null or player == null:
		return
	_transitioning = true
	player.reset_transient_floor_state()
	_lights_disabled_time = 0.0
	_lights_disabled_wing = ""
	_original_light_energy.clear()
	_staff_access_time = 0.0
	_staff_access_wing = ""
	_cleanup_floor()
	state.begin_day(day)
	var layout_seed := _derive_layout_seed(state.run_seed, day)
	var new_floor := FloorScript.new() as HotelFloor
	new_floor.name = "Floor_Day_%d" % day
	new_floor.configure_managed(self, day, layout_seed)
	floor = new_floor
	floor_host.add_child(new_floor)


func _derive_layout_seed(run_seed: int, day: int) -> int:
	var value := int((run_seed ^ (day * 104729) ^ 0x6A09E667) & 0x7FFFFFFF)
	return value if value > 0 else day * 7919 + 17


func build_day_manifest(descriptors: Array, _map_seed: int) -> Dictionary:
	var guest_descriptors: Array[Dictionary] = []
	var function_descriptors: Array[Dictionary] = []
	for descriptor_value in descriptors:
		var descriptor: Dictionary = descriptor_value
		if String(descriptor.get("room_type", "")) == "guest":
			guest_descriptors.append(descriptor)
		else:
			function_descriptors.append(descriptor)
	guest_descriptors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.room_id) < String(b.room_id)
	)
	var raw: Dictionary = state.generate_day_manifest(state.day_index, guest_descriptors.size())
	_ensure_day_two_confirmable_room(raw, guest_descriptors)
	var room_states: Dictionary = {}
	var mapped_guests: Array = []
	for index in range(guest_descriptors.size()):
		var descriptor: Dictionary = guest_descriptors[index]
		var truth: Dictionary = raw.guest_rooms[index].duplicate(true)
		truth["room_id"] = String(descriptor.room_id)
		truth["room_number"] = String(descriptor.display_number)
		truth["wing"] = String(descriptor.wing)
		truth["room_type"] = "guest"
		room_states[truth.room_id] = truth.duplicate(true)
		mapped_guests.append(truth)

	var mapped_functions: Array = []
	for descriptor in function_descriptors:
		var function_type := String(descriptor.room_type)
		var state_type := "security_archive" if function_type == "security" else function_type
		var function_state := {
			"room_id": String(descriptor.room_id),
			"room_number": String(descriptor.display_number),
			"room_type": function_type,
			"state_room_type": state_type,
			"locked": true,
			"is_guest_room": false,
		}
		room_states[function_state.room_id] = function_state.duplicate(true)
		mapped_functions.append(function_state)

	var preferred_disposal_ids: Array[String] = []
	for disposal_value in raw.disposal_points:
		var disposal: Dictionary = disposal_value.duplicate(true)
		var target_type := String(disposal.room_type)
		if target_type == "security_archive":
			target_type = "security"
		var mapped_id := ""
		for function_state in mapped_functions:
			if String(function_state.room_type) == target_type:
				mapped_id = String(function_state.room_id)
				break
		if not mapped_id.is_empty():
			preferred_disposal_ids.append(mapped_id)
	var disposal_room_ids := _select_logistic_disposals(mapped_functions, preferred_disposal_ids)
	var mapped_disposals: Array = []
	for mapped_id in disposal_room_ids:
		var mapped_type := ""
		for function_state in mapped_functions:
			if String(function_state.room_id) == mapped_id:
				mapped_type = String(function_state.room_type)
				break
		mapped_disposals.append({
			"point_id": "%s-disposal" % mapped_id,
			"room_id": mapped_id,
			"room_type": mapped_type,
			"discovered": false,
		})

	var mapped_items: Array = []
	for item_value in raw.item_spawns:
		var spawn: Dictionary = item_value.duplicate(true)
		var zone := String(spawn.get("zone_type", "public"))
		if zone == "security_archive":
			zone = "security"
		spawn["zone"] = zone
		mapped_items.append(spawn)

	raw["guest_rooms"] = mapped_guests
	raw["functional_rooms"] = mapped_functions
	raw["disposal_points"] = mapped_disposals
	raw["item_spawns"] = mapped_items
	state.current_manifest = raw.duplicate(true)
	return {
		"day_index": state.day_index,
		"rooms": room_states,
		"guest_rooms": mapped_guests,
		"functional_rooms": mapped_functions,
		"disposal_points": mapped_disposals,
		"disposal_room_ids": disposal_room_ids,
		"item_spawns": mapped_items,
		"validation": raw.get("validation", {}),
	}


func _ensure_day_two_confirmable_room(raw: Dictionary, guest_descriptors: Array[Dictionary]) -> void:
	if state.day_index != 2:
		return
	var truths: Array = raw.get("guest_rooms", [])
	if truths.size() < 2:
		return
	var previous_index := -1
	if not previous_room_number.is_empty():
		for index in range(guest_descriptors.size()):
			if String(guest_descriptors[index].get("display_number", "")) == previous_room_number:
				previous_index = index
				break
	if previous_index < 0 and not previous_room_number.is_empty():
		var previous_wing := previous_room_number.get_slice("-", 0)
		var same_wing_indices: Array[int] = []
		for index in range(guest_descriptors.size()):
			if String(guest_descriptors[index].get("wing", "")) == previous_wing:
				same_wing_indices.append(index)
		if not same_wing_indices.is_empty():
			previous_index = same_wing_indices[posmod(previous_guest_ordinal, same_wing_indices.size())]
	if previous_index < 0:
		previous_index = clampi(previous_guest_ordinal, 0, truths.size() - 1)
	for index in range(truths.size()):
		if index != previous_index and _truth_has_two_vacant_votes(truths[index]):
			return
	# The only guaranteed room landed on the ineligible wake-up room.  Swap its
	# complete immutable truth packet with another stable descriptor; counts and
	# evidence safety remain unchanged, but a new room is now confirmable.
	if _truth_has_two_vacant_votes(truths[previous_index]):
		var target_index := 0 if previous_index != 0 else 1
		var temporary: Variant = truths[previous_index]
		truths[previous_index] = truths[target_index]
		truths[target_index] = temporary
		raw["guest_rooms"] = truths
		raw["validation"] = state.validate_manifest(raw)


func _truth_has_two_vacant_votes(room_value: Variant) -> bool:
	if not (room_value is Dictionary) or String(room_value.get("assignment", "")) != RunState.ASSIGNMENT_VACANT:
		return false
	var evidence: Dictionary = room_value.get("evidence", {})
	var votes := 0
	for source in RunState.EVIDENCE_SOURCES:
		if String(evidence.get(source, "")) == RunState.VOTE_VACANT:
			votes += 1
	return votes >= 2


func _set_manifest_room_number(room_id: String, room_number: String) -> void:
	var guests: Array = state.current_manifest.get("guest_rooms", [])
	for index in range(guests.size()):
		var truth: Dictionary = guests[index]
		if String(truth.get("room_id", "")) == room_id:
			truth["room_number"] = room_number
			guests[index] = truth
			break
	state.current_manifest["guest_rooms"] = guests
	if floor != null:
		floor.set_room_runtime_value(room_id, "room_number", room_number)


func _select_logistic_disposals(functions: Array, preferred_ids: Array[String]) -> Array[String]:
	var eligible: Array[String] = []
	for function_value in functions:
		var function_state: Dictionary = function_value
		if String(function_state.get("room_type", "")) in ["storage", "laundry", "service_elevator"]:
			eligible.append(String(function_state.room_id))
	var preferred: Array[String] = []
	for room_id in preferred_ids:
		if eligible.has(room_id) and not preferred.has(room_id):
			preferred.append(room_id)
	if floor == null or not is_instance_valid(floor) or not floor.has_method("max_guest_distance_to_rooms"):
		return preferred if not preferred.is_empty() else eligible.slice(0, mini(2, eligible.size()))
	if not preferred.is_empty() and preferred.size() <= 2:
		if floor.max_guest_distance_to_rooms(preferred) <= MAX_HEAVY_DISPOSAL_DISTANCE:
			return preferred
	var best: Array[String] = []
	var best_distance := INF
	var best_overlap := -1
	for first in range(eligible.size()):
		for second in range(first + 1, eligible.size()):
			var candidate: Array[String] = [eligible[first], eligible[second]]
			var distance: float = floor.max_guest_distance_to_rooms(candidate)
			var overlap := int(preferred.has(candidate[0])) + int(preferred.has(candidate[1]))
			if distance < best_distance - 0.001 or (is_equal_approx(distance, best_distance) and overlap > best_overlap):
				best = candidate
				best_distance = distance
				best_overlap = overlap
	if not best.is_empty():
		return best
	return eligible.slice(0, mini(1, eligible.size()))


## Conservative complete-night estimate used by generation QA and the five-run
## driver.  It includes the five-second lead, the tenant's real corridor-to-room
## path, fast wrap/clean actions, exhausted two-hand carrying, the disposal
## action, and eight seconds of human-control/door/action-wheel allowance.
func theoretical_night_solution(room_id: String) -> Dictionary:
	if floor == null or not is_instance_valid(floor):
		return {"ok": false, "reason": "floor_missing"}
	var descriptor := floor.get_room_descriptor(room_id)
	if descriptor.is_empty() or String(descriptor.get("room_type", "")) != "guest":
		return {"ok": false, "reason": "invalid_guest_room", "room_id": room_id}
	var disposal_ids: Array = state.current_manifest.get("disposal_points", []).map(
		func(point_value: Variant) -> String:
			return String((point_value as Dictionary).get("room_id", ""))
	)
	var nearest_disposal_id := ""
	var heavy_distance := INF
	for disposal_id_value in disposal_ids:
		var disposal_id := String(disposal_id_value)
		var disposal := floor.get_room_descriptor(disposal_id)
		if disposal.is_empty():
			continue
		var distance: float = floor.path_distance_world(descriptor.center, disposal.center)
		if distance < heavy_distance:
			heavy_distance = distance
			nearest_disposal_id = disposal_id
	var corridor: Vector2i = descriptor.get("corridor_tile", Vector2i.ZERO)
	var tenant_start := floor.cell_pos(corridor.x, corridor.y) + Vector3(0.0, 0.08, 0.0)
	var tenant_distance: float = floor.path_distance_world(tenant_start, descriptor.center)
	var support_ready := _manifest_has_spawn_item("ratchet_strap") and _manifest_has_spawn_item("industrial_cleaner")
	if nearest_disposal_id.is_empty() or is_inf(heavy_distance) or is_inf(tenant_distance):
		return {"ok": false, "reason": "route_missing", "room_id": room_id}
	var fast_seconds := (
		RunState.NIGHT_LEAD_SECONDS
		+ tenant_distance / RunState.TENANT_CHASE_SPEED
		+ RunState.CORPSE_WRAP_FAST_SECONDS
		+ RunState.STAIN_CLEAN_FAST_SECONDS
		+ heavy_distance / RunState.EXHAUSTED_HEAVY_SPEED
		+ RunState.BODY_DISPOSE_SECONDS
		+ RunState.THEORY_CONTROL_BUFFER_SECONDS
	)
	var fallback_seconds := (
		RunState.NIGHT_LEAD_SECONDS
		+ tenant_distance / RunState.TENANT_CHASE_SPEED
		+ RunState.CORPSE_WRAP_SECONDS
		+ RunState.STAIN_CLEAN_SECONDS
		+ heavy_distance / RunState.EXHAUSTED_HEAVY_SPEED
		+ RunState.BODY_DISPOSE_SECONDS
	)
	return {
		"ok": support_ready and fast_seconds <= RunState.NIGHT_THEORY_MAX_SECONDS + 0.001,
		"room_id": room_id,
		"disposal_room_id": nearest_disposal_id,
		"support_ready": support_ready,
		"tenant_distance": tenant_distance,
		"heavy_distance": heavy_distance,
		"fast_seconds": fast_seconds,
		"fallback_seconds": fallback_seconds,
		"remaining_seconds": RunState.NIGHT_SECONDS - fast_seconds,
		"remaining_ratio": (RunState.NIGHT_SECONDS - fast_seconds) / RunState.NIGHT_SECONDS,
	}


func worst_theoretical_night_solution() -> Dictionary:
	var worst: Dictionary = {"ok": false, "fast_seconds": -INF, "reason": "no_guest_rooms"}
	if floor == null or not is_instance_valid(floor):
		return worst
	for room_id in floor.get_guest_room_ids():
		var solution := theoretical_night_solution(room_id)
		if float(solution.get("fast_seconds", -INF)) > float(worst.get("fast_seconds", -INF)):
			worst = solution
	return worst


func _manifest_has_spawn_item(item_id: String) -> bool:
	for spawn_value in state.current_manifest.get("item_spawns", []):
		if String((spawn_value as Dictionary).get("item_id", "")) == item_id:
			return true
	return false


func on_floor_ready(ready_floor: HotelFloor) -> void:
	if ready_floor != floor:
		return
	guard_nodes = []
	cleaner_node = null
	tenant_node = null
	suitcase_node = null
	carried_world_node = null
	_tenant_spawned = false
	_knock_chase_time = 0.0
	_knock_chase_room_id = ""
	_tenant_defeated = false
	_corpse_disposed = false
	_stain_cleaned = false
	_corpse_node = null
	_stain_node = null
	selected_room_id = ""
	_room_intrusion_latch = ""
	_last_player_room_id = ""

	var guest_ids := floor.get_guest_room_ids()
	var spawn_position := floor.get_lobby_spawn_position()
	var spawn_yaw := 0.0
	current_previous_room_id = ""
	if state.day_index == 2 and not guest_ids.is_empty():
		if not previous_room_number.is_empty():
			for candidate_id in guest_ids:
				var candidate := floor.get_room_descriptor(candidate_id)
				if String(candidate.get("display_number", "")) == previous_room_number:
					current_previous_room_id = candidate_id
					break
		if current_previous_room_id.is_empty() and not previous_room_number.is_empty():
			var previous_wing := previous_room_number.get_slice("-", 0)
			var same_wing: Array[String] = []
			for candidate_id in guest_ids:
				if String(floor.get_room_descriptor(candidate_id).get("wing", "")) == previous_wing:
					same_wing.append(candidate_id)
			if not same_wing.is_empty():
				current_previous_room_id = same_wing[posmod(previous_guest_ordinal, same_wing.size())]
		if current_previous_room_id.is_empty():
			var ordinal := clampi(previous_guest_ordinal, 0, guest_ids.size() - 1)
			if ordinal < 0:
				ordinal = 0
			current_previous_room_id = guest_ids[ordinal]
		if not previous_room_number.is_empty() and String(floor.get_room_descriptor(current_previous_room_id).get("display_number", "")) != previous_room_number:
			floor.set_room_display_number(current_previous_room_id, previous_room_number)
			_set_manifest_room_number(current_previous_room_id, previous_room_number)
		floor.set_previous_room(current_previous_room_id)
		floor.set_room_unlocked(current_previous_room_id, true)
		floor.set_room_door_open(current_previous_room_id, false)
		spawn_position = floor.get_room_spawn_position(current_previous_room_id)
		_last_player_room_id = current_previous_room_id
		_room_intrusion_latch = current_previous_room_id

	player.configure_floor(floor, spawn_position, spawn_yaw)
	floor.player = player
	_spawn_day_npcs()
	if state.suitcase_exists:
		var suitcase_position := spawn_position + Vector3(0.75, 0.0, 0.2)
		if state.day_index == 1:
			suitcase_position = floor.get_lobby_spawn_position() + Vector3(1.2, 0.0, 0.5)
		elif not current_previous_room_id.is_empty():
			suitcase_position = floor.get_room_clear_position(current_previous_room_id, 0.62)
		suitcase_node = floor.spawn_suitcase(suitcase_position)
	# Items carried across a rebuilt floor acquire a safe anchor on the new map.
	# Pickups collected later in the day overwrite this with their actual origin.
	_reanchor_persistent_items(spawn_position)
	_transitioning = false
	if hud != null:
		hud.show_help("找房", 2.0)
	_update_hud()


func _process(delta: float) -> void:
	if state == null:
		return
	if _run_ended:
		_update_hud()
		return
	_tick_lighting(delta)
	_staff_access_time = maxf(0.0, _staff_access_time - delta)
	_tick_knock_chase(delta)
	if _transitioning or floor == null or not is_instance_valid(floor):
		return
	var old_phase := state.phase
	var tick_result: Dictionary = state.tick(delta)
	if old_phase == RunState.PHASE_NIGHT_LEAD and state.phase == RunState.PHASE_NIGHT:
		_spawn_returning_tenant()
	_check_day_intrusion()
	if bool(tick_result.expired):
		if state.phase == RunState.PHASE_DAY:
			_on_day_timer_expired()
		elif state.phase == RunState.PHASE_NIGHT:
			_fail_run("夜晚超时", "现场未在天亮前彻底处理。")
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not _run_ended or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_R:
		start_new_run()
		get_viewport().set_input_as_handled()


func _update_hud() -> void:
	if hud == null or state == null:
		return
	var remaining := float(state.timers.get("day", 0.0))
	if state.phase in [RunState.PHASE_NIGHT, RunState.PHASE_NIGHT_LEAD]:
		remaining = float(state.timers.get("night", 0.0))
	hud.set_run_status(state.day_index, state.phase, remaining, state.strikes)
	hud.set_head_start(float(state.timers.get("lead", 0.0)) if state.phase == RunState.PHASE_NIGHT_LEAD else 0.0)
	if player != null:
		player.refresh_notebook_data()
		player.refresh_suitcase_data()


func _spawn_day_npcs() -> void:
	_spawn_npc("guard", floor.get_patrol_points(0), false)
	cleaner_node = _spawn_npc("cleaner", floor.get_patrol_points(4), false)


func _spawn_npc(
	kind: String,
	patrol: PackedVector3Array,
	night_mode: bool,
	pursuit_role: StringName = HotelNPC.ROLE_CHASER
	) -> HotelNPC:
	var npc := NPCScript.new() as HotelNPC
	npc.name = "%s_%d" % [kind.capitalize(), floor.get_child_count()]
	if patrol.size() > 0:
		npc.position = patrol[0]
	floor.add_child(npc)
	npc.add_to_group("hotel_npc")
	npc.configure(floor, player, kind, patrol, night_mode, pursuit_role)
	if kind == "guard":
		guard_nodes.append(npc)
	elif kind == "tenant":
		tenant_node = npc
		npc.add_to_group("hotel_tenant")
	return npc


func _spawn_returning_tenant() -> void:
	if _tenant_spawned or selected_room_id.is_empty():
		return
	_tenant_spawned = true
	var descriptor := floor.get_room_descriptor(selected_room_id)
	var patrol := PackedVector3Array()
	if not descriptor.is_empty():
		var corridor: Vector2i = descriptor.corridor_tile
		patrol.append(floor.cell_pos(corridor.x, corridor.y) + Vector3(0.0, 0.08, 0.0))
	else:
		patrol.append(floor.get_lobby_spawn_position())
	tenant_node = _spawn_npc("tenant", patrol, true)
	if hud != null:
		hud.show_help("租客回来了。把他引入你准备的机关。", 3.0)


func _begin_night_crisis(room_id: String) -> void:
	_end_knock_chase(false)
	selected_room_id = room_id
	state.suitcase_inventory = _empty_slots(4)
	state.begin_night(true)
	_tenant_spawned = false
	_tenant_defeated = false
	_corpse_disposed = false
	_stain_cleaned = false
	if cleaner_node != null and is_instance_valid(cleaner_node):
		cleaner_node.queue_free()
	cleaner_node = null
	for guard in guard_nodes:
		if is_instance_valid(guard):
			guard.set_night_mode(true)
	_spawn_npc("guard", floor.get_patrol_points(7), true, HotelNPC.ROLE_AMBUSHER)
	var descriptor := floor.get_room_descriptor(room_id)
	if not descriptor.is_empty():
		var corridor: Vector2i = descriptor.corridor_tile
		var ejection := floor.cell_pos(corridor.x, corridor.y) + Vector3(0.0, 0.08, 0.0)
		player.global_position = ejection
		player.safe_pos = ejection
		player.velocity = Vector3.ZERO
	if hud != null:
		hud.show_help("房间有租客返房：箱内物品已丢失。5秒后开始追逐。", 4.5)


func _on_day_timer_expired() -> void:
	var room_id := floor.get_room_id_at_world(player.global_position)
	if room_id.is_empty():
		_fail_run("无处过夜", "倒计时结束时你没有待在一间有效的新客房里。")
		return
	var descriptor := floor.get_room_descriptor(room_id)
	if descriptor.is_empty() or String(descriptor.get("room_type", "")) != "guest" or room_id == current_previous_room_id:
		_fail_run("无处过夜", "倒计时结束时所在位置不是一间可用的新客房。")
		return
	_settle_room(room_id, false)


func _settle_room(room_id: String, barricaded: bool) -> void:
	if state.phase != RunState.PHASE_DAY or _transitioning:
		return
	var descriptor := floor.get_room_descriptor(room_id)
	if descriptor.is_empty() or String(descriptor.get("room_type", "")) != "guest":
		_show_message("这里只是功能房，不能住宿。")
		return
	if room_id == current_previous_room_id:
		_show_message("昨夜房今天不能再次入住。")
		return
	if floor.get_room_id_at_world(player.global_position) != room_id:
		_show_message("必须在房间内的床边提交住宿。")
		return
	if barricaded and not _consume_carry_item("ratchet_strap"):
		_show_message("随身栏里没有棘轮绑带。")
		return

	selected_room_id = room_id
	_previous_room_from_selection(room_id)
	_resolve_suitcase_at_settlement(room_id)
	var truth: Dictionary = state.find_room(room_id)
	if barricaded:
		_complete_day("绑带牢牢堵住了门。")
	elif String(truth.get("assignment", "")) == RunState.ASSIGNMENT_VACANT:
		_complete_day("房间确实空置。你安全熬过了这一夜。")
	elif String(truth.get("presence", "")) == RunState.PRESENCE_AWAY and not bool(truth.get("returns_tonight", true)):
		_complete_day("这是出租房，但租客整夜没有回来。")
	else:
		_begin_night_crisis(room_id)


func _previous_room_from_selection(room_id: String) -> void:
	var guest_ids := floor.get_guest_room_ids()
	previous_guest_ordinal = guest_ids.find(room_id)
	var truth := state.find_room(room_id)
	previous_room_number = String(truth.get("room_number", room_id))


func _resolve_suitcase_at_settlement(room_id: String) -> void:
	if not state.suitcase_exists:
		return
	var suitcase_room := ""
	if state.suitcase_carried:
		suitcase_room = floor.get_room_id_at_world(player.global_position)
	elif suitcase_node != null and is_instance_valid(suitcase_node):
		suitcase_room = floor.get_room_id_at_world(suitcase_node.global_position)
	if suitcase_room != room_id:
		state.suitcase_exists = false
		state.suitcase_inventory = _empty_slots(4)
		if suitcase_node != null and is_instance_valid(suitcase_node):
			suitcase_node.queue_free()
		suitcase_node = null


func _complete_day(message: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	player.reset_transient_floor_state()
	# World nodes are rebuilt between days.  Release suitcase slot reservations
	# so the preserved suitcase respawns as a physical object on the new floor.
	if state.suitcase_carried:
		state.set_suitcase_carried(false)
	carried_world_node = null
	_show_message(message)
	var result: Dictionary = state.complete_current_day()
	if bool(result.complete):
		_run_ended = true
		_transitioning = false
		if hud != null:
			hud.show_end("原型完成", "你在第二天结束前找到了落脚处并保住了行动能力。\nDay 3–7 与正式目标将在下一阶段继续设计。")
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	call_deferred("load_day", int(result.day_index))


func _fail_run(title: String, detail: String) -> void:
	if _run_ended:
		return
	_run_ended = true
	_transitioning = false
	state.phase = RunState.PHASE_GAME_OVER
	if player != null:
		player.cancel_timed_action("")
	if hud != null:
		hud.show_end(title, "%s\n\n按 R 从 Day 1 重新开始。" % detail)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func perform_floor_action(_source_floor: HotelFloor, source: HotelInteractable, action_id: String, _player_node: Node) -> void:
	if _run_ended or source == null or not is_instance_valid(source):
		return
	var room_id := String(source.data.get("room_id", ""))
	match action_id:
		"observe":
			_record_room_evidence(room_id, "doorstep", "门口观察")
		"listen":
			_record_room_evidence(room_id, "listen", "倾听")
		"knock":
			_handle_knock(room_id)
		"unlock_lockpick":
			if _consume_carry_item("lockpick"):
				floor.set_room_unlocked(room_id, true)
				_show_message("锁舌安静地弹开了。")
		"unlock_prybar":
			if _consume_carry_item("pry_bar"):
				floor.set_room_unlocked(room_id, true)
				cleaner_report(source.global_position)
				_show_message("门被撬开，声音传遍了这一翼。")
		"unlock_pass":
			if _consume_carry_item("staff_card"):
				floor.set_room_unlocked(room_id, true)
				_staff_access_time = 12.0
				_staff_access_wing = String(floor.get_room_descriptor(room_id).get("wing", _player_wing()))
				_show_message("工作卡暂时放行了这扇门。")
		"unlock_electrician":
			if _consume_carry_item("electrician_kit"):
				floor.set_room_unlocked(room_id, true)
				_show_message("电子门锁重新通电。")
		"settle":
			_settle_room(room_id, false)
		"barricade_settle":
			_settle_room(room_id, true)
		"arm_cabinet":
			if not is_daytime():
				_show_message("坠柜必须在白天预先准备。")
				return
			floor.set_room_runtime_value(room_id, "cabinet_armed", true)
			_show_message("坠柜机关已经预置好。")
		"arm_cabinet_pry":
			if not is_daytime():
				_show_message("坠柜必须在白天预先准备。")
				return
			if _consume_carry_item("pry_bar"):
				floor.set_room_runtime_value(room_id, "cabinet_armed", true)
				_show_message("扁撬让坠柜快速进入待发状态。")
		"read_records":
			_read_registration_records()
		"search_facility":
			_search_facility(room_id)
		"pickup_item":
			_pickup_item(source)
		"pickup_suitcase":
			_pickup_suitcase(source)
		"open_suitcase":
			if can_open_suitcase():
				player.suitcase_open = true
				player.refresh_suitcase_data()
				_show_message("箱内整理：1–4放入，Shift+1–4取出。")
			else:
				_show_message("先把旅行箱放下，并站在旁边。")
		"wrap_corpse":
			_wrap_corpse(source, false)
		"wrap_corpse_strap":
			_wrap_corpse(source, true)
		"carry_corpse":
			_pickup_body(source)
		"dispose_body":
			_dispose_body(room_id)
		"clean_stain":
			_clean_stain(source, false)
		"clean_stain_spray":
			_clean_stain(source, true)


func on_player_action_started(action_id: String, target: Node) -> void:
	if not (target is Node3D) or floor == null or not is_instance_valid(floor):
		return
	var sound_position := (target as Node3D).global_position + Vector3(0.0, 1.1, 0.0)
	match action_id:
		"knock":
			_schedule_world_sfx(SFX_KNOCK, sound_position, -3.5, 0.82, 0.0)
			_schedule_world_sfx(SFX_KNOCK, sound_position, -4.5, 0.88, 0.17)
			_schedule_world_sfx(SFX_KNOCK, sound_position, -4.0, 0.78, 0.37)
		"unlock_lockpick":
			_schedule_world_sfx(SFX_LOCKPICK, sound_position, -9.0, 1.12, 0.0)
			_schedule_world_sfx(SFX_LOCKPICK, sound_position, -11.0, 1.28, 0.34)
		"unlock_prybar":
			_schedule_world_sfx(SFX_PRYBAR, sound_position, -1.5, 0.84, 0.0)


func _schedule_world_sfx(path: String, world_position: Vector3, volume_db: float, pitch: float, delay: float) -> void:
	if delay <= 0.0:
		_play_world_sfx(path, world_position, volume_db, pitch)
		return
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		_play_world_sfx(path, world_position, volume_db, pitch)
	)


func _play_world_sfx(path: String, world_position: Vector3, volume_db: float, pitch: float) -> void:
	if floor == null or not is_instance_valid(floor):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var sfx := AudioStreamPlayer3D.new()
	sfx.name = "WorldSFX"
	sfx.stream = stream
	sfx.volume_db = volume_db
	sfx.pitch_scale = pitch
	sfx.max_distance = 18.0
	sfx.unit_size = 3.0
	sfx.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	floor.add_child(sfx)
	sfx.global_position = world_position
	sfx.finished.connect(sfx.queue_free)
	sfx.play()


func _record_room_evidence(room_id: String, source: String, label: String) -> Dictionary:
	var result: Dictionary = state.record_evidence(room_id, source)
	if not bool(result.get("ok", false)):
		_show_message("无法记录这条线索。")
		return result
	if floor != null:
		floor.set_room_runtime_value(room_id, "registered", true)
	if floor != null and floor.has_method("set_room_plate_state"):
		floor.set_room_plate_state(room_id, "none")
	if player != null:
		player.refresh_notebook_data()
	if not label.is_empty():
		_show_message("%s完成，%s 已自动写入手记。" % [label, _room_number(room_id)])
	return result


func _handle_knock(room_id: String) -> void:
	var result := _record_room_evidence(room_id, "knock", "")
	if not bool(result.get("ok", false)):
		return
	var room := state.find_room(room_id)
	if String(room.get("presence", "")) == RunState.PRESENCE_INSIDE:
		_start_knock_chase(room_id)
	else:
		_show_message("%s 无人应门；结果已自动写入手记。" % _room_number(room_id))


func _start_knock_chase(room_id: String) -> void:
	if not is_daytime() or floor == null:
		return
	if _knock_chase_time > 0.0:
		_knock_chase_time = maxf(_knock_chase_time, KNOCK_CHASE_SECONDS)
		_show_message("有人应门；追你的人还没甩掉！")
		return
	var descriptor := floor.get_room_descriptor(room_id)
	if descriptor.is_empty():
		return
	floor.set_room_door_open(room_id, true)
	var start := Vector3(descriptor.get("center", player.global_position))
	tenant_node = _spawn_npc("tenant", PackedVector3Array([start]), false)
	_knock_chase_time = KNOCK_CHASE_SECONDS
	_knock_chase_room_id = room_id
	if hud != null:
		hud.show_help("有人冲出来了——撑过14秒，别被抓住！", 3.5)


func _tick_knock_chase(delta: float) -> void:
	if _knock_chase_time <= 0.0:
		return
	if state == null or state.phase != RunState.PHASE_DAY:
		_end_knock_chase(false)
		return
	_knock_chase_time = maxf(0.0, _knock_chase_time - delta)
	if _knock_chase_time <= 0.0:
		_end_knock_chase(true)


func _end_knock_chase(escaped: bool) -> void:
	if tenant_node != null and is_instance_valid(tenant_node):
		tenant_node.queue_free()
	tenant_node = null
	_knock_chase_time = 0.0
	_knock_chase_room_id = ""
	if escaped:
		_show_message("你甩掉了租客。敲门结果已经留在手记里。")


func _read_registration_records() -> void:
	var count := 0
	for room_id_value in state.notebook.keys():
		var room_id := String(room_id_value)
		var result: Dictionary = state.record_evidence(room_id, "registration")
		if bool(result.get("ok", false)) and not bool(result.get("already_checked", false)):
			count += 1
		if floor != null and floor.has_method("set_room_plate_state"):
			floor.set_room_plate_state(room_id, "none")
	if player != null:
		player.refresh_notebook_data()
	_show_message("登记簿残缺不全；已更新 %d 个现有房间条目。" % count)


func _search_facility(room_id: String) -> void:
	var active := false
	for point_value in state.current_manifest.get("disposal_points", []):
		var point: Dictionary = point_value
		if String(point.get("room_id", "")) == room_id:
			point["discovered"] = true
			active = true
	if active:
		_show_message("你发现了一个可用的尸体投放点。记住位置，它不会写进笔记。")
	else:
		_show_message("这里没有可用的投放口。")


func _pickup_item(source: HotelInteractable) -> void:
	var item_id := String(source.data.get("item_id", ""))
	var result: Dictionary = state.add_item(RunState.CONTAINER_CARRY, item_id)
	if not bool(result.get("ok", false)):
		_show_message("随身栏放不下这件物品。")
		return
	var origin_value: Variant = source.data.get("origin_anchor", source.global_position)
	_item_origin_anchors[int(result.get("uid", 0))] = origin_value if origin_value is Vector3 else source.global_position
	_show_message("拾取：%s" % get_item_display_name(item_id))
	source.queue_free()


func _pickup_suitcase(source: HotelInteractable) -> void:
	var result: Dictionary = state.set_suitcase_carried(true)
	if not bool(result.get("ok", false)):
		_show_message("搬箱子需要空出随身栏前两格。")
		return
	suitcase_node = source
	carried_world_node = source
	source.visible = false
	source.set_enabled(false)
	_show_message("旅行箱占用双手。按 G 放下。")


func _wrap_corpse(source: HotelInteractable, with_strap: bool) -> void:
	if with_strap and not _consume_carry_item("ratchet_strap"):
		_show_message("没有棘轮绑带。")
		return
	var position := source.global_position
	source.queue_free()
	_corpse_node = floor.spawn_wrapped_corpse(position)
	_show_message("尸体已裹好，现在需要双手搬运。")


func _pickup_body(source: HotelInteractable) -> void:
	var result: Dictionary = state.set_body_carried(true)
	if not bool(result.get("ok", false)):
		_show_message("搬尸体需要空出随身栏前两格。")
		return
	carried_world_node = source
	source.visible = false
	source.set_enabled(false)
	_show_message("正在搬运尸体。按 G 可放下。")


func _dispose_body(room_id: String) -> void:
	if state.carried_world_object != "body":
		_show_message("你没有搬着尸体。")
		return
	var valid := false
	for point_value in state.current_manifest.get("disposal_points", []):
		if String((point_value as Dictionary).get("room_id", "")) == room_id:
			valid = true
			break
	if not valid:
		_show_message("这个投放口今天没有启用。")
		return
	state.set_body_carried(false)
	if carried_world_node != null and is_instance_valid(carried_world_node):
		carried_world_node.queue_free()
	carried_world_node = null
	_corpse_disposed = true
	_show_message("尸体已投入。还要确认血迹已经清除。")
	_check_night_cleanup_complete()


func _clean_stain(source: HotelInteractable, with_cleaner: bool) -> void:
	if with_cleaner and not _consume_carry_item("industrial_cleaner"):
		_show_message("没有工业去污剂。")
		return
	source.queue_free()
	_stain_cleaned = true
	_show_message("血迹已经清除。")
	_check_night_cleanup_complete()


func tenant_killed(tenant: Node3D, world_position: Vector3, _method: String) -> void:
	if _tenant_defeated:
		return
	_tenant_defeated = true
	if tenant != null and is_instance_valid(tenant):
		tenant.queue_free()
	tenant_node = null
	_corpse_node = floor.spawn_corpse(world_position)
	_stain_node = floor.spawn_stain(world_position)
	_show_message("租客已死。裹尸、投放，并清除血迹。")


func _check_night_cleanup_complete() -> void:
	if _tenant_defeated and _corpse_disposed and _stain_cleaned:
		_complete_day("现场已经处理完毕，封锁没有发生。")


func use_selected_item() -> void:
	if state == null or _run_ended:
		return
	var item := state.get_item_at(RunState.CONTAINER_CARRY, selected_slot)
	if not bool(item.get("ok", false)):
		_show_message("所选随身格为空。")
		return
	var item_id := String(item.item_id)
	match item_id:
		"folding_trap":
			if state.phase not in [RunState.PHASE_NIGHT_LEAD, RunState.PHASE_NIGHT]:
				_show_message("致命陷阱只能在夜间危机中部署。")
				return
			if player.is_action_busy():
				return
			var deploy_position: Vector3 = player.get_drop_position()
			player.begin_timed_action(RunState.TRAP_DEPLOY_SECONDS, "部署折叠陷阱", func() -> void:
				var current_slot := _find_carry_item_slot("folding_trap")
				if current_slot < 0 or state.phase not in [RunState.PHASE_NIGHT_LEAD, RunState.PHASE_NIGHT]:
					return
				var removed := state.consume_item(RunState.CONTAINER_CARRY, current_slot)
				if bool(removed.get("ok", false)):
					_item_origin_anchors.erase(int(removed.get("uid", 0)))
					floor.spawn_deployed_trap(deploy_position)
					_show_message("折叠陷阱已部署；把返房租客引过来。")
			, "deploy_trap")
		"instant_camera":
			var pursuer := _nearest_visible_pursuer()
			if pursuer != null:
				pursuer.stun(2.0)
				_consume_carry_item("instant_camera")
				_show_message("闪光让追兵停顿了约2秒。")
			else:
				var target_value: Node = player.current_interact
				if target_value == null or not is_instance_valid(target_value):
					target_value = player.raycast_interactable(12.0)
				var target := target_value as HotelInteractable
				if target == null:
					return
				var room_id := String(target.data.get("room_id", ""))
				if not room_id.is_empty():
					_record_room_evidence(room_id, "doorstep", "拍立得记录")
					_consume_carry_item("instant_camera")
		"inspection_mirror":
			var mirror_target_value: Node = player.current_interact
			if mirror_target_value == null or not is_instance_valid(mirror_target_value):
				mirror_target_value = player.raycast_interactable(6.0)
			if mirror_target_value is HotelInteractable:
				var target := mirror_target_value as HotelInteractable
				var room_id := String(target.data.get("room_id", ""))
				if not room_id.is_empty():
					_record_room_evidence(room_id, "doorstep", "检修镜观察")
					_consume_carry_item("inspection_mirror")
			else:
				var scout := _nearest_npc()
				if scout != null:
					var distance := player.global_position.distance_to(scout.global_position)
					_consume_carry_item("inspection_mirror")
					_show_message("镜中确认：最近的巡逻者约 %.0f 米。" % distance)
		"staff_card":
			if _consume_carry_item("staff_card"):
				_staff_access_time = 12.0
				_staff_access_wing = _player_wing()
				_show_message("工作卡带来约12秒员工身份；保安近身禁区缩小。")
		"alarm_clock":
			_consume_carry_item("alarm_clock")
			var noise_position: Vector3 = player.get_drop_position()
			for guard in guard_nodes:
				if is_instance_valid(guard):
					guard.lure_to(noise_position, 5.0)
			if cleaner_node != null and is_instance_valid(cleaner_node):
				cleaner_node.lure_to(noise_position, 5.0)
			if tenant_node != null and is_instance_valid(tenant_node):
				tenant_node.lure_to(noise_position, 5.0)
			_show_message("闹钟声把附近人员引向了声源。")
		"electrician_kit":
			_consume_carry_item("electrician_kit")
			_disable_lights(20.0, _player_wing())
			_show_message("这一翼的照明与电子设备将关闭约20秒。")
		"industrial_cleaner":
			_consume_carry_item("industrial_cleaner")
			floor.spawn_slippery_zone(player.get_drop_position())
			_show_message("去污剂喷在地面上，形成一次湿滑减速区。")
		"ratchet_strap":
			if not (player.current_interact is HotelInteractable) or (player.current_interact as HotelInteractable).kind != "door":
				_show_message("靠近并对准一扇门，才能使用绑带封门。")
				return
			var target := player.current_interact as HotelInteractable
			_consume_carry_item("ratchet_strap")
			_show_message("最近的门被临时封住10秒。")
			floor.seal_door(target, 10.0)
			get_tree().create_timer(10.0).timeout.connect(func() -> void:
				if is_instance_valid(target):
					target.set_enabled(true)
			)
		_:
			_show_message("这件物品要在对应的门、房间或现场上使用。")


func drop_two_handed(world_position: Vector3) -> void:
	if state == null:
		return
	if state.carried_world_object == "suitcase":
		state.set_suitcase_carried(false)
		if suitcase_node != null and is_instance_valid(suitcase_node):
			suitcase_node.global_position = world_position + Vector3(0.0, 0.38, 0.0)
			suitcase_node.visible = true
			suitcase_node.set_enabled(true)
		carried_world_node = null
		_show_message("旅行箱已放下。靠近后按 I 整理。")
		return
	if state.carried_world_object == "body":
		state.set_body_carried(false)
		if carried_world_node != null and is_instance_valid(carried_world_node):
			carried_world_node.global_position = world_position + Vector3(0.0, 0.28, 0.0)
			carried_world_node.visible = true
			carried_world_node.set_enabled(true)
		carried_world_node = null
		_show_message("尸体已放下。")
		return
	var trap := _find_carry_item_slot("folding_trap")
	if trap >= 0:
		var lookup := state.get_item_at(RunState.CONTAINER_CARRY, trap)
		var uid := int(lookup.get("uid", 0))
		var origin_value: Variant = _item_origin_anchors.get(uid, world_position)
		var removed := state.remove_item(RunState.CONTAINER_CARRY, trap)
		if bool(removed.get("ok", false)):
			floor.spawn_item_pickup("folding_trap", world_position + Vector3(0.0, 0.22, 0.0), "", origin_value)
			_item_origin_anchors.erase(uid)
			_show_message("折叠陷阱已放下；清洁工看见后会送回原处。")
		return
	var lookup := state.get_item_at(RunState.CONTAINER_CARRY, selected_slot)
	if bool(lookup.get("ok", false)) and not bool(lookup.get("reserved", false)):
		var uid := int(lookup.get("uid", 0))
		var item_id := String(lookup.get("item_id", ""))
		var origin_value: Variant = _item_origin_anchors.get(uid, world_position)
		var removed := state.remove_item(RunState.CONTAINER_CARRY, selected_slot)
		if bool(removed.get("ok", false)):
			floor.spawn_item_pickup(item_id, world_position + Vector3(0.0, 0.22, 0.0), "", origin_value)
			_item_origin_anchors.erase(uid)
			_show_message("已放下%s。" % get_item_display_name(item_id))


func use_selected_item_at_slot(slot: int) -> void:
	selected_slot = slot
	use_selected_item()


func move_carry_slot_to_suitcase(slot: int) -> void:
	if not can_open_suitcase():
		_show_message("旅行箱未放下或距离太远。")
		return
	var result := state.move_item(RunState.CONTAINER_CARRY, slot, RunState.CONTAINER_SUITCASE)
	if not bool(result.get("ok", false)):
		_show_message("这件物品无法放入箱中。")


func move_suitcase_slot_to_carry(slot: int) -> void:
	if not can_open_suitcase():
		_show_message("旅行箱未放下或距离太远。")
		return
	var result := state.move_item(RunState.CONTAINER_SUITCASE, slot, RunState.CONTAINER_CARRY)
	if not bool(result.get("ok", false)):
		_show_message("随身栏没有足够空间。")


func can_open_suitcase() -> bool:
	return state != null and state.suitcase_exists and not state.suitcase_carried and suitcase_node != null and is_instance_valid(suitcase_node) and player.global_position.distance_to(suitcase_node.global_position) <= 2.25


func set_selected_slot(slot: int) -> void:
	selected_slot = clampi(slot, 0, 3)


func has_item(item_id: String) -> bool:
	return _find_carry_item_slot(item_id) >= 0


func _find_carry_item_slot(item_id: String) -> int:
	if state == null:
		return -1
	for index in range(state.inventory.size()):
		var cell = state.inventory[index]
		if cell is Dictionary and not bool(cell.get("reserved", false)) and String(cell.get("item_id", "")) == item_id:
			return index
	return -1


func _consume_carry_item(item_id: String) -> bool:
	var slot := _find_carry_item_slot(item_id)
	if slot < 0:
		return false
	var lookup := state.get_item_at(RunState.CONTAINER_CARRY, slot)
	var result := state.consume_item(RunState.CONTAINER_CARRY, slot)
	if bool(result.get("ok", false)):
		_item_origin_anchors.erase(int(lookup.get("uid", 0)))
		return true
	return false


func is_two_handed() -> bool:
	return state != null and state.is_two_handed()


func get_item_display_name(item_id: String) -> String:
	if state == null:
		return item_id
	return String(state.get_item_definition(item_id).get("display_name", item_id))


func get_carry_slots_for_ui() -> Array:
	return _slots_for_ui(state.inventory if state != null else [])


func get_suitcase_slots_for_ui() -> Array:
	return _slots_for_ui(state.suitcase_inventory if state != null else [])


func _slots_for_ui(slots: Array) -> Array:
	var result: Array = []
	for cell in slots:
		if not (cell is Dictionary):
			result.append(null)
			continue
		var item_id := String(cell.get("item_id", ""))
		var ui_cell: Dictionary = cell.duplicate(true)
		ui_cell["display_name"] = "旅行箱" if item_id == "suitcase" else ("尸体" if item_id == "body" else get_item_display_name(item_id))
		ui_cell["slot_cost"] = 2 if item_id in ["suitcase", "body"] else int(state.get_item_definition(item_id).get("slot_cost", 1))
		result.append(ui_cell)
	return result


func get_notebook_for_ui() -> Array:
	var result: Array = []
	if state == null:
		return result
	for room_id in state.notebook.keys():
		var entry := (state.notebook[room_id] as Dictionary).duplicate(true)
		if floor != null and is_instance_valid(floor):
			var descriptor := floor.get_room_descriptor(String(room_id))
			var center: Variant = descriptor.get("center", null)
			if center is Vector3:
				var bounds: Rect2 = floor._map_world_bounds()
				entry["map_position"] = Vector2(
					(center.x - bounds.position.x) / bounds.size.x,
					(center.z - bounds.position.y) / bounds.size.y
				)
		result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("room_number", "")) < String(b.get("room_number", ""))
	)
	return result


func npc_caught(kind: StringName) -> void:
	if _run_ended or state == null or _capture_sequence_active:
		return
	if state.phase == RunState.PHASE_DAY:
		if kind == &"tenant" and _knock_chase_time > 0.0:
			_end_knock_chase(false)
		var result: Dictionary = state.add_daytime_strike()
		var black_room := bool(result.get("black_room", false))
		if black_room:
			_run_ended = true
		else:
			state.apply_daytime_capture_penalty()
		_begin_capture_scare(kind, Callable(self, "_finish_day_capture").bind(black_room))
	else:
		_begin_capture_scare(kind, Callable(self, "_finish_night_capture").bind(kind))


func _begin_capture_scare(kind: StringName, finished: Callable) -> void:
	_capture_sequence_active = true
	if player != null:
		player.cancel_timed_action("")
		player.velocity = Vector3.ZERO
		player.set_process(false)
		player.set_physics_process(false)
	if hud != null:
		hud.capture_scare_finished.connect(finished, CONNECT_ONE_SHOT)
		hud.play_capture_scare(kind)
	else:
		finished.call()


func _finish_day_capture(black_room: bool) -> void:
	_capture_sequence_active = false
	if black_room:
		if hud != null:
			hud.show_end("被关进小黑屋", "第三次被抓。随身与箱内物资已清空，时间跳过两天；当前两日原型到此结束。")
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	if floor != null and is_instance_valid(floor):
		player.global_position = floor.get_lobby_spawn_position()
		player.safe_pos = player.global_position
	player.velocity = Vector3.ZERO
	player.set_process(true)
	player.set_physics_process(true)
	_show_message("被保安送回大厅，扣除15秒。被抓 %d/3" % state.strikes)


func _finish_night_capture(kind: StringName) -> void:
	_capture_sequence_active = false
	if player != null:
		player.set_process(true)
		player.set_physics_process(true)
	_fail_run("夜间被捕", "%s抓住了你。" % ("返房租客" if kind == &"tenant" else "保安"))


func cleaner_report(world_position: Vector3) -> void:
	for guard in guard_nodes:
		if is_instance_valid(guard):
			guard.report_incident(world_position)


func on_loose_item_returned(item: Node3D) -> void:
	if item == suitcase_node:
		_show_message("清洁工把走廊里的旅行箱送回了原处。")


func is_night_active() -> bool:
	return state != null and state.phase in [RunState.PHASE_NIGHT_LEAD, RunState.PHASE_NIGHT]


func is_daytime() -> bool:
	return state != null and state.phase == RunState.PHASE_DAY and not _run_ended


func guard_personal_space(default_distance: float) -> float:
	var access_active := _staff_access_time > 0.0 and not _staff_access_wing.is_empty()
	if access_active and _player_wing() == _staff_access_wing:
		return minf(default_distance, 0.48)
	return default_distance


func is_player_hidden(player_node: Node) -> bool:
	return player_node != null and bool(player_node.get("in_wardrobe"))


func _check_day_intrusion() -> void:
	if state.phase != RunState.PHASE_DAY:
		return
	var room_id := floor.get_room_id_at_world(player.global_position)
	# Day 2 begins inside the room survived the previous night.  That room is a
	# safe wake-up location for the day even though it is not eligible tonight.
	if not current_previous_room_id.is_empty() and room_id == current_previous_room_id:
		_last_player_room_id = room_id
		_room_intrusion_latch = room_id
		return
	if room_id != _last_player_room_id:
		_last_player_room_id = room_id
		_room_intrusion_latch = ""
	if room_id.is_empty() or room_id == _room_intrusion_latch:
		return
	var truth := state.find_room(room_id)
	if not truth.is_empty() and String(truth.get("presence", "")) == RunState.PRESENCE_INSIDE:
		_room_intrusion_latch = room_id
		npc_caught(&"tenant")


func _player_wing() -> String:
	if floor == null or player == null:
		return ""
	var wing := floor.get_wing_at_world(player.global_position)
	if not wing.is_empty():
		return wing
	var forward: Vector3 = -player.global_transform.basis.z
	if absf(forward.x) > absf(forward.z):
		return "E" if forward.x > 0.0 else "W"
	return "S" if forward.z > 0.0 else "N"


func _disable_lights(duration: float, wing := "") -> void:
	_lights_disabled_time = maxf(_lights_disabled_time, duration)
	_lights_disabled_wing = wing
	if floor == null:
		return
	for light_value in floor.lights:
		var omni: OmniLight3D = light_value.omni
		if not wing.is_empty() and floor.get_wing_at_world(omni.global_position) != wing:
			continue
		if not _original_light_energy.has(omni):
			_original_light_energy[omni] = omni.light_energy
		omni.light_energy = 0.03


func _tick_lighting(delta: float) -> void:
	if _lights_disabled_time <= 0.0:
		return
	_lights_disabled_time = maxf(0.0, _lights_disabled_time - delta)
	# HotelFloor's normal flicker pass also runs every frame, so keep the outage
	# authoritative until its timer ends.
	if floor != null and is_instance_valid(floor):
		for light in _original_light_energy.keys():
			if is_instance_valid(light):
				(light as OmniLight3D).light_energy = 0.03
	if _lights_disabled_time <= 0.0:
		for light in _original_light_energy.keys():
			if is_instance_valid(light):
				light.light_energy = float(_original_light_energy[light])
		_original_light_energy.clear()
		_lights_disabled_wing = ""


func _room_number(room_id: String) -> String:
	var room := state.find_room(room_id)
	return String(room.get("room_number", room_id))


func _show_message(message: String) -> void:
	if hud != null:
		hud.show_help(message, 2.8)


func _empty_slots(count: int) -> Array:
	var result: Array = []
	result.resize(count)
	result.fill(null)
	return result


func _nearest_visible_pursuer() -> HotelNPC:
	var nearest: HotelNPC = tenant_node if tenant_node != null and is_instance_valid(tenant_node) else null
	var nearest_distance := INF if nearest == null else player.global_position.distance_squared_to(nearest.global_position)
	for guard in guard_nodes:
		if not is_instance_valid(guard) or not guard.is_chasing():
			continue
		var distance := player.global_position.distance_squared_to(guard.global_position)
		if distance < nearest_distance:
			nearest = guard
			nearest_distance = distance
	if nearest == null or nearest_distance > 64.0:
		return null
	var from: Vector3 = player.camera.global_position
	var to: Vector3 = nearest.global_position + Vector3(0.0, 1.25, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return nearest
	var collider: Variant = hit.get("collider")
	if collider == nearest or (collider is Node and nearest.is_ancestor_of(collider as Node)):
		return nearest
	return null


func _nearest_npc() -> HotelNPC:
	var nearest: HotelNPC = null
	var nearest_distance := INF
	var candidates: Array = guard_nodes.duplicate()
	if cleaner_node != null:
		candidates.append(cleaner_node)
	if tenant_node != null:
		candidates.append(tenant_node)
	for candidate in candidates:
		if not (candidate is HotelNPC) or not is_instance_valid(candidate):
			continue
		var distance := player.global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest


func _reanchor_persistent_items(anchor: Vector3) -> void:
	var seen: Dictionary = {}
	for container in [state.inventory, state.suitcase_inventory]:
		for cell in container:
			if not (cell is Dictionary) or bool(cell.get("reserved", false)):
				continue
			var uid := int(cell.get("uid", 0))
			if uid > 0 and not seen.has(uid):
				seen[uid] = true
				_item_origin_anchors[uid] = anchor


func _cleanup_floor() -> void:
	_lights_disabled_time = 0.0
	_lights_disabled_wing = ""
	_original_light_energy.clear()
	_knock_chase_time = 0.0
	_knock_chase_room_id = ""
	if floor != null and is_instance_valid(floor):
		if floor.get_parent() != null:
			floor.get_parent().remove_child(floor)
		floor.queue_free()
	floor = null
	guard_nodes = []
	cleaner_node = null
	tenant_node = null
	suitcase_node = null
	carried_world_node = null
