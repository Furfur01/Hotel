extends SceneTree

## Layout + manifest soak for the two time-budget constraints which are easy to
## regress when corridor scale or function-room placement changes.

const FloorScript = preload("res://hotel.gd")
const ControllerScript = preload("res://run_controller.gd")
const RunState = preload("res://game_state.gd")

const SEED_COUNT := 500
const SPRINT_SPEED := 7.0
const EXHAUSTED_HEAVY_SPEED := 2.0
const MAX_LOBBY_SECONDS := 20.0
const MAX_DISPOSAL_SECONDS := 35.0

var failures: Array[String] = []
var worst_lobby_seconds := 0.0
var worst_disposal_seconds := 0.0
var worst_theory_seconds := 0.0
var worst_fallback_seconds := 0.0
var one_point_days := 0
var two_point_days := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for run_seed in range(1, SEED_COUNT + 1):
		for day in [1, 2]:
			var controller = ControllerScript.new()
			controller.state = RunState.new(run_seed)
			controller.state.begin_day(day)
			controller.previous_guest_ordinal = run_seed % 10

			var floor = FloorScript.new()
			floor.day_index = day
			floor.generation_seed = controller._derive_layout_seed(run_seed, day)
			floor._generate_layout()
			floor._assign_room_metadata()
			controller.floor = floor

			var manifest: Dictionary = controller.build_day_manifest(floor.room_descriptors, floor.map_seed)
			var disposal_ids: Array = manifest.get("disposal_room_ids", [])
			if disposal_ids.size() == 1:
				one_point_days += 1
			elif disposal_ids.size() == 2:
				two_point_days += 1
			else:
				_fail(run_seed, day, "disposal count=%d" % disposal_ids.size())

			var lobby_seconds := floor.max_lobby_to_guest_distance() / SPRINT_SPEED
			var disposal_seconds := floor.max_guest_distance_to_rooms(disposal_ids) / EXHAUSTED_HEAVY_SPEED
			worst_lobby_seconds = maxf(worst_lobby_seconds, lobby_seconds)
			worst_disposal_seconds = maxf(worst_disposal_seconds, disposal_seconds)
			if lobby_seconds > MAX_LOBBY_SECONDS + 0.001:
				_fail(run_seed, day, "lobby sprint %.2fs" % lobby_seconds)
			if disposal_seconds > MAX_DISPOSAL_SECONDS + 0.001:
				_fail(run_seed, day, "heavy disposal %.2fs ids=%s" % [disposal_seconds, disposal_ids])
			for room_id in floor.get_guest_room_ids():
				var solution: Dictionary = controller.theoretical_night_solution(room_id)
				worst_theory_seconds = maxf(worst_theory_seconds, float(solution.get("fast_seconds", INF)))
				worst_fallback_seconds = maxf(worst_fallback_seconds, float(solution.get("fallback_seconds", INF)))
				if not bool(solution.get("ok", false)):
					_fail(run_seed, day, "night theory %s" % solution)

			_validate_day_two_safe_evidence(controller, floor, run_seed, day)
			_validate_public_unlocks(manifest, run_seed, day)
			controller.free()
			floor.free()

	print("LOGISTICS_GENERATION_TEST seeds=%d days=%d worst_lobby=%.2fs worst_heavy=%.2fs worst_theory=%.2fs fallback=%.2fs one_point=%d two_point=%d failures=%d" % [
		SEED_COUNT,
		SEED_COUNT * 2,
		worst_lobby_seconds,
		worst_disposal_seconds,
		worst_theory_seconds,
		worst_fallback_seconds,
		one_point_days,
		two_point_days,
		failures.size(),
	])
	for failure in failures.slice(0, mini(20, failures.size())):
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _validate_day_two_safe_evidence(controller, floor, run_seed: int, day: int) -> void:
	if day != 2:
		return
	var guest_ids: Array[String] = floor.get_guest_room_ids()
	var previous_index := clampi(controller.previous_guest_ordinal, 0, guest_ids.size() - 1)
	var previous_id: String = guest_ids[previous_index]
	var confirmable_new := 0
	for room_value in controller.state.current_manifest.get("guest_rooms", []):
		var room: Dictionary = room_value
		if String(room.get("room_id", "")) == previous_id:
			continue
		if String(room.get("assignment", "")) != RunState.ASSIGNMENT_VACANT:
			continue
		var votes := 0
		var evidence: Dictionary = room.get("evidence", {})
		for source in RunState.EVIDENCE_SOURCES:
			if String(evidence.get(source, "")) == RunState.VOTE_VACANT:
				votes += 1
		if votes >= 2:
			confirmable_new += 1
	if confirmable_new < 1:
		_fail(run_seed, day, "no confirmable new vacant room")


func _validate_public_unlocks(manifest: Dictionary, run_seed: int, day: int) -> void:
	var public_unlocks := 0
	for spawn_value in manifest.get("item_spawns", []):
		var spawn: Dictionary = spawn_value
		if String(spawn.get("item_id", "")) == "lockpick" and bool(spawn.get("public_access", false)):
			public_unlocks += 1
	if public_unlocks < 3:
		_fail(run_seed, day, "public unlocks=%d" % public_unlocks)


func _fail(run_seed: int, day: int, detail: String) -> void:
	failures.append("seed=%d day=%d %s" % [run_seed, day, detail])
