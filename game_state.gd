class_name HotelRunState
extends RefCounted

## Pure run data for the two-day hotel prototype.
##
## The scene layer owns geometry, actors and presentation.  This object only owns
## serialisable dictionaries/arrays so a regenerated floor can consume the same
## stable room truth without depending on node order.

const PHASE_DAY := "day"
const PHASE_NIGHT_LEAD := "night_lead"
const PHASE_NIGHT := "night"
const PHASE_BLACK_ROOM := "black_room"
const PHASE_COMPLETE := "complete"
const PHASE_GAME_OVER := "game_over"

const DAY_SECONDS := 240.0
const NIGHT_SECONDS := 120.0
const EARLY_DAY_GUEST_ROOMS := 5
const NIGHT_LEAD_SECONDS := 5.0
## Balance contract for the returning-tenant fallback route.  A generated floor
## must offer a legal fast-cleanup solution which consumes at most half of the
## night clock, leaving the other 60 seconds for aiming, door handling and NPC
## variation.  Action UIs and the theoretical solver share these values.
const NIGHT_THEORY_MAX_SECONDS := NIGHT_SECONDS * 0.50
const TENANT_CHASE_SPEED := 3.65
const EXHAUSTED_HEAVY_SPEED := 2.0
const CORPSE_WRAP_SECONDS := 12.0
const CORPSE_WRAP_FAST_SECONDS := 3.0
const STAIN_CLEAN_SECONDS := 18.0
const STAIN_CLEAN_FAST_SECONDS := 3.0
const BODY_DISPOSE_SECONDS := 4.0
const TRAP_DEPLOY_SECONDS := 3.0
const THEORY_CONTROL_BUFFER_SECONDS := 8.0
const MAX_STRIKES := 3
const INVENTORY_CAPACITY := 4
const SUITCASE_CAPACITY := 4

const CONTAINER_CARRY := "carry"
const CONTAINER_SUITCASE := "suitcase"

const ASSIGNMENT_VACANT := "vacant"
const ASSIGNMENT_RENTED := "rented"
const PRESENCE_NONE := "none"
const PRESENCE_INSIDE := "inside"
const PRESENCE_AWAY := "away"

const VOTE_NONE := ""
const VOTE_VACANT := "vacant"
const VOTE_RENTED := "rented"
const KNOCK_NO_RESPONSE := "no_response"

const EVIDENCE_SOURCES: Array[String] = [
	"registration",
	"doorstep",
	"listen",
	"knock",
]

const FUNCTIONAL_ROOM_TYPES: Array[String] = [
	"storage",
	"laundry",
	"maintenance",
	"security_archive",
	"service_elevator",
]

## The ten prototype consumables.  slot_cost is also the two-hand signal: an
## item with cost 2 is two-handed while it is in the carry inventory.  All ten
## may be stored in the suitcase; bodies and the suitcase itself are world
## objects and are deliberately not part of this table.
const ITEM_DEFINITIONS: Dictionary = {
	"staff_card": {
		"display_name": "保洁外套 / 工作卡",
		"slot_cost": 1,
		"can_store": true,
		"consumable": true,
	},
	"inspection_mirror": {
		"display_name": "伸缩检修镜",
		"slot_cost": 1,
		"can_store": true,
		"consumable": true,
	},
	"instant_camera": {
		"display_name": "拍立得",
		"slot_cost": 1,
		"can_store": true,
		"consumable": true,
	},
	"lockpick": {
		"display_name": "撬锁组",
		"slot_cost": 1,
		"can_store": true,
		"consumable": true,
	},
	"pry_bar": {
		"display_name": "扁撬",
		"slot_cost": 1,
		"can_store": true,
		"consumable": true,
	},
	"alarm_clock": {
		"display_name": "发条闹钟",
		"slot_cost": 1,
		"can_store": true,
		"consumable": true,
	},
	"electrician_kit": {
		"display_name": "电工套件",
		"slot_cost": 1,
		"can_store": true,
		"consumable": true,
	},
	"ratchet_strap": {
		"display_name": "棘轮绑带",
		"slot_cost": 1,
		"can_store": true,
		"consumable": true,
	},
	"industrial_cleaner": {
		"display_name": "工业去污剂",
		"slot_cost": 1,
		"can_store": true,
		"consumable": true,
	},
	"folding_trap": {
		"display_name": "折叠致命陷阱",
		"slot_cost": 2,
		"can_store": true,
		"consumable": true,
	},
}

var day_index: int = 1
var phase: String = PHASE_DAY
var timers: Dictionary = {}
var strikes: int = 0
var run_seed: int = 1

## Each occupied slot is a small dictionary containing uid/item_id/anchor.
## Both cells of a two-slot item share a uid; this keeps UI access simple while
## ensuring mutations always operate on the complete item.
var inventory: Array = []
var suitcase_inventory: Array = []
var suitcase_exists: bool = true
var suitcase_carried: bool = false
var carried_world_object: String = ""

## Entries are keyed by room_id.  Truth never enters the notebook; only the
## evidence votes actually observed by the player are stored here.
var notebook: Dictionary = {}
var current_manifest: Dictionary = {}

var _next_item_uid: int = 1


func _init(p_run_seed: int = 0) -> void:
	reset_run(p_run_seed)


func reset_run(p_run_seed: int = 0) -> void:
	run_seed = p_run_seed
	if run_seed == 0:
		run_seed = int(Time.get_ticks_usec()) ^ randi()
	if run_seed == 0:
		run_seed = 1
	day_index = 1
	phase = PHASE_DAY
	timers = {
		"day": DAY_SECONDS,
		"night": NIGHT_SECONDS,
		"lead": 0.0,
	}
	strikes = 0
	inventory = _empty_slots(INVENTORY_CAPACITY)
	suitcase_inventory = _empty_slots(SUITCASE_CAPACITY)
	suitcase_exists = true
	suitcase_carried = false
	carried_world_object = ""
	notebook = {}
	current_manifest = {}
	_next_item_uid = 1


func begin_day(p_day_index: int = -1) -> Dictionary:
	if p_day_index > 0:
		day_index = p_day_index
	phase = PHASE_DAY
	strikes = 0
	timers.day = DAY_SECONDS
	timers.night = NIGHT_SECONDS
	timers.lead = 0.0
	notebook = {}
	return generate_day_manifest(day_index)


func begin_night(p_with_lead: bool = true) -> void:
	timers.night = NIGHT_SECONDS
	timers.lead = NIGHT_LEAD_SECONDS if p_with_lead else 0.0
	phase = PHASE_NIGHT_LEAD if p_with_lead else PHASE_NIGHT


## Advances the active timer.  The five-second lead is part of the night
## night budget (it is a head start, not bonus cleanup time).
func tick(p_delta: float) -> Dictionary:
	var delta := maxf(p_delta, 0.0)
	var expired := false
	if phase == PHASE_DAY:
		timers.day = maxf(float(timers.day) - delta, 0.0)
		expired = float(timers.day) <= 0.0
	elif phase == PHASE_NIGHT_LEAD:
		timers.lead = maxf(float(timers.lead) - delta, 0.0)
		timers.night = maxf(float(timers.night) - delta, 0.0)
		expired = float(timers.night) <= 0.0
		if float(timers.lead) <= 0.0:
			phase = PHASE_NIGHT
	elif phase == PHASE_NIGHT:
		timers.night = maxf(float(timers.night) - delta, 0.0)
		expired = float(timers.night) <= 0.0
	return {
		"phase": phase,
		"expired": expired,
		"timers": timers.duplicate(true),
	}


## First two captures are recoverable.  The third is an atomic confiscation and
## moves the calendar forward two days, leaving an empty suitcase shell.
func add_daytime_strike() -> Dictionary:
	if phase != PHASE_DAY:
		return _failure("not_daytime")
	strikes += 1
	if strikes < MAX_STRIKES:
		return {
			"ok": true,
			"black_room": false,
			"strikes": strikes,
			"time_penalty": 15.0,
		}
	clear_all_items()
	day_index += 2
	phase = PHASE_BLACK_ROOM
	return {
		"ok": true,
		"black_room": true,
		"strikes": strikes,
		"day_index": day_index,
	}


func apply_daytime_capture_penalty() -> void:
	## Kept separate from add_daytime_strike so a controller can play the capture
	## transition first and then debit exactly the documented fifteen seconds.
	if phase == PHASE_DAY:
		timers.day = maxf(float(timers.day) - 15.0, 0.0)


func clear_all_items() -> void:
	inventory = _empty_slots(INVENTORY_CAPACITY)
	suitcase_inventory = _empty_slots(SUITCASE_CAPACITY)
	suitcase_carried = false
	carried_world_object = ""


func complete_current_day() -> Dictionary:
	if day_index >= 2:
		phase = PHASE_COMPLETE
		return {"ok": true, "complete": true, "day_index": day_index}
	day_index += 1
	return {
		"ok": true,
		"complete": false,
		"day_index": day_index,
		"manifest": begin_day(day_index),
	}


# ---------------------------------------------------------------------------
# Inventory transactions

func get_item_definition(p_item_id: String) -> Dictionary:
	if not ITEM_DEFINITIONS.has(p_item_id):
		return {}
	return ITEM_DEFINITIONS[p_item_id].duplicate(true)


func add_item(p_container: String, p_item_id: String, p_preferred_slot: int = -1) -> Dictionary:
	if not ITEM_DEFINITIONS.has(p_item_id):
		return _failure("unknown_item")
	if not _container_exists(p_container):
		return _failure("invalid_container")
	var definition: Dictionary = ITEM_DEFINITIONS[p_item_id]
	if p_container == CONTAINER_SUITCASE and not bool(definition.can_store):
		return _failure("item_cannot_be_stored")
	if p_container == CONTAINER_CARRY and int(definition.slot_cost) >= 2:
		if carried_world_object != "" or _has_two_handed_inventory_item():
			return _failure("hands_already_occupied")
	var working := _get_container_slots(p_container).duplicate(true)
	var target_slots := _find_target_slots(working, int(definition.slot_cost), p_preferred_slot)
	if target_slots.is_empty():
		return _failure("not_enough_space")
	var uid := _next_item_uid
	_next_item_uid += 1
	_write_item_to_slots(working, target_slots, uid, p_item_id)
	_set_container_slots(p_container, working)
	return {
		"ok": true,
		"uid": uid,
		"item_id": p_item_id,
		"container": p_container,
		"slots": target_slots,
	}


func remove_item(p_container: String, p_slot: int) -> Dictionary:
	var lookup := _lookup_item(p_container, p_slot)
	if not bool(lookup.ok):
		return lookup
	if bool(lookup.get("reserved", false)):
		return _failure("reserved_hand_slot")
	var working := _get_container_slots(p_container).duplicate(true)
	for index in lookup.slots:
		working[int(index)] = null
	_set_container_slots(p_container, working)
	return {
		"ok": true,
		"uid": lookup.uid,
		"item_id": lookup.item_id,
		"container": p_container,
		"slots": lookup.slots,
	}


func consume_item(p_container: String, p_slot: int) -> Dictionary:
	var lookup := _lookup_item(p_container, p_slot)
	if not bool(lookup.ok):
		return lookup
	if bool(lookup.get("reserved", false)):
		return _failure("reserved_hand_slot")
	var definition: Dictionary = ITEM_DEFINITIONS.get(String(lookup.item_id), {})
	if definition.is_empty() or not bool(definition.get("consumable", false)):
		return _failure("item_not_consumable")
	var result := remove_item(p_container, p_slot)
	if bool(result.ok):
		result["consumed"] = true
	return result


func consume_item_by_id(p_item_id: String, p_search_suitcase: bool = true) -> Dictionary:
	for index in range(inventory.size()):
		var slot = inventory[index]
		if slot is Dictionary and String(slot.get("item_id", "")) == p_item_id:
			return consume_item(CONTAINER_CARRY, index)
	if p_search_suitcase:
		for index in range(suitcase_inventory.size()):
			var slot = suitcase_inventory[index]
			if slot is Dictionary and String(slot.get("item_id", "")) == p_item_id:
				return consume_item(CONTAINER_SUITCASE, index)
	return _failure("item_not_found")


## Moves a complete item or does nothing.  Source removal and target placement
## are both performed on temporary arrays and committed only after all checks.
func move_item(
	p_from_container: String,
	p_from_slot: int,
	p_to_container: String,
	p_preferred_slot: int = -1
) -> Dictionary:
	var lookup := _lookup_item(p_from_container, p_from_slot)
	if not bool(lookup.ok):
		return lookup
	if bool(lookup.get("reserved", false)):
		return _failure("reserved_hand_slot")
	if not _container_exists(p_to_container):
		return _failure("invalid_container")
	var definition: Dictionary = ITEM_DEFINITIONS.get(String(lookup.item_id), {})
	if p_to_container == CONTAINER_SUITCASE and not bool(definition.get("can_store", false)):
		return _failure("item_cannot_be_stored")
	if p_to_container == CONTAINER_CARRY and int(definition.get("slot_cost", 1)) >= 2:
		if carried_world_object != "":
			return _failure("hands_already_occupied")
		if p_from_container != CONTAINER_CARRY and _has_two_handed_inventory_item():
			return _failure("hands_already_occupied")

	var source_work := _get_container_slots(p_from_container).duplicate(true)
	for index in lookup.slots:
		source_work[int(index)] = null
	var target_work: Array
	if p_from_container == p_to_container:
		target_work = source_work
	else:
		target_work = _get_container_slots(p_to_container).duplicate(true)
	var target_slots := _find_target_slots(target_work, int(definition.slot_cost), p_preferred_slot)
	if target_slots.is_empty():
		return _failure("not_enough_space")
	_write_item_to_slots(target_work, target_slots, int(lookup.uid), String(lookup.item_id))
	if p_from_container == p_to_container:
		_set_container_slots(p_from_container, target_work)
	else:
		_set_container_slots(p_from_container, source_work)
		_set_container_slots(p_to_container, target_work)
	return {
		"ok": true,
		"uid": lookup.uid,
		"item_id": lookup.item_id,
		"from_container": p_from_container,
		"to_container": p_to_container,
		"slots": target_slots,
	}


func get_item_at(p_container: String, p_slot: int) -> Dictionary:
	var result := _lookup_item(p_container, p_slot)
	return result.duplicate(true)


## The suitcase and a wrapped body are world objects.  They reserve carry slots
## 0 and 1 because they physically occupy both hands.  Reservation is atomic and
## refuses to overwrite inventory already in those cells.
func set_suitcase_carried(p_carried: bool) -> Dictionary:
	if p_carried:
		if not suitcase_exists:
			return _failure("suitcase_missing")
		return _reserve_world_object("suitcase")
	if carried_world_object != "suitcase":
		return _failure("suitcase_not_carried")
	_release_world_object()
	return {"ok": true, "carried": false, "world_object": "suitcase"}


func set_body_carried(p_carried: bool) -> Dictionary:
	if p_carried:
		return _reserve_world_object("body")
	if carried_world_object != "body":
		return _failure("body_not_carried")
	_release_world_object()
	return {"ok": true, "carried": false, "world_object": "body"}


func is_two_handed() -> bool:
	return carried_world_object != "" or _has_two_handed_inventory_item()


func get_free_slot_count(p_container: String) -> int:
	if not _container_exists(p_container):
		return 0
	var count := 0
	for slot in _get_container_slots(p_container):
		if slot == null:
			count += 1
	return count


func _reserve_world_object(p_kind: String) -> Dictionary:
	if p_kind != "suitcase" and p_kind != "body":
		return _failure("invalid_world_object")
	if carried_world_object != "":
		return _failure("hands_already_occupied")
	if _has_two_handed_inventory_item():
		return _failure("hands_already_occupied")
	if inventory[0] != null or inventory[1] != null:
		return _failure("first_two_slots_occupied")
	var working := inventory.duplicate(true)
	var reservation_uid := -1 if p_kind == "suitcase" else -2
	for index in [0, 1]:
		working[index] = {
			"uid": reservation_uid,
			"item_id": p_kind,
			"anchor": index == 0,
			"reserved": true,
		}
	inventory = working
	carried_world_object = p_kind
	suitcase_carried = p_kind == "suitcase"
	return {"ok": true, "carried": true, "world_object": p_kind, "slots": [0, 1]}


func _release_world_object() -> void:
	var working := inventory.duplicate(true)
	for index in range(mini(2, working.size())):
		var slot = working[index]
		if slot is Dictionary and bool(slot.get("reserved", false)):
			working[index] = null
	inventory = working
	carried_world_object = ""
	suitcase_carried = false


func _has_two_handed_inventory_item() -> bool:
	var seen: Dictionary = {}
	for slot in inventory:
		if not (slot is Dictionary) or bool(slot.get("reserved", false)):
			continue
		var uid := int(slot.get("uid", 0))
		if seen.has(uid):
			continue
		seen[uid] = true
		var definition: Dictionary = ITEM_DEFINITIONS.get(String(slot.get("item_id", "")), {})
		if int(definition.get("slot_cost", 1)) >= 2:
			return true
	return false


func _lookup_item(p_container: String, p_slot: int) -> Dictionary:
	if not _container_exists(p_container):
		return _failure("invalid_container")
	var slots := _get_container_slots(p_container)
	if p_slot < 0 or p_slot >= slots.size():
		return _failure("invalid_slot")
	var cell = slots[p_slot]
	if not (cell is Dictionary):
		return _failure("empty_slot")
	var uid := int(cell.get("uid", 0))
	return {
		"ok": true,
		"uid": uid,
		"item_id": String(cell.get("item_id", "")),
		"container": p_container,
		"slots": _indices_for_uid(slots, uid),
		"reserved": bool(cell.get("reserved", false)),
	}


func _container_exists(p_container: String) -> bool:
	if p_container == CONTAINER_CARRY:
		return true
	return p_container == CONTAINER_SUITCASE and suitcase_exists


func _get_container_slots(p_container: String) -> Array:
	return inventory if p_container == CONTAINER_CARRY else suitcase_inventory


func _set_container_slots(p_container: String, p_slots: Array) -> void:
	if p_container == CONTAINER_CARRY:
		inventory = p_slots
	else:
		suitcase_inventory = p_slots


func _find_target_slots(p_slots: Array, p_cost: int, p_preferred_slot: int) -> Array:
	if p_cost <= 0 or p_cost > p_slots.size():
		return []
	if p_preferred_slot >= 0:
		if p_preferred_slot + p_cost > p_slots.size():
			return []
		for offset in range(p_cost):
			if p_slots[p_preferred_slot + offset] != null:
				return []
		var preferred: Array = []
		for offset in range(p_cost):
			preferred.append(p_preferred_slot + offset)
		return preferred
	for start in range(p_slots.size() - p_cost + 1):
		var available := true
		for offset in range(p_cost):
			if p_slots[start + offset] != null:
				available = false
				break
		if available:
			var found: Array = []
			for offset in range(p_cost):
				found.append(start + offset)
			return found
	return []


func _write_item_to_slots(
	p_slots: Array,
	p_indices: Array,
	p_uid: int,
	p_item_id: String
) -> void:
	for position in range(p_indices.size()):
		p_slots[int(p_indices[position])] = {
			"uid": p_uid,
			"item_id": p_item_id,
			"anchor": position == 0,
			"reserved": false,
		}


func _indices_for_uid(p_slots: Array, p_uid: int) -> Array:
	var result: Array = []
	for index in range(p_slots.size()):
		var slot = p_slots[index]
		if slot is Dictionary and int(slot.get("uid", 0)) == p_uid:
			result.append(index)
	return result


func _empty_slots(p_size: int) -> Array:
	var result: Array = []
	result.resize(p_size)
	result.fill(null)
	return result


# ---------------------------------------------------------------------------
# Notebook

func discover_room(p_room_id: String) -> Dictionary:
	var room := find_room(p_room_id)
	if room.is_empty():
		return _failure("unknown_room")
	if notebook.has(p_room_id):
		return notebook[p_room_id].duplicate(true)
	var observed: Dictionary = {}
	var checked: Dictionary = {}
	for source in EVIDENCE_SOURCES:
		observed[source] = VOTE_NONE
		checked[source] = false
	var entry := {
		"room_id": p_room_id,
		"room_number": String(room.get("room_number", p_room_id)),
		"evidence": observed,
		"checked": checked,
		"vacant_votes": 0,
		"rented_votes": 0,
		"conclusion": VOTE_NONE,
	}
	notebook[p_room_id] = entry
	return entry.duplicate(true)


## Records at most one vote from each source.  The caller supplies only the room
## and source; the vote is read from the immutable manifest, preventing UI or
## interaction code from accidentally writing a false clue.
func record_evidence(p_room_id: String, p_source: String) -> Dictionary:
	if not EVIDENCE_SOURCES.has(p_source):
		return _failure("invalid_evidence_source")
	var room := find_room(p_room_id)
	if room.is_empty():
		return _failure("unknown_room")
	if not notebook.has(p_room_id):
		var discovered := discover_room(p_room_id)
		if not bool(discovered.get("ok", true)):
			return discovered
	var entry: Dictionary = notebook[p_room_id]
	var checked: Dictionary = entry.checked
	if bool(checked.get(p_source, false)):
		return {
			"ok": true,
			"already_checked": true,
			"vote": String(entry.evidence.get(p_source, VOTE_NONE)),
			"entry": entry.duplicate(true),
		}
	var truth_evidence: Dictionary = room.get("evidence", {})
	var vote := String(truth_evidence.get(p_source, VOTE_NONE))
	checked[p_source] = true
	entry.checked = checked
	var observed: Dictionary = entry.evidence
	observed[p_source] = vote
	entry.evidence = observed
	_recount_notebook_entry(entry)
	notebook[p_room_id] = entry
	return {
		"ok": true,
		"already_checked": false,
		"vote": vote,
		"entry": entry.duplicate(true),
	}


func get_notebook_entry(p_room_id: String) -> Dictionary:
	if not notebook.has(p_room_id):
		return {}
	return notebook[p_room_id].duplicate(true)


func _recount_notebook_entry(p_entry: Dictionary) -> void:
	var vacant := 0
	var rented := 0
	var evidence: Dictionary = p_entry.evidence
	for source in EVIDENCE_SOURCES:
		var vote := String(evidence.get(source, VOTE_NONE))
		if vote == VOTE_VACANT:
			vacant += 1
		elif vote == VOTE_RENTED:
			rented += 1
	p_entry.vacant_votes = vacant
	p_entry.rented_votes = rented
	if vacant >= 2:
		p_entry.conclusion = VOTE_VACANT
	elif rented >= 2:
		p_entry.conclusion = VOTE_RENTED
	else:
		p_entry.conclusion = VOTE_NONE


func find_room(p_room_id: String, p_manifest: Dictionary = {}) -> Dictionary:
	var manifest := current_manifest if p_manifest.is_empty() else p_manifest
	for room_value in manifest.get("guest_rooms", []):
		var room: Dictionary = room_value
		if String(room.get("room_id", "")) == p_room_id:
			return room.duplicate(true)
	return {}


# ---------------------------------------------------------------------------
# Deterministic day manifests

func generate_day_manifest(p_day_index: int = -1, p_room_count: int = -1) -> Dictionary:
	var manifest_day := day_index if p_day_index < 1 else p_day_index
	var truth_rng := _make_rng(_derive_seed(manifest_day, "truth"))
	var loot_rng := _make_rng(_derive_seed(manifest_day, "loot"))
	var room_count := EARLY_DAY_GUEST_ROOMS if manifest_day <= 2 else p_room_count
	if manifest_day > 2:
		if room_count < 0:
			room_count = truth_rng.randi_range(10, 14)
		room_count = clampi(room_count, 10, 14)

	var rooms := _generate_guest_rooms(manifest_day, room_count, truth_rng)
	var functional_rooms := generate_functional_rooms(manifest_day)
	var disposal_points := generate_disposal_points(functional_rooms, loot_rng)
	var item_spawns := generate_item_spawns(manifest_day, loot_rng)
	var manifest := {
		"day_index": manifest_day,
		"run_seed": run_seed,
		"seeds": {
			"layout": _derive_seed(manifest_day, "layout"),
			"truth": _derive_seed(manifest_day, "truth"),
			"decor": _derive_seed(manifest_day, "decor"),
			"loot": _derive_seed(manifest_day, "loot"),
		},
		"guest_rooms": rooms,
		"functional_rooms": functional_rooms,
		"disposal_points": disposal_points,
		"item_spawns": item_spawns,
	}
	manifest["validation"] = validate_manifest(manifest)
	current_manifest = manifest.duplicate(true)
	day_index = manifest_day
	notebook = {}
	return manifest.duplicate(true)


func _generate_guest_rooms(
	p_day_index: int,
	p_room_count: int,
	p_rng: RandomNumberGenerator
) -> Array:
	var vacancy_ratio := 0.30 if p_day_index <= 1 else 0.20
	var minimum_vacant := 3 if p_day_index <= 1 else 2
	var guaranteed_confirmable := 2 if p_day_index <= 1 else 1
	var vacant_count := maxi(minimum_vacant, int(round(float(p_room_count) * vacancy_ratio)))
	var shuffled := _shuffled_indices(p_room_count, p_rng)
	var vacant_indices: Dictionary = {}
	var guaranteed_indices: Dictionary = {}
	for index in range(vacant_count):
		vacant_indices[int(shuffled[index])] = true
	for index in range(guaranteed_confirmable):
		guaranteed_indices[int(shuffled[index])] = true

	var rented_indices: Array = []
	for index in range(p_room_count):
		if not vacant_indices.has(index):
			rented_indices.append(index)
	_shuffle_array(rented_indices, p_rng)
	var inside_count := int(round(float(rented_indices.size()) * 0.40))
	var inside_indices: Dictionary = {}
	for index in range(inside_count):
		inside_indices[int(rented_indices[index])] = true

	var rooms: Array = []
	for index in range(p_room_count):
		var is_vacant := vacant_indices.has(index)
		var assignment := ASSIGNMENT_VACANT if is_vacant else ASSIGNMENT_RENTED
		var presence := PRESENCE_NONE
		var returns_tonight := false
		if not is_vacant:
			if inside_indices.has(index):
				presence = PRESENCE_INSIDE
			else:
				presence = PRESENCE_AWAY
				var no_return_chance := 0.40 if p_day_index <= 1 else 0.25
				returns_tonight = p_rng.randf() >= no_return_chance
		var wing := "east" if index % 2 == 0 else "west"
		var room_number_value := 101 + index
		var room_id := "D%02d-R%03d" % [p_day_index, room_number_value]
		var room := {
			"room_id": room_id,
			"room_number": str(room_number_value),
			"wing": wing,
			"assignment": assignment,
			"presence": presence,
			"returns_tonight": returns_tonight,
			"locked": p_rng.randf() < 0.50,
			"evidence": _generate_room_evidence(
				assignment,
				presence,
				guaranteed_indices.has(index),
				p_rng
			),
		}
		rooms.append(room)
	return rooms


func _generate_room_evidence(
	p_assignment: String,
	p_presence: String,
	p_guaranteed_confirmable: bool,
	p_rng: RandomNumberGenerator
) -> Dictionary:
	var evidence := {
		"registration": VOTE_NONE,
		"doorstep": VOTE_NONE,
		"listen": VOTE_NONE,
		"knock": VOTE_NONE,
	}
	if p_assignment == ASSIGNMENT_VACANT:
		if p_guaranteed_confirmable:
			evidence.registration = VOTE_VACANT
			evidence.doorstep = VOTE_VACANT
		else:
			if p_rng.randf() < 0.70:
				evidence.registration = VOTE_VACANT
			if p_rng.randf() < 0.50:
				evidence.doorstep = VOTE_VACANT
		evidence.knock = KNOCK_NO_RESPONSE
		return evidence

	if p_rng.randf() < 0.75:
		evidence.registration = VOTE_RENTED
	if p_rng.randf() < 0.55:
		evidence.doorstep = VOTE_RENTED
	if p_presence == PRESENCE_INSIDE:
		if p_rng.randf() < 0.70:
			evidence.listen = VOTE_RENTED
		evidence.knock = VOTE_RENTED
	else:
		evidence.knock = KNOCK_NO_RESPONSE
	return evidence


func generate_functional_rooms(p_day_index: int) -> Array:
	var result: Array = []
	for type_name in FUNCTIONAL_ROOM_TYPES:
		result.append({
			"room_id": "D%02d-F-%s" % [p_day_index, type_name],
			"room_type": type_name,
			"locked": true,
			"is_guest_room": false,
		})
	return result


func generate_disposal_points(
	p_functional_rooms: Array,
	p_rng: RandomNumberGenerator
) -> Array:
	var candidates: Array = []
	for room_value in p_functional_rooms:
		var room: Dictionary = room_value
		if String(room.room_type) in ["storage", "laundry", "service_elevator"]:
			candidates.append(room)
	_shuffle_array(candidates, p_rng)
	var point_count := p_rng.randi_range(1, 2)
	var result: Array = []
	for index in range(point_count):
		var candidate: Dictionary = candidates[index]
		result.append({
			"point_id": "%s-disposal" % String(candidate.room_id),
			"room_id": String(candidate.room_id),
			"room_type": String(candidate.room_type),
			"discovered": false,
		})
	return result


func generate_item_spawns(p_day_index: int, p_rng: RandomNumberGenerator) -> Array:
	var target_count := 8 if p_day_index <= 1 else 9
	var result: Array = []
	## Three disposal-capable function rooms are all locked and their active state
	## is intentionally hidden.  Three public one-use picks let a cautious player
	## inspect every candidate without the key-behind-a-locked-door deadlock.
	for public_index in range(3):
		result.append(_spawn_record(public_index, "lockpick", "public_corridor_%02d" % public_index, "public", true))

	var next_index := 3
	if p_rng.randf() < 0.50:
		result.append(_spawn_record(next_index, "folding_trap", "storage", "storage", false))
		next_index += 1

	## These two one-use tools form the guaranteed <=60-second night fallback.
	## They remain behind the locked laundry door, so the player must still spend
	## a public lockpick and deliberately carry them into the selected room.
	for cleanup_item in ["ratchet_strap", "industrial_cleaner"]:
		result.append(_spawn_record(next_index, cleanup_item, "laundry", "laundry", false))
		next_index += 1

	var ordinary_pool: Array = [
		"inspection_mirror",
		"instant_camera",
		"alarm_clock",
		"lockpick",
	]
	var advanced_pool: Array = [
		{"item_id": "staff_card", "zone": "security_archive"},
		{"item_id": "pry_bar", "zone": "maintenance"},
		{"item_id": "electrician_kit", "zone": "maintenance"},
	]
	while result.size() < target_count:
		if result.size() % 2 == 0:
			var advanced: Dictionary = advanced_pool[p_rng.randi_range(0, advanced_pool.size() - 1)]
			result.append(_spawn_record(
				next_index,
				String(advanced.item_id),
				String(advanced.zone),
				String(advanced.zone),
				false
			))
		else:
			var item_id := String(ordinary_pool[p_rng.randi_range(0, ordinary_pool.size() - 1)])
			result.append(_spawn_record(
				next_index,
				item_id,
				"guest_room_%02d" % next_index,
				"guest_room",
				false
			))
		next_index += 1
	return result


func _spawn_record(
	p_index: int,
	p_item_id: String,
	p_origin_anchor: String,
	p_zone_type: String,
	p_public_access: bool
) -> Dictionary:
	var definition: Dictionary = ITEM_DEFINITIONS[p_item_id]
	return {
		"spawn_id": "I%02d-%s" % [p_index, p_item_id],
		"item_id": p_item_id,
		"slot_cost": int(definition.slot_cost),
		"origin_anchor": p_origin_anchor,
		"zone_type": p_zone_type,
		"public_access": p_public_access,
	}


## Exhaustively checks every subset of the four evidence sources.  A subset
## may remain uncertain, but any automatic two-vote conclusion must equal the
## room's assignment.
func validate_room_evidence(p_room: Dictionary) -> Dictionary:
	var errors: Array = []
	var assignment := String(p_room.get("assignment", ""))
	var evidence: Dictionary = p_room.get("evidence", {})
	for source in EVIDENCE_SOURCES:
		var vote := String(evidence.get(source, VOTE_NONE))
		if vote == KNOCK_NO_RESPONSE:
			if source != "knock" or String(p_room.get("presence", "")) == PRESENCE_INSIDE:
				errors.append("invalid no-response %s:%s" % [source, vote])
		elif vote not in [VOTE_NONE, VOTE_VACANT, VOTE_RENTED]:
			errors.append("invalid vote %s:%s" % [source, vote])
		elif vote != VOTE_NONE and vote != assignment:
			errors.append("false vote %s:%s" % [source, vote])
	var combination_count := 1 << EVIDENCE_SOURCES.size()
	for mask in range(combination_count):
		var vacant_votes := 0
		var rented_votes := 0
		for source_index in range(EVIDENCE_SOURCES.size()):
			if mask & (1 << source_index) == 0:
				continue
			var vote := String(evidence.get(EVIDENCE_SOURCES[source_index], VOTE_NONE))
			if vote == VOTE_VACANT:
				vacant_votes += 1
			elif vote == VOTE_RENTED:
				rented_votes += 1
		if vacant_votes >= 2 and assignment != ASSIGNMENT_VACANT:
			errors.append("mask %d falsely confirms vacant" % mask)
		if rented_votes >= 2 and assignment != ASSIGNMENT_RENTED:
			errors.append("mask %d falsely confirms rented" % mask)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"checked_combinations": combination_count,
	}


func validate_manifest(p_manifest: Dictionary) -> Dictionary:
	var errors: Array = []
	var rooms: Array = p_manifest.get("guest_rooms", [])
	var manifest_day := int(p_manifest.get("day_index", 1))
	if manifest_day <= 2 and rooms.size() != EARLY_DAY_GUEST_ROOMS:
		errors.append("early-day guest room count must be %d" % EARLY_DAY_GUEST_ROOMS)
	elif manifest_day > 2 and (rooms.size() < 10 or rooms.size() > 14):
		errors.append("guest room count outside 10..14")
	var ids: Dictionary = {}
	var vacant_count := 0
	var rented_count := 0
	var inside_count := 0
	var confirmable_vacant_count := 0
	for room_value in rooms:
		var room: Dictionary = room_value
		var room_id := String(room.get("room_id", ""))
		if room_id.is_empty() or ids.has(room_id):
			errors.append("missing or duplicate room_id: %s" % room_id)
		ids[room_id] = true
		var assignment := String(room.get("assignment", ""))
		if assignment == ASSIGNMENT_VACANT:
			vacant_count += 1
			if _available_vote_count(room, VOTE_VACANT) >= 2:
				confirmable_vacant_count += 1
		elif assignment == ASSIGNMENT_RENTED:
			rented_count += 1
			if String(room.get("presence", "")) == PRESENCE_INSIDE:
				inside_count += 1
		else:
			errors.append("invalid assignment in %s" % room_id)
		var evidence_result := validate_room_evidence(room)
		if not bool(evidence_result.ok):
			for error in evidence_result.errors:
				errors.append("%s: %s" % [room_id, error])
	var minimum_vacant := 3 if manifest_day <= 1 else 2
	var minimum_confirmable := 2 if manifest_day <= 1 else 1
	if vacant_count < minimum_vacant:
		errors.append("too few vacant rooms")
	if confirmable_vacant_count < minimum_confirmable:
		errors.append("too few confirmable vacant rooms")
	if rented_count > 0:
		var expected_inside := int(round(float(rented_count) * 0.40))
		if inside_count != expected_inside:
			errors.append("inside tenant count differs from rounded 40 percent")
	var functional_rooms: Array = p_manifest.get("functional_rooms", [])
	if functional_rooms.size() != FUNCTIONAL_ROOM_TYPES.size():
		errors.append("functional room set incomplete")
	for room_value in functional_rooms:
		var room: Dictionary = room_value
		if not bool(room.get("locked", false)):
			errors.append("functional room is not locked")
	var disposal_points: Array = p_manifest.get("disposal_points", [])
	if disposal_points.size() < 1 or disposal_points.size() > 2:
		errors.append("disposal point count outside 1..2")
	var item_spawns: Array = p_manifest.get("item_spawns", [])
	var expected_items := 8 if manifest_day <= 1 else 9
	if item_spawns.size() != expected_items:
		errors.append("wrong item spawn count")
	var public_lockpick_count := 0
	var cleanup_tools: Dictionary = {
		"ratchet_strap": false,
		"industrial_cleaner": false,
	}
	for spawn_value in item_spawns:
		var spawn: Dictionary = spawn_value
		var item_id := String(spawn.get("item_id", ""))
		if item_id == "lockpick" and bool(spawn.get("public_access", false)):
			public_lockpick_count += 1
		if cleanup_tools.has(item_id) and String(spawn.get("zone_type", "")) == "laundry":
			cleanup_tools[item_id] = true
	if public_lockpick_count < 3:
		errors.append("fewer than three publicly accessible lockpicks")
	for cleanup_item in cleanup_tools:
		if not bool(cleanup_tools[cleanup_item]):
			errors.append("missing guaranteed laundry cleanup tool: %s" % cleanup_item)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"guest_room_count": rooms.size(),
		"vacant_count": vacant_count,
		"rented_count": rented_count,
		"inside_count": inside_count,
		"confirmable_vacant_count": confirmable_vacant_count,
	}


func _available_vote_count(p_room: Dictionary, p_vote: String) -> int:
	var count := 0
	var evidence: Dictionary = p_room.get("evidence", {})
	for source in EVIDENCE_SOURCES:
		if String(evidence.get(source, VOTE_NONE)) == p_vote:
			count += 1
	return count


func _derive_seed(p_day_index: int, p_stream: String) -> int:
	var value := ("%d:%d:%s" % [run_seed, p_day_index, p_stream]).hash()
	return value if value != 0 else 1


func _make_rng(p_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	return rng


func _shuffled_indices(p_count: int, p_rng: RandomNumberGenerator) -> Array:
	var result: Array = []
	for index in range(p_count):
		result.append(index)
	_shuffle_array(result, p_rng)
	return result


func _shuffle_array(p_values: Array, p_rng: RandomNumberGenerator) -> void:
	for index in range(p_values.size() - 1, 0, -1):
		var swap_index := p_rng.randi_range(0, index)
		var temporary = p_values[index]
		p_values[index] = p_values[swap_index]
		p_values[swap_index] = temporary


func _failure(p_reason: String) -> Dictionary:
	return {"ok": false, "reason": p_reason}


# ---------------------------------------------------------------------------
# Save-friendly snapshots

func to_dictionary() -> Dictionary:
	return {
		"day_index": day_index,
		"phase": phase,
		"timers": timers.duplicate(true),
		"strikes": strikes,
		"run_seed": run_seed,
		"inventory": inventory.duplicate(true),
		"suitcase_inventory": suitcase_inventory.duplicate(true),
		"suitcase_exists": suitcase_exists,
		"suitcase_carried": suitcase_carried,
		"carried_world_object": carried_world_object,
		"notebook": notebook.duplicate(true),
		"current_manifest": current_manifest.duplicate(true),
		"next_item_uid": _next_item_uid,
	}


func load_dictionary(p_data: Dictionary) -> Dictionary:
	var loaded_inventory: Array = p_data.get("inventory", [])
	var loaded_suitcase: Array = p_data.get("suitcase_inventory", [])
	if loaded_inventory.size() != INVENTORY_CAPACITY:
		return _failure("invalid_inventory_size")
	if loaded_suitcase.size() != SUITCASE_CAPACITY:
		return _failure("invalid_suitcase_size")
	day_index = maxi(1, int(p_data.get("day_index", 1)))
	phase = String(p_data.get("phase", PHASE_DAY))
	timers = p_data.get("timers", {}).duplicate(true)
	if not timers.has("day") or not timers.has("night") or not timers.has("lead"):
		return _failure("invalid_timers")
	strikes = clampi(int(p_data.get("strikes", 0)), 0, MAX_STRIKES)
	run_seed = int(p_data.get("run_seed", 1))
	inventory = loaded_inventory.duplicate(true)
	suitcase_inventory = loaded_suitcase.duplicate(true)
	suitcase_exists = bool(p_data.get("suitcase_exists", true))
	suitcase_carried = bool(p_data.get("suitcase_carried", false))
	carried_world_object = String(p_data.get("carried_world_object", ""))
	notebook = p_data.get("notebook", {}).duplicate(true)
	current_manifest = p_data.get("current_manifest", {}).duplicate(true)
	_next_item_uid = maxi(1, int(p_data.get("next_item_uid", 1)))
	return {"ok": true}
