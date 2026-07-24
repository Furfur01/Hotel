extends SceneTree

const RunState = preload("res://game_state.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_round_durations()
	_test_inventory_transactions()
	_test_notebook_votes()
	_test_500_seed_manifests()
	_test_snapshot_round_trip()
	if failures.is_empty():
		print("HotelRunState: all tests passed (500 seeds x 2 days).")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _test_round_durations() -> void:
	var state = RunState.new(100)
	var day_one := state.begin_day(1)
	_check(is_equal_approx(float(state.timers.day), 240.0), "day investigation should allow four minutes")
	_check(day_one.guest_rooms.size() == 5, "Day 1 should contain exactly five guest rooms")
	state.begin_night()
	_check(is_equal_approx(float(state.timers.night), 120.0), "night cleanup should retain its two-minute pressure")
	var day_two := state.begin_day(2)
	_check(day_two.guest_rooms.size() == 5, "Day 2 should contain exactly five guest rooms")


func _check(p_condition: bool, p_message: String) -> void:
	if not p_condition:
		failures.append(p_message)


func _test_inventory_transactions() -> void:
	var state = RunState.new(101)
	var trap: Dictionary = state.add_item(state.CONTAINER_CARRY, "folding_trap")
	_check(bool(trap.ok), "two-slot trap should be added")
	_check(state.inventory[0].uid == state.inventory[1].uid, "trap must occupy two slots with one uid")
	_check(state.is_two_handed(), "trap in carry inventory should be two-handed")
	var lockpick: Dictionary = state.add_item(state.CONTAINER_CARRY, "lockpick")
	var extra_cleaner: Dictionary = state.add_item(state.CONTAINER_CARRY, "industrial_cleaner")
	_check(bool(lockpick.ok) and bool(extra_cleaner.ok), "small items should fill the remaining slots")

	var snapshot: Array = state.inventory.duplicate(true)
	var failed_add: Dictionary = state.add_item(state.CONTAINER_CARRY, "alarm_clock")
	_check(not bool(failed_add.ok), "item should not fit in a full carry inventory")
	_check(state.inventory == snapshot, "failed add must not mutate inventory")
	var second_trap: Dictionary = state.add_item(state.CONTAINER_CARRY, "folding_trap")
	_check(not bool(second_trap.ok), "only one two-handed carry item may be held")

	var moved: Dictionary = state.move_item(state.CONTAINER_CARRY, 0, state.CONTAINER_SUITCASE)
	_check(bool(moved.ok), "trap should move to suitcase")
	_check(state.get_free_slot_count(state.CONTAINER_CARRY) == 2, "moving trap must clear both of its carry slots")
	_check(state.suitcase_inventory[0].uid == state.suitcase_inventory[1].uid, "moved trap must remain atomic")
	state.remove_item(state.CONTAINER_CARRY, 2)
	state.remove_item(state.CONTAINER_CARRY, 3)

	var suitcase_pickup: Dictionary = state.set_suitcase_carried(true)
	_check(bool(suitcase_pickup.ok), "suitcase should reserve first two free slots")
	_check(state.suitcase_carried and state.is_two_handed(), "carried suitcase should be two-handed")
	var reserved_remove: Dictionary = state.remove_item(state.CONTAINER_CARRY, 0)
	_check(not bool(reserved_remove.ok), "generic removal must not remove suitcase reservation")
	_check(bool(state.set_suitcase_carried(false).ok), "suitcase should be droppable")

	var cleaner: Dictionary = state.add_item(state.CONTAINER_CARRY, "industrial_cleaner")
	_check(bool(cleaner.ok), "cleaner should be added")
	var consumed: Dictionary = state.consume_item(state.CONTAINER_CARRY, int(cleaner.slots[0]))
	_check(bool(consumed.ok) and bool(consumed.consumed), "consumable should be atomically removed")

	var blocked_state = RunState.new(102)
	var carried_trap: Dictionary = blocked_state.add_item(blocked_state.CONTAINER_CARRY, "folding_trap")
	for item_id in ["lockpick", "alarm_clock", "instant_camera", "industrial_cleaner"]:
		blocked_state.add_item(blocked_state.CONTAINER_SUITCASE, item_id)
	var carry_before: Array = blocked_state.inventory.duplicate(true)
	var suitcase_before: Array = blocked_state.suitcase_inventory.duplicate(true)
	var failed_move: Dictionary = blocked_state.move_item(
		blocked_state.CONTAINER_CARRY,
		int(carried_trap.slots[0]),
		blocked_state.CONTAINER_SUITCASE
	)
	_check(not bool(failed_move.ok), "move into a full suitcase should fail")
	_check(
		blocked_state.inventory == carry_before and blocked_state.suitcase_inventory == suitcase_before,
		"failed move must leave both containers untouched"
	)


func _test_notebook_votes() -> void:
	var state = RunState.new(202)
	var manifest: Dictionary = state.generate_day_manifest(1, 10)
	var target: Dictionary = {}
	for room_value in manifest.guest_rooms:
		var room: Dictionary = room_value
		var available := 0
		for source in state.EVIDENCE_SOURCES:
			if room.evidence[source] == state.VOTE_VACANT:
				available += 1
		if available >= 2:
			target = room
			break
	_check(not target.is_empty(), "day one must expose a confirmable vacant room")
	if target.is_empty():
		return
	state.discover_room(target.room_id)
	var used := 0
	for source in state.EVIDENCE_SOURCES:
		if target.evidence[source] == state.VOTE_VACANT and used < 2:
			var first: Dictionary = state.record_evidence(target.room_id, source)
			var repeat: Dictionary = state.record_evidence(target.room_id, source)
			_check(bool(first.ok), "first evidence recording should succeed")
			_check(bool(repeat.already_checked), "evidence source must not vote twice")
			used += 1
	var entry: Dictionary = state.get_notebook_entry(target.room_id)
	_check(entry.vacant_votes == 2, "two unique sources should yield exactly two votes")
	_check(entry.conclusion == state.VOTE_VACANT, "two true votes should confirm vacancy")


func _test_500_seed_manifests() -> void:
	for seed_value in range(1, 501):
		var state = RunState.new(seed_value)
		for tested_day in [1, 2]:
			var manifest: Dictionary = state.generate_day_manifest(tested_day)
			var validation: Dictionary = state.validate_manifest(manifest)
			_check(bool(validation.ok), "seed %d day %d invalid: %s" % [seed_value, tested_day, validation.errors])
			for room_value in manifest.guest_rooms:
				var evidence_validation: Dictionary = state.validate_room_evidence(room_value)
				_check(
					bool(evidence_validation.ok) and evidence_validation.checked_combinations == 16,
					"seed %d day %d contains unsafe evidence" % [seed_value, tested_day]
				)


func _test_snapshot_round_trip() -> void:
	var source = RunState.new(303)
	source.generate_day_manifest(2, 12)
	source.add_item(source.CONTAINER_CARRY, "lockpick")
	source.record_evidence(source.current_manifest.guest_rooms[0].room_id, "registration")
	var restored = RunState.new(1)
	var load_result: Dictionary = restored.load_dictionary(source.to_dictionary())
	_check(bool(load_result.ok), "snapshot should load")
	_check(restored.to_dictionary() == source.to_dictionary(), "snapshot round trip should preserve all run data")
