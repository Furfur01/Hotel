class_name HotelFloor
extends Node3D

signal floor_built(floor: HotelFloor)

const TILE := 2.0
const HALF := 1.0
const WALL_H := 3.0
const GRID := 49
const LR := 3
const MAP_MARGIN := 2
const CORRIDOR_CLEARANCE := 4
const PRIMARY_TRUNK := 7
const CORR_MIN := 115
const CORR_BUDGET := 220
const MIN_LOOPS := 3
const MAX_LOOPS := 6
const LOOP_MIN_GAP := 3
const LOOP_MAX_GAP := 12
const MIN_GUEST_ROOMS := 5
const MAX_GUEST_ROOMS := 14
const FUNCTION_ROOM_TYPES := ["storage", "laundry", "maintenance", "security", "service_elevator"]
const MIN_ROOMS := 10
const MAX_ROOMS := 19
const EARLY_DAY_GUEST_ROOMS := 5
const EARLY_DAY_TOTAL_ROOMS := 10
const GENERATION_ATTEMPTS := 12
const MAP_PIXEL_SCALE := 3
const WORLD_ITEM_TEXTURE_DIR := "res://assets/icons/world/"

enum Cell { WALL, CORRIDOR, ROOM, LOBBY }

const _Kit = preload("res://modules.gd")
const _Inter = preload("res://interactable.gd")
const _RunState = preload("res://game_state.gd")

@export var generation_seed: int = -1

var managed_mode := false
var day_index := 1
var controller: Node = null
var day_manifest: Dictionary = {}

var GW := GRID
var GH := GRID
var grid: Array = []
var map_seed := 0
var corridor_count := 0
var loop_count := 0
var _last_loop_tiles := 0
## A 24-tile promenade keeps the floor spacious at player scale while making
## the 35-second exhausted body-carry budget geometrically enforceable.
var _ring_min := 12
var _ring_max := GRID - 13
var _missing_spoke := Vector2i.ZERO

var kit
var lights: Array = []
var rooms: Array = []
var door_spots: Array = []
var door_tiles: Dictionary = {}
var room_descriptors: Array = []
var room_by_id: Dictionary = {}
var descriptor_by_id: Dictionary = {}
var door_nodes: Dictionary = {}
var room_nodes: Dictionary = {}
var gameplay_nodes: Node3D
var room_runtime: Dictionary = {}
var previous_room_id := ""
var pickup_nodes: Array[Node3D] = []
var hazard_nodes: Array[Node3D] = []
var slippery_nodes: Array[Node3D] = []
var _world_item_texture_cache: Dictionary = {}

var lc: Vector2i
var lobby_rect: Rect2i
var lobby_exits: Array = []
var lobby_bands: Dictionary = {}
var lobby_collapsed := false
var exited_lobby := false
var steps_after := 0
var turned := false
var prev_dir: Vector2i = Vector2i.ZERO
var last_cell: Vector2i = Vector2i(-1, -1)
var player: Node3D

var elev_cell: Vector2i = Vector2i(-1, -1)
var elev_dir: Vector2i = Vector2i(1, 0)

var audio_player: AudioStreamPlayer
var generator: AudioStreamGenerator
var phase60 := 0.0
var phase120 := 0.0

func _ready() -> void:
	_generate_layout()
	_assign_room_metadata()
	_pick_elevator()
	print("GEN seed=", map_seed, " corridors=", corridor_count, " loops=", loop_count, " rooms=", rooms.size(), " elev=", elev_cell)
	if OS.get_cmdline_user_args().has("--map-preview"):
		_save_map_preview()
		get_tree().quit()
		return
	kit = _Kit.new()
	kit.setup()
	_build()
	_build_environment()
	if DisplayServer.get_name() != "headless":
		_setup_audio()
	if managed_mode:
		if controller != null and controller.has_method("build_day_manifest"):
			day_manifest = controller.build_day_manifest(room_descriptors, map_seed)
		_apply_day_manifest()
		_build_gameplay_markers()
		floor_built.emit(self)
		if controller != null and controller.has_method("on_floor_ready"):
			controller.on_floor_ready(self)
	else:
		_spawn_player()


func _exit_tree() -> void:
	# Release the generator playback before whole floors are destroyed between
	# days and before headless test shutdown.
	if audio_player != null:
		audio_player.stop()
		audio_player.stream = null
	generator = null


func _generate_layout() -> void:
	randomize()
	var base_seed := generation_seed if generation_seed >= 0 else randi()
	var best: Dictionary = {}
	var best_score := -1
	var accepted := false
	for attempt in range(GENERATION_ATTEMPTS):
		var candidate_seed: int = base_seed + attempt * 7919
		seed(candidate_seed)
		_init_grid()
		_gen_lobby()
		var carved := _grow_corridors()
		var added_loops := _add_loop_connections(randi_range(MIN_LOOPS, MAX_LOOPS))
		carved += _last_loop_tiles
		var target_room_count := EARLY_DAY_TOTAL_ROOMS if day_index <= 2 else randi_range(MIN_ROOMS, MAX_ROOMS)
		_gen_rooms(target_room_count)
		var score := carved + rooms.size() * 12 + added_loops * 40
		if score > best_score:
			best_score = score
			best = {
				"seed": candidate_seed,
				"corridors": carved,
				"loops": added_loops,
				"grid": grid.duplicate(true),
				"rooms": rooms.duplicate(true),
				"door_spots": door_spots.duplicate(true),
				"door_tiles": door_tiles.duplicate(true),
			}
		if carved >= CORR_MIN and added_loops >= MIN_LOOPS and rooms.size() >= target_room_count and _validate_layout():
			map_seed = candidate_seed
			corridor_count = carved
			loop_count = added_loops
			accepted = true
			break
	if not accepted:
		map_seed = best["seed"]
		corridor_count = best["corridors"]
		loop_count = best["loops"]
		grid = best["grid"]
		rooms = best["rooms"]
		door_spots = best["door_spots"]
		door_tiles = best["door_tiles"]
		push_warning("Map generation used the best fallback layout after %d attempts." % GENERATION_ATTEMPTS)
	seed(map_seed ^ 0x5F3759DF)

func _process(delta: float) -> void:
	_flicker(delta)
	_fill_hum()
	if not managed_mode:
		_update_lobby_collapse()
	else:
		_check_night_hazards()

func _init_grid() -> void:
	grid = []
	for y in range(GH):
		var row := []
		row.resize(GW)
		row.fill(Cell.WALL)
		grid.append(row)

func _in(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < GW and y < GH

func _gen_lobby() -> void:
	lc = Vector2i(GW / 2, GH / 2)
	lobby_rect = Rect2i(lc.x - LR, lc.y - LR, LR * 2 + 1, LR * 2 + 1)
	for y in range(lobby_rect.position.y, lobby_rect.end.y):
		for x in range(lobby_rect.position.x, lobby_rect.end.x):
			grid[y][x] = Cell.LOBBY
	lobby_bands = {}
	for i in range(lobby_rect.position.x, lobby_rect.end.x):
		lobby_bands[Vector2i(i, lc.y)] = true
	for j in range(lobby_rect.position.y, lobby_rect.end.y):
		lobby_bands[Vector2i(lc.x, j)] = true
	lobby_exits = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var edge = lc + d * LR
		lobby_exits.append({"d": d, "edge": edge})

func _can_carve(q: Vector2i, exempt: Vector2i, travel_dir: Vector2i) -> String:
	if not _in(q.x, q.y):
		return "no"
	if q.x <= MAP_MARGIN or q.x >= GW - 1 - MAP_MARGIN or q.y <= MAP_MARGIN or q.y >= GH - 1 - MAP_MARGIN:
		return "no"
	if lobby_rect.grow(1).has_point(q):
		return "no"
	var c = grid[q.y][q.x]
	if c == Cell.CORRIDOR:
		return "connect"
	if c != Cell.WALL:
		return "no"
	var perps = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for p in perps:
		var nb = q + p
		if not _in(nb.x, nb.y):
			continue
		var g = grid[nb.y][nb.x]
		if g == Cell.CORRIDOR and nb != exempt:
			return "no"
	var lateral := Vector2i(-travel_dir.y, travel_dir.x)
	for distance in range(1, CORRIDOR_CLEARANCE + 1):
		for side in [-1, 1]:
			var nb: Vector2i = q + lateral * distance * side
			if not _in(nb.x, nb.y):
				continue
			if grid[nb.y][nb.x] == Cell.CORRIDOR and nb != exempt:
				return "no"
	return "ok"


func _grow_corridors() -> int:
	## A deliberately sparse circulation plan: one large perimeter promenade and
	## three separated lobby spokes.  Every spoke already has an alternate route
	## through the other two, so the playable floor is not a corridor tree.
	var carved := 0
	for x in range(_ring_min, _ring_max + 1):
		carved += _set_corridor(Vector2i(x, _ring_min))
		carved += _set_corridor(Vector2i(x, _ring_max))
	for y in range(_ring_min + 1, _ring_max):
		carved += _set_corridor(Vector2i(_ring_min, y))
		carved += _set_corridor(Vector2i(_ring_max, y))

	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	directions.shuffle()
	_missing_spoke = directions.pop_back()
	for direction: Vector2i in directions:
		carved += _carve_spoke(direction)
	return carved


func _add_loop_connections(wanted: int) -> int:
	_last_loop_tiles = 0
	var connected := 3
	if connected < wanted and _missing_spoke != Vector2i.ZERO:
		_last_loop_tiles += _carve_spoke(_missing_spoke)
		connected += 1
	var cross_rows := [_ring_min + 7, _ring_max - 7]
	for row in cross_rows:
		if connected >= wanted:
			break
		for x in range(_ring_min, _ring_max + 1):
			_last_loop_tiles += _set_corridor(Vector2i(x, row))
		connected += 1
	return connected


func _set_corridor(cell: Vector2i) -> int:
	if not _in(cell.x, cell.y) or grid[cell.y][cell.x] != Cell.WALL:
		return 0
	grid[cell.y][cell.x] = Cell.CORRIDOR
	return 1


func _carve_spoke(direction: Vector2i) -> int:
	var carved := 0
	var position: Vector2i = lc + direction * LR
	var ring_target := lc
	if direction.x > 0:
		ring_target.x = _ring_max
	elif direction.x < 0:
		ring_target.x = _ring_min
	elif direction.y > 0:
		ring_target.y = _ring_max
	else:
		ring_target.y = _ring_min
	while position != ring_target:
		position += direction
		carved += _set_corridor(position)
	return carved


func _can_build_loop(start: Vector2i, finish: Vector2i, cells: Array) -> bool:
	if grid[start.y][start.x] != Cell.CORRIDOR or grid[finish.y][finish.x] != Cell.CORRIDOR:
		return false
	var direction: Vector2i = (finish - start).sign()
	var lateral := Vector2i(-direction.y, direction.x)
	for cell: Vector2i in cells:
		if grid[cell.y][cell.x] != Cell.WALL or lobby_rect.grow(4).has_point(cell):
			return false
		for side in [-1, 1]:
			var neighbor: Vector2i = cell + lateral * side
			if _in(neighbor.x, neighbor.y) and grid[neighbor.y][neighbor.x] == Cell.CORRIDOR:
				return false
	return true


func _gen_rooms(target_room_count: int = -1) -> void:
	rooms = []
	door_spots = []
	door_tiles = {}
	if target_room_count < 0:
		target_room_count = EARLY_DAY_TOTAL_ROOMS if day_index <= 2 else randi_range(MIN_ROOMS, MAX_ROOMS)
	var cells := []
	for y in range(1, GH - 1):
		for x in range(1, GW - 1):
			if grid[y][x] == Cell.CORRIDOR:
				cells.append(Vector2i(x, y))
	cells.shuffle()
	for c in cells:
		if rooms.size() >= target_room_count:
			break
		if lobby_rect.grow(3).has_point(c) or randf() > 0.58:
			continue
		var dirs := _room_side_directions(c)
		if dirs.is_empty():
			continue
		dirs.shuffle()
		for d in dirs:
			var w = c + d
			if not _in(w.x, w.y) or grid[w.y][w.x] != Cell.WALL:
				continue
			var kind = 1 if randf() < 0.13 else 0
			var depth = 3 if kind == 1 else 2
			var hw = 2 if kind == 1 else 1
			if not _room_fits(w, d, depth, hw):
				kind = 0
				depth = 2
				hw = 1
				if not _room_fits(w, d, depth, hw):
					continue
			var carved_cells := _carve_room(w, d, depth, hw)
			var n = Vector2i(-d.x, -d.y)
			var center = cell_pos(w.x, w.y) + Vector3(d.x * (depth - 1) / 2.0 * TILE, 0.0, d.y * (depth - 1) / 2.0 * TILE)
			var stable_key := "X%02dY%02dD%d%d" % [c.x, c.y, d.x + 1, d.y + 1]
			door_spots.append({"tile": w, "corridor": c, "dir": n, "kind": kind, "stable_key": stable_key})
			door_tiles[c] = true
			rooms.append({
				"center": center,
				"kind": kind,
				"door_dir": n,
				"door_tile": w,
				"corridor_tile": c,
				"cells": carved_cells,
				"depth": depth,
				"half_width": hw,
				"stable_key": stable_key,
			})
			break


func _assign_room_metadata() -> void:
	room_descriptors = []
	room_by_id = {}
	descriptor_by_id = {}
	if rooms.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map_seed) ^ 0x31C0FFEE ^ (day_index * 104729)
	var function_by_index := _select_function_room_indices(rng)
	var sequence_by_index: Dictionary = {}
	for wing_name in ["E", "W", "N", "S"]:
		var wing_indices: Array[int] = []
		for room_index in range(rooms.size()):
			if _wing_for_room(rooms[room_index]) == wing_name:
				wing_indices.append(room_index)
		wing_indices.sort_custom(func(a: int, b: int) -> bool:
			var a_corridor: Vector2i = rooms[a].corridor_tile
			var b_corridor: Vector2i = rooms[b].corridor_tile
			var a_key := a_corridor.y * GRID + a_corridor.x if wing_name in ["E", "W"] else a_corridor.x * GRID + a_corridor.y
			var b_key := b_corridor.y * GRID + b_corridor.x if wing_name in ["E", "W"] else b_corridor.x * GRID + b_corridor.y
			return a_key < b_key
		)
		for sequence in range(wing_indices.size()):
			sequence_by_index[wing_indices[sequence]] = sequence
	var wing_bases := {"E": 201, "W": 221, "N": 241, "S": 261}
	for i in range(rooms.size()):
		var room: Dictionary = rooms[i]
		var wing := _wing_for_room(room)
		var sequence: int = int(sequence_by_index.get(i, 0))
		var side_parity := 0
		var toward_corridor: Vector2i = room.door_dir
		if wing in ["E", "W"]:
			side_parity = 1 if toward_corridor.y > 0 else 0
		else:
			side_parity = 1 if toward_corridor.x > 0 else 0
		var number: int = int(wing_bases[wing]) + sequence * 2 + side_parity
		var room_type: String = function_by_index.get(i, "guest")
		var room_id := "D%02d_%s" % [day_index, String(room.stable_key)]
		var display_number := "%s-%03d" % [wing, number]
		if room_type != "guest":
			display_number = _function_room_label(room_type)
		room["room_id"] = room_id
		room["room_type"] = room_type
		room["wing"] = wing
		room["number"] = number
		room["display_number"] = display_number
		room["is_previous_room"] = false
		rooms[i] = room
		for cell: Vector2i in room.cells:
			room_by_id[cell] = room_id
		room_descriptors.append(room.duplicate(true))
		descriptor_by_id[room_id] = room.duplicate(true)
		for spot_index in range(door_spots.size()):
			if String(door_spots[spot_index].get("stable_key", "")) != String(room.stable_key):
				continue
			door_spots[spot_index]["room_id"] = room_id
			door_spots[spot_index]["room_type"] = room_type
			door_spots[spot_index]["display_number"] = display_number
			break


func _wing_for_room(room: Dictionary) -> String:
	var corridor: Vector2i = room.corridor_tile
	var delta := corridor - lc
	if abs(delta.y) > abs(delta.x):
		return "S" if delta.y >= 0 else "N"
	return "E" if delta.x >= 0 else "W"


func _select_function_room_indices(rng: RandomNumberGenerator) -> Dictionary:
	## Function rooms are gameplay infrastructure, not decoration.  Place the
	## service elevator near the lobby, put storage/laundry far apart on the
	## circulation graph, then farthest-point sample the remaining two rooms.
	## This prevents all disposal-capable rooms clustering in one hotel wing.
	var result: Dictionary = {}
	if rooms.size() < FUNCTION_ROOM_TYPES.size():
		return result
	var lobby_distances := _circulation_distance_map(lc)
	var service_index := 0
	var service_distance := 2147483647
	for index in range(rooms.size()):
		var corridor: Vector2i = rooms[index].corridor_tile
		var distance := int(lobby_distances.get(corridor, 2147483647))
		if distance < service_distance:
			service_distance = distance
			service_index = index
	result[service_index] = "service_elevator"

	var remaining: Array[int] = []
	for index in range(rooms.size()):
		if index != service_index:
			remaining.append(index)
	var best_a := remaining[0]
	var best_b := remaining[1]
	var best_coverage := 2147483647
	var best_separation := -1
	var room_distance_maps: Dictionary = {}
	for candidate in remaining:
		var candidate_cell := _cell_of_unclamped(rooms[candidate].center)
		room_distance_maps[candidate] = _walkable_distance_map(candidate_cell)
	for a_position in range(remaining.size()):
		var a_index := remaining[a_position]
		var a_distances: Dictionary = room_distance_maps[a_index]
		for b_position in range(a_position + 1, remaining.size()):
			var b_index := remaining[b_position]
			var b_distances: Dictionary = room_distance_maps[b_index]
			var coverage := 0
			for subject in range(rooms.size()):
				var subject_cell := _cell_of_unclamped(rooms[subject].center)
				coverage = maxi(coverage, mini(
					int(a_distances.get(subject_cell, 2147483647)),
					int(b_distances.get(subject_cell, 2147483647))
				))
			var b_cell := _cell_of_unclamped(rooms[b_index].center)
			var separation := int(a_distances.get(b_cell, -1))
			if coverage < best_coverage or (coverage == best_coverage and separation > best_separation):
				best_coverage = coverage
				best_separation = separation
				best_a = a_index
				best_b = b_index
	var swap_disposal := rng.randi_range(0, 1) == 1
	result[best_a] = "laundry" if swap_disposal else "storage"
	result[best_b] = "storage" if swap_disposal else "laundry"
	remaining.erase(best_a)
	remaining.erase(best_b)

	var chosen: Array[int] = [service_index, best_a, best_b]
	var support_types := ["maintenance", "security"]
	if rng.randi_range(0, 1) == 1:
		support_types.reverse()
	for support_type in support_types:
		var chosen_index := remaining[0]
		var chosen_score := -1
		for candidate in remaining:
			var candidate_cell: Vector2i = rooms[candidate].corridor_tile
			var distances := _circulation_distance_map(candidate_cell)
			var nearest_chosen := 2147483647
			for used_index in chosen:
				var used_cell: Vector2i = rooms[used_index].corridor_tile
				nearest_chosen = mini(nearest_chosen, int(distances.get(used_cell, 0)))
			if nearest_chosen > chosen_score:
				chosen_score = nearest_chosen
				chosen_index = candidate
		result[chosen_index] = support_type
		chosen.append(chosen_index)
		remaining.erase(chosen_index)
	return result


func _circulation_distance_map(start: Vector2i) -> Dictionary:
	var distances: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var here := queue[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next := here + direction
			if not _in(next.x, next.y) or grid[next.y][next.x] not in [Cell.CORRIDOR, Cell.LOBBY] or distances.has(next):
				continue
			distances[next] = int(distances[here]) + 1
			queue.append(next)
	return distances


func _walkable_distance_map(start: Vector2i) -> Dictionary:
	var distances: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var here := queue[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next := here + direction
			if not _is_walkable_cell(next) or distances.has(next):
				continue
			distances[next] = int(distances[here]) + 1
			queue.append(next)
	return distances


func _function_room_label(room_type: String) -> String:
	match room_type:
		"storage": return "收纳间"
		"laundry": return "洗衣 / 布草"
		"maintenance": return "维修 / 配电"
		"security": return "安保 / 档案"
		"service_elevator": return "服务电梯"
	return room_type


func _room_side_directions(c: Vector2i) -> Array[Vector2i]:
	var links: Array[Vector2i] = []
	for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var neighbor := c + d
		if _in(neighbor.x, neighbor.y) and grid[neighbor.y][neighbor.x] in [Cell.CORRIDOR, Cell.LOBBY]:
			links.append(d)
	if links.size() != 2 or links[0] + links[1] != Vector2i.ZERO:
		return []
	var axis := links[0]
	var side := Vector2i(-axis.y, axis.x)
	return [side, -side]

func _room_fits(w: Vector2i, d: Vector2i, depth: int, hw: int) -> bool:
	var perp = Vector2i(-d.y, d.x)
	for i in range(0, depth + 1):
		for j in range(-(hw + 1), hw + 2):
			var here = w + d * i + perp * j
			if not _in(here.x, here.y):
				return false
			if here.x <= MAP_MARGIN or here.x >= GW - 1 - MAP_MARGIN or here.y <= MAP_MARGIN or here.y >= GH - 1 - MAP_MARGIN:
				return false
			if grid[here.y][here.x] != Cell.WALL:
				return false
	return true

func _carve_room(w: Vector2i, d: Vector2i, depth: int, hw: int) -> Array[Vector2i]:
	var perp = Vector2i(-d.y, d.x)
	var carved: Array[Vector2i] = []
	for i in range(0, depth):
		for j in range(-hw, hw + 1):
			var here = w + d * i + perp * j
			grid[here.y][here.x] = Cell.ROOM
			carved.append(here)
	return carved


func _validate_layout() -> bool:
	for y in range(GH):
		for x in range(GW):
			if x <= MAP_MARGIN or x >= GW - 1 - MAP_MARGIN or y <= MAP_MARGIN or y >= GH - 1 - MAP_MARGIN:
				if grid[y][x] != Cell.WALL:
					return false

	var allowed_exits: Dictionary = {}
	for ex in lobby_exits:
		allowed_exits[ex.edge + ex.d] = true
	var halo := lobby_rect.grow(1)
	for y in range(halo.position.y, halo.end.y):
		for x in range(halo.position.x, halo.end.x):
			var p := Vector2i(x, y)
			if grid[y][x] == Cell.CORRIDOR and not allowed_exits.has(p):
				return false

	var seen: Dictionary = {lc: true}
	var queue: Array[Vector2i] = [lc]
	var cursor := 0
	while cursor < queue.size():
		var here := queue[cursor]
		cursor += 1
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = here + d
			if _in(next.x, next.y) and _is_walkable_cell(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	var walkable_count := 0
	for y in range(GH):
		for x in range(GW):
			if grid[y][x] != Cell.WALL:
				walkable_count += 1
	if seen.size() != walkable_count:
		return false

	for spot in door_spots:
		var tile: Vector2i = spot.tile
		var toward_corridor: Vector2i = spot.dir
		if grid[tile.y][tile.x] != Cell.ROOM:
			return false
		var room_side := tile - toward_corridor
		var corridor_side := tile + toward_corridor
		if not _in(room_side.x, room_side.y) or grid[room_side.y][room_side.x] != Cell.ROOM:
			return false
		if not _in(corridor_side.x, corridor_side.y) or not _is_walkable_cell(corridor_side):
			return false
	return true


func _is_walkable_cell(cell: Vector2i) -> bool:
	return _in(cell.x, cell.y) and grid[cell.y][cell.x] != Cell.WALL


func _pick_elevator() -> void:
	var distance: Dictionary = {lc: 0}
	var queue: Array[Vector2i] = [lc]
	var cursor := 0
	while cursor < queue.size():
		var here := queue[cursor]
		cursor += 1
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = here + d
			if _is_walkable_cell(next) and not distance.has(next):
				distance[next] = distance[here] + 1
				queue.append(next)

	var best := Vector2i(-1, -1)
	var best_dir := Vector2i.ZERO
	var best_score := -1
	for y in range(MAP_MARGIN + 2, GH - MAP_MARGIN - 2):
		for x in range(MAP_MARGIN + 2, GW - MAP_MARGIN - 2):
			var cell := Vector2i(x, y)
			if grid[y][x] != Cell.CORRIDOR or door_tiles.has(cell) or not distance.has(cell):
				continue
			var wall_dir := _elevator_wall_direction(cell)
			if wall_dir == Vector2i.ZERO:
				continue
			var open_neighbors := 0
			for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				if _is_walkable_cell(cell + d):
					open_neighbors += 1
			if open_neighbors > 2:
				continue
			var score: int = distance[cell] + (8 if open_neighbors == 1 else 0)
			if score > best_score:
				best_score = score
				best = cell
				best_dir = wall_dir
	elev_cell = best
	elev_dir = best_dir if best_dir != Vector2i.ZERO else Vector2i.RIGHT


func _elevator_wall_direction(cell: Vector2i) -> Vector2i:
	for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var wall: Vector2i = cell + d
		var behind: Vector2i = wall + d
		if _in(behind.x, behind.y) and grid[wall.y][wall.x] == Cell.WALL and grid[behind.y][behind.x] == Cell.WALL:
			return d
	return Vector2i.ZERO

func _save_map_preview() -> void:
	var img := _create_map_image(12)
	img.save_png("res://map_preview.png")


func _create_map_texture(include_debug_truth: bool = false) -> ImageTexture:
	return ImageTexture.create_from_image(_create_map_image(MAP_PIXEL_SCALE, include_debug_truth))


func _create_map_image(px: int, include_debug_truth: bool = false) -> Image:
	var img := Image.create_empty(GW * px, GH * px, false, Image.FORMAT_RGBA8)
	var c_wall := Color(0.17, 0.145, 0.105, 1.0)
	var c_void := Color(0.025, 0.021, 0.017, 1.0)
	var c_corr := Color(0.55, 0.43, 0.22, 1.0)
	var c_room := Color(0.38, 0.27, 0.16, 1.0)
	var c_lobby := Color(0.77, 0.68, 0.44, 1.0)
	for y in range(GH):
		for x in range(GW):
			var col: Color
			match grid[y][x]:
				Cell.WALL:
					col = c_wall if _touches_empty(x, y) or x == 0 or x == GW - 1 or y == 0 or y == GH - 1 else c_void
				Cell.CORRIDOR:
					col = c_corr
				Cell.ROOM:
					col = c_room
				Cell.LOBBY:
					col = c_lobby
			for dy in range(px):
				for dx in range(px):
					img.set_pixel(x * px + dx, y * px + dy, col)
	for spot in door_spots:
		_mark_door(img, spot, px)
	_mark(img, lc.x, lc.y, Color(0.82, 0.74, 0.48), px)
	if elev_cell.x >= 0:
		_mark(img, elev_cell.x, elev_cell.y, Color(0.34, 0.62, 0.7), px)
	if managed_mode and include_debug_truth:
		_draw_debug_truth(img, px)
	return img


func _mark_door(img: Image, spot: Dictionary, px: int) -> void:
	var tile: Vector2i = spot.tile
	var direction: Vector2i = spot.dir
	var center_x := tile.x * px + px / 2
	var center_y := tile.y * px + px / 2
	var half_width := maxi(0, px / 6)
	var color := Color(0.86, 0.62, 0.24, 1.0)
	if direction.x != 0:
		var edge_x := (tile.x + 1) * px - 1 if direction.x > 0 else tile.x * px
		for offset in range(-half_width, half_width + 1):
			img.set_pixel(edge_x, clampi(center_y + offset, 0, img.get_height() - 1), color)
	else:
		var edge_y := (tile.y + 1) * px - 1 if direction.y > 0 else tile.y * px
		for offset in range(-half_width, half_width + 1):
			img.set_pixel(clampi(center_x + offset, 0, img.get_width() - 1), edge_y, color)


func _mark(img: Image, cx: int, cy: int, col: Color, px: int) -> void:
	for dy in range(px):
		for dx in range(px):
			img.set_pixel(cx * px + dx, cy * px + dy, col)

func cell_pos(cx: int, cy: int) -> Vector3:
	return Vector3(cx * TILE + HALF - GW * TILE * 0.5, 0.0, cy * TILE + HALF - GH * TILE * 0.5)

func _build() -> void:
	door_nodes = {}
	room_nodes = {}
	_add_floor_collision()
	_add_boundary_collision()
	for y in range(GH):
		for x in range(GW):
			var c = grid[y][x]
			var p = cell_pos(x, y)
			if c == Cell.WALL:
				if _touches_empty(x, y) or x == 0 or x == GW - 1 or y == 0 or y == GH - 1:
					var w = kit.wall_segment()
					w.position = p
					add_child(w)
			else:
				var fl = kit.floor_tile()
				fl.position = p
				add_child(fl)
				var ce = kit.ceiling_tile()
				ce.position = p
				add_child(ce)
	for spot in door_spots:
		var t: Vector2i = spot.tile
		var du = kit.door_unit(spot.dir)
		du.position = cell_pos(t.x, t.y) + Vector3(spot.dir.x * HALF, 0.0, spot.dir.y * HALF)
		du.name = "Door_%s" % String(spot.get("room_id", "unknown"))
		if managed_mode:
			du.host = self
			du.data = spot.duplicate(true)
		add_child(du)
		if spot.has("room_id"):
			door_nodes[spot.room_id] = du
			_add_door_label(du, spot)
	for rm in rooms:
		var mod = kit.room_module(rm.kind, rm.door_dir) if String(rm.room_type) == "guest" else kit.function_room_module(String(rm.room_type), rm.kind, rm.door_dir)
		mod.position = rm.center
		mod.name = "Room_%s" % String(rm.get("room_id", "unknown"))
		add_child(mod)
		if rm.has("room_id"):
			room_nodes[rm.room_id] = mod
	_build_lobby_decor()
	_build_range_signs()
	_place_corridor_decor()
	if elev_cell.x >= 0:
		var ev = kit.elevator_module()
		ev.position = cell_pos(elev_cell.x, elev_cell.y) + Vector3(elev_dir.x * 0.94, 0.0, elev_dir.y * 0.94)
		ev.rotation.y = kit._ry(elev_dir)
		add_child(ev)
	lights = kit.flicker


func _add_door_label(door: Node3D, spot: Dictionary) -> void:
	var direction: Vector2i = spot.get("dir", Vector2i.DOWN)
	var plaque := MeshInstance3D.new()
	plaque.name = "RoomPlateGlow"
	var plaque_mesh := BoxMesh.new()
	plaque_mesh.size = Vector3(0.035, 0.32, 0.78) if direction.x != 0 else Vector3(0.78, 0.32, 0.035)
	plaque.mesh = plaque_mesh
	plaque.position = Vector3(direction.x * 0.075, 2.32, direction.y * 0.075)
	var plaque_material := StandardMaterial3D.new()
	plaque_material.albedo_color = Color(0.055, 0.075, 0.060)
	plaque_material.metallic = 0.68
	plaque_material.roughness = 0.34
	plaque_material.emission_enabled = true
	plaque_material.emission = Color(0.88, 0.57, 0.16)
	plaque_material.emission_energy_multiplier = 1.25
	plaque.material_override = plaque_material
	door.add_child(plaque)

	var label := Label3D.new()
	label.name = "RoomPlateText"
	label.text = String(spot.get("display_number", "?"))
	label.font_size = 27
	label.pixel_size = 0.008
	label.modulate = Color(1.0, 0.82, 0.36)
	label.outline_modulate = Color(0.03, 0.08, 0.055)
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position = Vector3(direction.x * 0.10, 2.32, direction.y * 0.10)
	door.add_child(label)


func set_room_plate_state(room_id: String, _conclusion: String) -> void:
	var door: Node3D = door_nodes.get(room_id)
	if door == null:
		return
	var glow := Color(0.88, 0.57, 0.16)
	var plaque := door.get_node_or_null("RoomPlateGlow") as MeshInstance3D
	if plaque != null and plaque.material_override is StandardMaterial3D:
		var material := plaque.material_override as StandardMaterial3D
		material.emission = glow
		material.emission_energy_multiplier = 1.25
	var label := door.get_node_or_null("RoomPlateText") as Label3D
	if label != null:
		label.modulate = glow.lightened(0.24)


func _apply_day_manifest() -> void:
	room_runtime = {}
	var states: Dictionary = day_manifest.get("rooms", day_manifest)
	for descriptor: Dictionary in room_descriptors:
		var room_id: String = descriptor.room_id
		var state: Dictionary = states.get(room_id, {})
		if descriptor.room_type != "guest":
			state["locked"] = true
		state["room_id"] = room_id
		state["room_type"] = descriptor.room_type
		state["cabinet_armed"] = false
		state["inspected"] = false
		state["registered"] = false
		room_runtime[room_id] = state
		var door: Node = door_nodes.get(room_id)
		if door != null:
			door.data["locked"] = bool(state.get("locked", false))
			door.data["room_type"] = descriptor.room_type


func _build_gameplay_markers() -> void:
	gameplay_nodes = Node3D.new()
	gameplay_nodes.name = "Gameplay"
	add_child(gameplay_nodes)
	for descriptor: Dictionary in room_descriptors:
		var room_id: String = descriptor.room_id
		var center: Vector3 = descriptor.center
		if descriptor.room_type == "guest":
			var toward: Vector2i = descriptor.door_dir
			var toward3 := Vector3(toward.x, 0.0, toward.y)
			var bed_pos := center - toward3 * 0.9 + Vector3(0.0, 0.72, 0.0)
			_make_marker("bed", bed_pos, {"room_id": room_id}, Color(0.72, 0.55, 0.24, 0.55), Vector3(0.55, 0.35, 0.55))
			var side := Vector3(-toward.y, 0.0, toward.x)
			var cabinet_pos: Vector3 = center + side * 1.25 + Vector3(0.0, 0.9, 0.0)
			_make_marker("cabinet", cabinet_pos, {"room_id": room_id}, Color(0.35, 0.24, 0.12, 0.35), Vector3(0.45, 1.4, 0.35))
		else:
			_make_marker("facility", _room_clear_anchor(descriptor, -0.42) + Vector3(0.0, 0.65, 0.0), {
				"room_id": room_id,
				"room_type": descriptor.room_type,
			}, Color(0.26, 0.42, 0.46, 0.5), Vector3(0.5, 0.45, 0.5))
	var lobby_pos := cell_pos(lc.x, lc.y)
	_make_marker("records", lobby_pos + Vector3(0.0, 1.15, -1.7), {}, Color(0.66, 0.48, 0.2, 0.65), Vector3(0.9, 0.45, 0.25))
	_build_disposal_markers()
	_build_item_pickups()


func _build_disposal_markers() -> void:
	var disposal_ids: Array = day_manifest.get("disposal_room_ids", [])
	for room_id_variant in disposal_ids:
		var room_id := String(room_id_variant)
		var descriptor: Dictionary = descriptor_by_id.get(room_id, {})
		if descriptor.is_empty():
			continue
		var node := _make_marker("disposal", _room_clear_anchor(descriptor, 0.48) + Vector3(0.0, 0.75, 0.0), {"room_id": room_id}, Color(0.42, 0.12, 0.1, 0.75), Vector3(0.7, 0.8, 0.35))
		node.add_to_group("disposal")


func _make_marker(
	marker_kind: String,
	world_position: Vector3,
	marker_data: Dictionary,
	color: Color,
	size: Vector3,
	sprite_texture: Texture2D = null,
	sprite_height: float = 0.0,
	sprite_y_offset: float = 0.0
) -> HotelInteractable:
	var root := _Inter.new() as HotelInteractable
	root.kind = marker_kind
	root.host = self
	root.data = marker_data.duplicate(true)
	root.position = world_position
	root.name = "%s_%s" % [marker_kind.capitalize(), str(marker_data.get("room_id", gameplay_nodes.get_child_count()))]
	if sprite_texture != null and sprite_height > 0.0:
		var sprite := Sprite3D.new()
		sprite.name = "WorldItemSprite"
		sprite.texture = sprite_texture
		sprite.pixel_size = sprite_height / maxf(1.0, float(sprite_texture.get_height()))
		sprite.position.y = sprite_y_offset
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.double_sided = true
		sprite.no_depth_test = false
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		root.add_child(sprite)
	else:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = material
		root.add_child(mesh)
	var area := Area3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	area.add_child(collision)
	root.add_child(area)
	gameplay_nodes.add_child(root)
	return root


func _world_item_texture(item_id: String) -> Texture2D:
	if _world_item_texture_cache.has(item_id):
		return _world_item_texture_cache[item_id] as Texture2D
	var path := WORLD_ITEM_TEXTURE_DIR + item_id + ".png"
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	_world_item_texture_cache[item_id] = texture
	return texture


func get_interaction_options(source: HotelInteractable, _player: Node) -> Array:
	var options: Array = []
	var room_id := String(source.data.get("room_id", ""))
	match source.kind:
		"door":
			options.append({"id": "observe", "label": "观察门口", "duration": 1.0})
			options.append({"id": "listen", "label": "贴门倾听", "duration": 2.0})
			options.append({"id": "knock", "label": "敲门等待", "duration": 3.0})
			if source.door_open:
				options.push_front({"id": "close_door", "label": "关门", "duration": 0.0})
			elif not bool(source.data.get("locked", false)):
				options.push_front({"id": "open_door", "label": "开门", "duration": 0.0})
			else:
				if _controller_has_item("lockpick"):
					options.append({"id": "unlock_lockpick", "label": "使用撬锁组", "duration": 3.0})
				if _controller_has_item("pry_bar"):
					options.append({"id": "unlock_prybar", "label": "使用扁撬", "duration": 1.0})
				if _controller_has_item("staff_card"):
					options.append({"id": "unlock_pass", "label": "使用工作卡", "duration": 0.5})
				if String(source.data.get("room_type", "guest")) != "guest" and _controller_has_item("electrician_kit"):
					options.append({"id": "unlock_electrician", "label": "接通电子门锁", "duration": 2.0})
		"bed":
			options.append({"id": "settle", "label": "在这里住下", "duration": 1.0})
			if _controller_has_item("ratchet_strap"):
				options.append({"id": "barricade_settle", "label": "绑门并住下", "duration": 3.0})
		"cabinet":
			if bool(room_runtime.get(room_id, {}).get("cabinet_armed", false)):
				options.append({"id": "cabinet_ready", "label": "坠柜已准备", "duration": 0.0})
			elif _controller_is_daytime():
				options.append({"id": "arm_cabinet", "label": "松动坠柜", "duration": 12.0})
				if _controller_has_item("pry_bar"):
					options.append({"id": "arm_cabinet_pry", "label": "用扁撬松动", "duration": 4.0})
		"records":
			options.append({"id": "read_records", "label": "查阅不完整登记", "duration": 3.0})
		"facility":
			options.append({"id": "search_facility", "label": "搜查%s" % _function_room_label(String(source.data.get("room_type", ""))), "duration": 2.0})
		"disposal":
			options.append({"id": "dispose_body", "label": "投入尸体", "duration": _RunState.BODY_DISPOSE_SECONDS})
		"pickup":
			options.append({"id": "pickup_item", "label": "拾取%s" % String(source.data.get("display_name", "物品")), "duration": 0.0})
		"suitcase":
			options.append({"id": "pickup_suitcase", "label": "搬起旅行箱", "duration": 0.0})
			options.append({"id": "open_suitcase", "label": "整理旅行箱", "duration": 0.0})
		"corpse":
			options.append({"id": "wrap_corpse", "label": "用棉被裹尸", "duration": _RunState.CORPSE_WRAP_SECONDS})
			if _controller_has_item("ratchet_strap"):
				options.append({"id": "wrap_corpse_strap", "label": "用绑带裹尸", "duration": _RunState.CORPSE_WRAP_FAST_SECONDS})
		"wrapped_corpse":
			options.append({"id": "carry_corpse", "label": "搬起尸体", "duration": 0.0})
		"stain":
			options.append({"id": "clean_stain", "label": "用水和毛巾清理", "duration": _RunState.STAIN_CLEAN_SECONDS})
			if _controller_has_item("industrial_cleaner"):
				options.append({"id": "clean_stain_spray", "label": "使用去污剂", "duration": _RunState.STAIN_CLEAN_FAST_SECONDS})
	return options


func handle_interaction(source: HotelInteractable, action_id: String, player_node: Node) -> void:
	if action_id == "open_door":
		source.set_door_open(true)
		return
	if action_id == "close_door":
		source.set_door_open(false)
		return
	if controller != null and controller.has_method("perform_floor_action"):
		controller.perform_floor_action(self, source, action_id, player_node)


func _controller_has_item(item_id: String) -> bool:
	return controller != null and controller.has_method("has_item") and controller.has_item(item_id)


func _controller_is_daytime() -> bool:
	return controller != null and controller.has_method("is_daytime") and controller.is_daytime()


func configure_managed(p_controller: Node, p_day_index: int, p_seed: int, p_previous_room_id := "") -> void:
	managed_mode = true
	controller = p_controller
	day_index = p_day_index
	generation_seed = p_seed
	previous_room_id = p_previous_room_id


func get_lobby_spawn_position() -> Vector3:
	var point := cell_pos(lc.x, lc.y)
	return Vector3(point.x, 0.08, point.z)


func get_room_spawn_position(room_id: String) -> Vector3:
	var descriptor: Dictionary = descriptor_by_id.get(room_id, {})
	if descriptor.is_empty():
		return get_lobby_spawn_position()
	return _room_clear_anchor(descriptor, 0.0) + Vector3(0.0, 0.08, 0.0)


func get_room_clear_position(room_id: String, side_offset := 0.0) -> Vector3:
	var descriptor: Dictionary = descriptor_by_id.get(room_id, {})
	if descriptor.is_empty():
		return get_lobby_spawn_position()
	return _room_clear_anchor(descriptor, side_offset) + Vector3(0.0, 0.08, 0.0)


func get_room_id_at_world(world_position: Vector3) -> String:
	return String(room_by_id.get(_cell_of_unclamped(world_position), ""))


func get_wing_at_world(world_position: Vector3) -> String:
	var cell := _cell_of_unclamped(world_position)
	var delta := cell - lc
	if delta == Vector2i.ZERO:
		return ""
	if abs(delta.y) > abs(delta.x):
		return "S" if delta.y > 0 else "N"
	return "E" if delta.x > 0 else "W"


func get_room_descriptor(room_id: String) -> Dictionary:
	return descriptor_by_id.get(room_id, {}).duplicate(true)


func get_guest_room_ids() -> Array[String]:
	var result: Array[String] = []
	for descriptor: Dictionary in room_descriptors:
		if String(descriptor.room_type) == "guest":
			result.append(String(descriptor.room_id))
	result.sort()
	return result


func get_function_room_id(room_type: String) -> String:
	var normalized := "security" if room_type == "security_archive" else room_type
	for descriptor: Dictionary in room_descriptors:
		if String(descriptor.room_type) == normalized:
			return String(descriptor.room_id)
	return ""


func set_previous_room(room_id: String) -> void:
	previous_room_id = room_id
	if descriptor_by_id.has(room_id):
		descriptor_by_id[room_id]["is_previous_room"] = true
		if room_runtime.has(room_id):
			room_runtime[room_id]["is_previous_room"] = true


func set_room_display_number(room_id: String, display_number: String) -> void:
	if not descriptor_by_id.has(room_id) or display_number.is_empty():
		return
	descriptor_by_id[room_id]["display_number"] = display_number
	var parsed_number := int(display_number.get_slice("-", 1))
	if parsed_number > 0:
		descriptor_by_id[room_id]["number"] = parsed_number
	for index in range(room_descriptors.size()):
		if String(room_descriptors[index].get("room_id", "")) == room_id:
			room_descriptors[index]["display_number"] = display_number
			if parsed_number > 0:
				room_descriptors[index]["number"] = parsed_number
			break
	for index in range(rooms.size()):
		if String(rooms[index].get("room_id", "")) == room_id:
			rooms[index]["display_number"] = display_number
			if parsed_number > 0:
				rooms[index]["number"] = parsed_number
			break
	for index in range(door_spots.size()):
		if String(door_spots[index].get("room_id", "")) == room_id:
			door_spots[index]["display_number"] = display_number
			break
	var door: HotelInteractable = door_nodes.get(room_id)
	if door != null:
		door.data["display_number"] = display_number
		for child in door.get_children():
			if child is Label3D:
				(child as Label3D).text = display_number
				break
	_build_range_signs()


func set_room_unlocked(room_id: String, unlocked := true) -> void:
	if room_runtime.has(room_id):
		room_runtime[room_id]["locked"] = not unlocked
	var door: HotelInteractable = door_nodes.get(room_id)
	if door != null:
		door.data["locked"] = not unlocked


func set_room_door_open(room_id: String, open: bool) -> void:
	var door: HotelInteractable = door_nodes.get(room_id)
	if door != null:
		door.set_door_open(open)


func seal_door(door: HotelInteractable, duration: float) -> void:
	if door == null or door.kind != "door":
		return
	door.data["sealed_until"] = float(Time.get_ticks_msec()) * 0.001 + maxf(duration, 0.0)
	door.set_door_open(false)
	door.set_enabled(false)


func ensure_npc_passage(from_world: Vector3, to_world: Vector3) -> bool:
	## Grid paths cross room thresholds, while the actual door leaf is physical.
	## Ordinary closed doors are pushed open by pursuers; a strapped door is the
	## only state which blocks that crossing, and only until its deadline.
	var from_cell := _nearest_walkable_cell(_cell_of_unclamped(from_world))
	var to_cell := _nearest_walkable_cell(_cell_of_unclamped(to_world))
	for spot in door_spots:
		var room_cell: Vector2i = spot.tile
		var corridor_cell: Vector2i = spot.corridor
		if not ((from_cell == room_cell and to_cell == corridor_cell) or (from_cell == corridor_cell and to_cell == room_cell)):
			continue
		var door: HotelInteractable = door_nodes.get(String(spot.get("room_id", "")))
		if door == null:
			return true
		var sealed_until := float(door.data.get("sealed_until", 0.0))
		if sealed_until > float(Time.get_ticks_msec()) * 0.001:
			return false
		if not door.door_open:
			door.set_door_open(true)
		return true
	return true


func is_room_door_open(room_id: String) -> bool:
	var door: HotelInteractable = door_nodes.get(room_id)
	return door != null and door.door_open


func get_room_runtime(room_id: String) -> Dictionary:
	return room_runtime.get(room_id, {})


func set_room_runtime_value(room_id: String, key: String, value: Variant) -> void:
	if room_runtime.has(room_id):
		room_runtime[room_id][key] = value


func get_patrol_points(offset := 0) -> PackedVector3Array:
	var candidates: Array[Vector2i] = []
	for x in range(_ring_min + 2, _ring_max - 1, 5):
		for y in [_ring_min, _ring_max]:
			var cell := Vector2i(x, y)
			if grid[cell.y][cell.x] == Cell.CORRIDOR:
				candidates.append(cell)
	for y in range(_ring_min + 2, _ring_max - 1, 5):
		for x in [_ring_min, _ring_max]:
			var cell := Vector2i(x, y)
			if grid[cell.y][cell.x] == Cell.CORRIDOR:
				candidates.append(cell)
	if candidates.is_empty():
		candidates.append(lc)
	var result := PackedVector3Array()
	var count := mini(10, candidates.size())
	for index in range(count):
		var cell: Vector2i = candidates[posmod(index * 3 + offset, candidates.size())]
		result.append(cell_pos(cell.x, cell.y) + Vector3(0.0, 0.08, 0.0))
	return result


func find_path_world(from_world: Vector3, to_world: Vector3) -> PackedVector3Array:
	var start := _nearest_walkable_cell(_cell_of_unclamped(from_world))
	var finish := _nearest_walkable_cell(_cell_of_unclamped(to_world))
	var result := PackedVector3Array()
	if start.x < 0 or finish.x < 0:
		return result
	var came_from: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size() and not came_from.has(finish):
		var here := queue[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next := here + direction
			if _is_walkable_cell(next) and not came_from.has(next):
				came_from[next] = here
				queue.append(next)
	if not came_from.has(finish):
		return result
	var reverse: Array[Vector2i] = []
	var step := finish
	while step != start:
		reverse.append(step)
		step = came_from[step]
	reverse.append(start)
	reverse.reverse()
	for cell: Vector2i in reverse:
		result.append(cell_pos(cell.x, cell.y) + Vector3(0.0, 0.08, 0.0))
	return result


func path_distance_world(from_world: Vector3, to_world: Vector3) -> float:
	var path := find_path_world(from_world, to_world)
	return INF if path.is_empty() else float(path.size() - 1) * TILE


func max_guest_distance_to_rooms(target_room_ids: Array) -> float:
	if target_room_ids.is_empty():
		return INF
	var maximum := 0.0
	for descriptor: Dictionary in room_descriptors:
		if String(descriptor.get("room_type", "")) != "guest":
			continue
		var nearest := INF
		for room_id_value in target_room_ids:
			var target: Dictionary = descriptor_by_id.get(String(room_id_value), {})
			if target.is_empty():
				continue
			nearest = minf(nearest, path_distance_world(descriptor.center, target.center))
		maximum = maxf(maximum, nearest)
	return maximum


func max_lobby_to_guest_distance() -> float:
	var maximum := 0.0
	var lobby_position := get_lobby_spawn_position()
	for descriptor: Dictionary in room_descriptors:
		if String(descriptor.get("room_type", "")) != "guest":
			continue
		var distance := path_distance_world(lobby_position, descriptor.center)
		if not is_inf(distance):
			maximum = maxf(maximum, distance)
	return maximum


func _nearest_walkable_cell(candidate: Vector2i) -> Vector2i:
	if _is_walkable_cell(candidate):
		return candidate
	for radius in range(1, 8):
		for y in range(candidate.y - radius, candidate.y + radius + 1):
			for x in range(candidate.x - radius, candidate.x + radius + 1):
				var cell := Vector2i(x, y)
				if _is_walkable_cell(cell):
					return cell
	return Vector2i(-1, -1)


func _build_item_pickups() -> void:
	pickup_nodes = []
	var spawns: Array = day_manifest.get("item_spawns", [])
	var guests := get_guest_room_ids()
	var guest_cursor := 0
	var public_cursor := 0
	var room_spawn_counts: Dictionary = {}
	for spawn_value in spawns:
		var spawn: Dictionary = spawn_value
		var item_id := String(spawn.get("item_id", ""))
		var zone := String(spawn.get("zone", spawn.get("room_type", "public")))
		var room_id := String(spawn.get("room_id", ""))
		if room_id.is_empty() and zone == "guest_room" and not guests.is_empty():
			room_id = guests[guest_cursor % guests.size()]
			guest_cursor += 1
		elif room_id.is_empty() and zone.begins_with("guest_room") and not guests.is_empty():
			room_id = guests[guest_cursor % guests.size()]
			guest_cursor += 1
		elif room_id.is_empty() and zone not in ["public", "public_corridor"]:
			room_id = get_function_room_id(zone)
		var position := get_lobby_spawn_position()
		if room_id.is_empty():
			var exit_data: Dictionary = lobby_exits[public_cursor % lobby_exits.size()]
			var cell: Vector2i = exit_data.edge + exit_data.d * 2
			position = cell_pos(cell.x, cell.y) + Vector3(0.0, 0.28, 0.0)
			public_cursor += 1
		else:
			var descriptor: Dictionary = descriptor_by_id.get(room_id, {})
			var room_slot := int(room_spawn_counts.get(room_id, 0))
			room_spawn_counts[room_id] = room_slot + 1
			var side_offsets := [-0.56, 0.0, 0.56]
			position = _room_clear_anchor(descriptor, float(side_offsets[room_slot % side_offsets.size()])) + Vector3(0.0, 0.22, 0.0)
		var marker := spawn_item_pickup(item_id, position, room_id)
		pickup_nodes.append(marker)


func spawn_item_pickup(item_id: String, world_position: Vector3, room_id := "", origin_anchor: Variant = null) -> HotelInteractable:
	var display_name := item_id
	if controller != null and controller.has_method("get_item_display_name"):
		display_name = controller.get_item_display_name(item_id)
	var resolved_origin: Vector3 = world_position if not (origin_anchor is Vector3) else origin_anchor
	var sprite_height := 0.66 if item_id == "folding_trap" else 0.56
	var sprite_y_offset := 0.12 if item_id == "folding_trap" else 0.08
	var marker := _make_marker("pickup", world_position, {
		"item_id": item_id,
		"display_name": display_name,
		"room_id": room_id,
		"origin_anchor": resolved_origin,
		"loose": true,
		"deployed": false,
	}, Color(0.72, 0.48, 0.14, 0.9), Vector3(0.34, 0.34, 0.34), _world_item_texture(item_id), sprite_height, sprite_y_offset)
	marker.add_to_group("loose_item")
	return marker


func spawn_suitcase(world_position: Vector3) -> HotelInteractable:
	var marker := _make_marker("suitcase", world_position + Vector3(0.0, 0.38, 0.0), {
		"origin_anchor": world_position + Vector3(0.0, 0.38, 0.0),
		"loose": true,
		"deployed": false,
	}, Color(0.30, 0.14, 0.075, 1.0), Vector3(0.72, 0.72, 0.38), _world_item_texture("suitcase"), 0.76, 0.0)
	marker.add_to_group("loose_item")
	return marker


func spawn_wrapped_corpse(world_position: Vector3) -> HotelInteractable:
	var marker := _make_marker("wrapped_corpse", world_position + Vector3(0.0, 0.28, 0.0), {
		"origin_anchor": world_position + Vector3(0.0, 0.28, 0.0),
		"loose": true,
		"deployed": false,
	}, Color(0.72, 0.68, 0.56, 1.0), Vector3(1.45, 0.42, 0.55))
	marker.add_to_group("loose_item")
	return marker


func spawn_corpse(world_position: Vector3) -> HotelInteractable:
	return _make_marker("corpse", world_position + Vector3(0.0, 0.25, 0.0), {}, Color(0.32, 0.08, 0.07, 1.0), Vector3(1.35, 0.38, 0.5))


func spawn_stain(world_position: Vector3) -> HotelInteractable:
	return _make_marker("stain", Vector3(world_position.x, 0.025, world_position.z), {}, Color(0.28, 0.015, 0.01, 0.86), Vector3(1.15, 0.035, 0.9))


func spawn_deployed_trap(world_position: Vector3) -> HotelInteractable:
	var marker := _make_marker("deployed_trap", Vector3(world_position.x, 0.12, world_position.z), {
		"deployed": true,
	}, Color(0.38, 0.38, 0.40, 1.0), Vector3(0.9, 0.18, 0.9), _world_item_texture("folding_trap"), 0.68, 0.22)
	marker.add_to_group("tenant_hazard")
	hazard_nodes.append(marker)
	return marker


func spawn_slippery_zone(world_position: Vector3) -> HotelInteractable:
	var marker := _make_marker("slippery_zone", Vector3(world_position.x, 0.035, world_position.z), {
		"deployed": true,
		"hazard_type": "slippery",
	}, Color(0.28, 0.48, 0.50, 0.48), Vector3(1.25, 0.055, 1.25))
	slippery_nodes.append(marker)
	return marker


func remove_gameplay_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()


func get_loose_items() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("loose_item"):
		if not (node is Node3D) or not is_ancestor_of(node):
			continue
		var marker := node as Node3D
		if not marker.visible:
			continue
		var data_value: Variant = marker.get("data")
		if data_value is Dictionary and bool(data_value.get("deployed", false)):
			continue
		if data_value is Dictionary and data_value.get("origin_anchor") is Vector3:
			if marker.global_position.distance_to(data_value.origin_anchor) <= 0.12:
				continue
		var room_id := get_room_id_at_world(marker.global_position)
		if not room_id.is_empty():
			if not is_room_door_open(room_id):
				continue
		result.append(marker)
	return result


func return_loose_item(item: Node3D) -> void:
	if item == null or not is_instance_valid(item):
		return
	var data_value: Variant = item.get("data")
	if data_value is Dictionary and data_value.get("origin_anchor") is Vector3:
		item.global_position = data_value.origin_anchor
	if controller != null and controller.has_method("on_loose_item_returned"):
		controller.on_loose_item_returned(item)


func is_player_lockpicking(player_node: Node) -> bool:
	return player_node != null and player_node.has_method("active_action_id") and String(player_node.active_action_id()) in ["unlock_lockpick", "unlock_prybar"]


func cleaner_report(player_world_position: Vector3) -> void:
	if controller != null and controller.has_method("cleaner_report"):
		controller.cleaner_report(player_world_position)


func npc_caught(kind: StringName) -> void:
	if controller != null and controller.has_method("npc_caught"):
		controller.npc_caught(kind)


func guard_personal_space(default_distance: float) -> float:
	if controller != null and controller.has_method("guard_personal_space"):
		return float(controller.guard_personal_space(default_distance))
	return default_distance


func _check_night_hazards() -> void:
	if controller == null:
		return
	# Cleaner fluid is a one-shot slow zone and works on any moving NPC, by day
	# or night.  A short stun represents the loss of footing without adding a
	# second movement-state system to the framework.
	for npc_value in get_tree().get_nodes_in_group("hotel_npc"):
		if not (npc_value is Node3D) or not is_ancestor_of(npc_value):
			continue
		var npc := npc_value as Node3D
		for slippery in slippery_nodes:
			if is_instance_valid(slippery) and npc.global_position.distance_to(slippery.global_position) <= 1.2:
				if npc.has_method("stun"):
					npc.stun(1.5)
				slippery.queue_free()
				slippery_nodes.erase(slippery)
				break
	if not controller.has_method("is_night_active") or not controller.is_night_active():
		return
	for tenant_value in get_tree().get_nodes_in_group("hotel_tenant"):
		if not (tenant_value is Node3D) or not is_ancestor_of(tenant_value):
			continue
		var tenant := tenant_value as Node3D
		if tenant.has_meta("defeated"):
			continue
		for hazard in hazard_nodes:
			if is_instance_valid(hazard) and tenant.global_position.distance_to(hazard.global_position) <= 1.15:
				tenant.set_meta("defeated", true)
				if controller.has_method("tenant_killed"):
					controller.tenant_killed(tenant, hazard.global_position, "folding_trap")
				hazard.queue_free()
				break
		if tenant.has_meta("defeated"):
			continue
		var room_id := get_room_id_at_world(tenant.global_position)
		if not room_id.is_empty() and bool(room_runtime.get(room_id, {}).get("cabinet_armed", false)):
			var descriptor: Dictionary = descriptor_by_id.get(room_id, {})
			if not descriptor.is_empty() and tenant.global_position.distance_to(descriptor.center) <= 1.45:
				tenant.set_meta("defeated", true)
				room_runtime[room_id]["cabinet_armed"] = false
				if controller.has_method("tenant_killed"):
					controller.tenant_killed(tenant, tenant.global_position, "cabinet")


func _draw_debug_truth(img: Image, px: int) -> void:
	for descriptor: Dictionary in room_descriptors:
		var room_id := String(descriptor.room_id)
		var runtime: Dictionary = room_runtime.get(room_id, {})
		var color := Color(0.25, 0.55, 0.9)
		if String(descriptor.room_type) == "guest":
			if String(runtime.get("assignment", "")) == "vacant":
				color = Color(0.2, 0.85, 0.36)
			elif not bool(runtime.get("returns_tonight", true)):
				color = Color(0.95, 0.72, 0.18)
			else:
				color = Color(0.88, 0.2, 0.18)
		if room_id == previous_room_id:
			color = Color(0.5, 0.35, 1.0)
		var tile: Vector2i = descriptor.door_tile
		_mark(img, tile.x, tile.y, color, px)
	for disposal_value in day_manifest.get("disposal_room_ids", []):
		var descriptor: Dictionary = descriptor_by_id.get(String(disposal_value), {})
		if not descriptor.is_empty():
			var tile: Vector2i = descriptor.door_tile
			_mark(img, tile.x, tile.y, Color(1.0, 0.1, 0.8), px)
	# Static patrol waypoints make each NPC route auditable without exposing a
	# production map.  Pickup anchors are marked separately from current items.
	for patrol_offset in [0, 4, 7]:
		for waypoint: Vector3 in get_patrol_points(patrol_offset):
			var patrol_cell := _cell_of_unclamped(waypoint)
			_mark(img, patrol_cell.x, patrol_cell.y, Color(0.05, 0.95, 0.95), px)
	for pickup in pickup_nodes:
		if not is_instance_valid(pickup):
			continue
		var origin_value: Variant = pickup.data.get("origin_anchor", pickup.global_position)
		if origin_value is Vector3:
			var origin_cell := _cell_of_unclamped(origin_value)
			_mark(img, origin_cell.x, origin_cell.y, Color(1.0, 0.92, 0.16), px)

func _door_dir_of(a: Vector2i) -> Vector2i:
	for spot in door_spots:
		if spot.corridor == a:
			return spot.dir
	return Vector2i(0, 1)


func _room_clear_anchor(descriptor: Dictionary, side_offset := 0.0) -> Vector3:
	if descriptor.is_empty():
		return get_lobby_spawn_position()
	var center: Vector3 = descriptor.get("center", get_lobby_spawn_position())
	var direction: Vector2i = descriptor.get("door_dir", Vector2i.RIGHT)
	var toward := Vector3(direction.x, 0.0, direction.y)
	var side := Vector3(-direction.y, 0.0, direction.x)
	var depth := float(descriptor.get("depth", 2))
	return center + toward * maxf(0.55, depth - 0.72) + side * side_offset

func _build_lobby_decor() -> void:
	for off in [Vector2i(2, 2), Vector2i(-2, 2), Vector2i(2, -2), Vector2i(-2, -2)]:
		var g = lc + off
		if lobby_bands.has(g):
			continue
		var col = kit.lobby_column()
		col.position = cell_pos(g.x, g.y)
		col.add_to_group("lobby_decor")
		add_child(col)
	var desk_offs = [Vector2i(0, -2), Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0)]
	for off in desk_offs:
		var g = lc + off
		if not lobby_bands.has(g):
			var desk = kit.lobby_desk()
			desk.position = cell_pos(g.x, g.y)
			desk.rotation.y = kit._ry(Vector2i(-off.x, -off.y))
			desk.add_to_group("lobby_decor")
			add_child(desk)
			break
	for off in [Vector2i(0, 0), Vector2i(2, -2), Vector2i(-2, 2)]:
		var g = lc + off
		var ch = kit.lobby_chandelier()
		ch.position = cell_pos(g.x, g.y)
		ch.add_to_group("lobby_decor")
		add_child(ch)


func _build_range_signs() -> void:
	for existing in get_tree().get_nodes_in_group("range_sign"):
		if existing is Node and is_ancestor_of(existing):
			remove_child(existing)
			existing.queue_free()
	var names := {
		Vector2i.RIGHT: ["E", "东翼"],
		Vector2i.LEFT: ["W", "西翼"],
		Vector2i.DOWN: ["S", "南翼"],
		Vector2i.UP: ["N", "北翼"],
	}
	for exit_data in lobby_exits:
		var direction: Vector2i = exit_data.d
		var info: Array = names.get(direction, ["?", "客房"])
		var wing := String(info[0])
		var numbers: Array[int] = []
		for descriptor: Dictionary in room_descriptors:
			if String(descriptor.get("room_type", "")) == "guest" and String(descriptor.get("wing", "")) == wing:
				numbers.append(int(descriptor.get("number", 0)))
		if numbers.is_empty():
			continue
		numbers.sort()
		var label := Label3D.new()
		label.name = "RangeSign_%s" % wing
		label.text = "%s  %s-%03d—%s-%03d" % [String(info[1]), wing, numbers.front(), wing, numbers.back()]
		label.font_size = 30
		label.pixel_size = 0.007
		label.modulate = Color(0.82, 0.69, 0.38)
		label.outline_modulate = Color(0.055, 0.038, 0.02)
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		var sign_cell: Vector2i = exit_data.edge + direction
		label.position = cell_pos(sign_cell.x, sign_cell.y) + Vector3(0.0, 2.35, 0.0)
		label.add_to_group("range_sign")
		add_child(label)

func _place_corridor_decor() -> void:
	var counter := 0
	for y in range(GH):
		for x in range(GW):
			if grid[y][x] != Cell.CORRIDOR:
				continue
			if Vector2i(x, y) == elev_cell:
				continue
			if door_tiles.has(Vector2i(x, y)):
				continue
			counter += 1
			var walls := []
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx = x + d.x
				var ny = y + d.y
				if _in(nx, ny) and grid[ny][nx] == Cell.WALL:
					walls.append(d)
			if walls.size() == 0:
				continue
			var p = cell_pos(x, y)
			if counter % 7 == 0:
				var d: Vector2i = walls[0]
				var sc = kit.wall_sconce(d)
				sc.position = p + Vector3(d.x * 0.97, 2.0, d.y * 0.97)
				add_child(sc)
			elif counter % 13 == 0 and walls.size() > 1:
				var d: Vector2i = walls[walls.size() - 1]
				var pa = kit.framed_painting(d, 1.0, 0.7)
				pa.position = p + Vector3(d.x * 0.97, 1.7, d.y * 0.97)
				add_child(pa)

func _touches_empty(x: int, y: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx = x + d.x
		var ny = y + d.y
		if _in(nx, ny) and grid[ny][nx] != Cell.WALL:
			return true
	return false

func _add_floor_collision() -> void:
	var body = StaticBody3D.new()
	body.name = "FloorCollision"
	body.position = Vector3(0.0, -0.05, 0.0)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(GW * TILE, 0.1, GH * TILE)
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _add_boundary_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "ContinuousBoundary"
	var half_extent := GW * TILE * 0.5
	var wall_center := half_extent - HALF
	var wall_length := GW * TILE + TILE * 2.0
	for spec in [
		[Vector3(0.0, WALL_H * 0.5, -wall_center), Vector3(wall_length, WALL_H, TILE)],
		[Vector3(0.0, WALL_H * 0.5, wall_center), Vector3(wall_length, WALL_H, TILE)],
		[Vector3(-wall_center, WALL_H * 0.5, 0.0), Vector3(TILE, WALL_H, wall_length)],
		[Vector3(wall_center, WALL_H * 0.5, 0.0), Vector3(TILE, WALL_H, wall_length)],
	]:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = spec[1]
		col.shape = shape
		col.position = spec[0]
		body.add_child(col)
	add_child(body)

	var catch_body := StaticBody3D.new()
	catch_body.name = "SafetyFloor"
	var catch_col := CollisionShape3D.new()
	var catch_shape := BoxShape3D.new()
	catch_shape.size = Vector3(GW * TILE + 12.0, 0.5, GH * TILE + 12.0)
	catch_col.shape = catch_shape
	catch_col.position = Vector3(0.0, -2.5, 0.0)
	catch_body.add_child(catch_col)
	add_child(catch_body)


func _cell_of_unclamped(p: Vector3) -> Vector2i:
	var world_min_x := -GW * TILE * 0.5
	var world_min_z := -GH * TILE * 0.5
	return Vector2i(
		floori((p.x - world_min_x) / TILE),
		floori((p.z - world_min_z) / TILE)
	)


func _cell_of(p: Vector3) -> Vector2i:
	return _cell_of_unclamped(p)


func is_position_walkable(position: Vector3) -> bool:
	var cell := _cell_of_unclamped(position)
	return _is_walkable_cell(cell)


func _map_world_bounds() -> Rect2:
	return Rect2(
		Vector2(-GW * TILE * 0.5, -GH * TILE * 0.5),
		Vector2(GW * TILE, GH * TILE)
	)


func _safe_world_bounds() -> Rect2:
	var inner := GW * TILE * 0.5 - TILE - 0.35
	return Rect2(Vector2(-inner, -inner), Vector2(inner * 2.0, inner * 2.0))

func _update_lobby_collapse() -> void:
	if lobby_collapsed or player == null:
		return
	var c = _cell_of(player.global_position)
	if last_cell.x < 0:
		last_cell = c
		return
	if c == last_cell:
		return
	if not exited_lobby and not lobby_rect.has_point(c):
		exited_lobby = true
	if exited_lobby:
		var d = Vector2i(signi(c.x - last_cell.x), signi(c.y - last_cell.y))
		if prev_dir != Vector2i.ZERO and d != prev_dir and not (d.x != 0 and d.y != 0):
			turned = true
		if d.x != 0 or d.y != 0:
			prev_dir = d
			steps_after += 1
		if turned or steps_after >= 4:
			_collapse_lobby()
	last_cell = c

func _collapse_lobby() -> void:
	lobby_collapsed = true
	for y in range(lobby_rect.position.y, lobby_rect.end.y):
		for x in range(lobby_rect.position.x, lobby_rect.end.x):
			var g = Vector2i(x, y)
			if lobby_bands.has(g):
				continue
			grid[y][x] = Cell.WALL
			var w = kit.wall_segment()
			w.position = cell_pos(x, y)
			add_child(w)
	get_tree().call_group("lobby_decor", "queue_free")

func _build_environment() -> void:
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.008)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.33, 0.18)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.012, 0.011, 0.008)
	env.fog_density = 0.04
	env.fog_aerial_perspective = 0.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.01
	env.volumetric_fog_albedo = Color(0.5, 0.42, 0.26)
	env.volumetric_fog_emission = Color(0.08, 0.065, 0.03)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_length = 18.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	get_viewport().world_3d.environment = env

func _setup_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	generator = AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.1
	audio_player.stream = generator
	audio_player.volume_db = -18.0
	add_child(audio_player)
	audio_player.play()

func _face_of(d: Vector2i) -> float:
	if d.x == 1:
		return -PI / 2.0
	if d.x == -1:
		return PI / 2.0
	if d.y == 1:
		return PI
	return 0.0

func _spawn_player() -> void:
	var scene = load("res://player.tscn")
	player = scene.instantiate()
	var start = cell_pos(lc.x, lc.y)
	player.position = Vector3(start.x, 0.0, start.z)
	var face = _face_of(lobby_exits[0].d) if lobby_exits.size() > 0 else 0.0
	player.rotation.y = face
	add_child(player)
	player.configure_level(
		_create_map_texture(),
		_map_world_bounds(),
		_safe_world_bounds(),
		map_seed,
		rooms.size(),
		Vector3(start.x, 0.0, start.z)
	)
	last_cell = _cell_of(player.global_position)

func _flicker(delta: float) -> void:
	var t = Time.get_ticks_msec()
	for L in lights:
		var energy = L.base
		energy *= 0.9 + 0.1 * abs(sin(t * 0.02 + L.phase))
		L.timer -= delta
		if L.timer <= 0.0:
			L.timer = randf_range(3.0, 10.0)
			L.flick = randf_range(0.05, 0.3)
		if L.flick > 0.0:
			L.flick -= delta
			energy *= randf_range(0.05, 0.5)
		L.omni.light_energy = energy
		L.panel_mat.emission_energy_multiplier = clampf(energy / L.base, 0.0, 1.5)

func _fill_hum() -> void:
	if audio_player == null or not audio_player.playing:
		return
	var playback = audio_player.get_stream_playback()
	if playback == null:
		return
	var frames = playback.get_frames_available()
	if frames <= 0:
		return
	frames = mini(frames, 4096)
	var sr = generator.mix_rate
	for i in range(frames):
		phase60 += TAU * 60.0 / sr
		phase120 += TAU * 120.0 / sr
		var s = 0.5 * sin(phase60) + 0.3 * sin(phase120)
		s += randf_range(-0.015, 0.015)
		s *= 0.25
		playback.push_frame(Vector2(s, s))
