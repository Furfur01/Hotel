extends SceneTree

## Headless structural soak test for HotelFloor's layout-only generation path.
##
## Run from the project root:
##   godot --headless --log-file /tmp/floor_generation_test.log \
##     --path . --script res://tests/floor_generation_test.gd
## Optional arguments:
##   --seeds=500 --seed-start=0

const HotelFloorScript = preload("res://hotel.gd")
const CARDINALS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const EXPECTED_FUNCTIONS := {
	"storage": true,
	"laundry": true,
	"maintenance": true,
	"security": true,
	"service_elevator": true,
}
const MAX_EXAMPLES_PER_FAILURE := 8

var _failure_counts: Dictionary = {}
var _failure_examples: Dictionary = {}
var _tarjan_clock := 0
var _tarjan_discovery: Dictionary = {}
var _tarjan_low: Dictionary = {}
var _tarjan_parent: Dictionary = {}
var _tarjan_bridges: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var options := _read_options()
	var seed_count: int = options.seed_count
	var seed_start: int = options.seed_start
	var passed := 0
	var shifted_seed_count := 0
	var seeds_with_bridges := 0
	var seeds_with_critical_bridges := 0
	var total_bridges := 0
	var total_critical_bridges := 0
	var min_bridges := 2147483647
	var max_bridges := 0
	var critical_room_ids: Dictionary = {}

	print("FLOOR_GENERATION_TEST start seeds=%d seed_start=%d" % [seed_count, seed_start])
	for offset in range(seed_count):
		var requested_seed := seed_start + offset
		var floor = HotelFloorScript.new()
		floor.generation_seed = requested_seed
		floor.day_index = 1 + (offset % 2)
		floor._generate_layout()
		floor._assign_room_metadata()

		if floor.map_seed != requested_seed:
			shifted_seed_count += 1

		var failures_before := _total_failures()
		_validate_counts(floor, requested_seed)
		_validate_boundary(floor, requested_seed)
		_validate_connectivity(floor, requested_seed)
		_validate_doors_and_bindings(floor, requested_seed)
		if not floor._validate_layout():
			_fail("layout_self_validation", requested_seed, "HotelFloor._validate_layout() returned false")

		var graph := _build_corridor_graph(floor)
		var bridges := _find_bridges(graph)
		var bridge_count := bridges.size()
		total_bridges += bridge_count
		min_bridges = mini(min_bridges, bridge_count)
		max_bridges = maxi(max_bridges, bridge_count)
		if bridge_count > 0:
			seeds_with_bridges += 1

		var critical := _critical_bridge_report(floor, graph, bridges)
		var critical_bridge_count: int = critical.bridge_count
		total_critical_bridges += critical_bridge_count
		if critical_bridge_count > 0:
			seeds_with_critical_bridges += 1
			for room_id in critical.room_ids:
				critical_room_ids[room_id] = true
			_fail(
				"critical_region_reroute",
				requested_seed,
				"%d bridge edge(s) can isolate room entrances; sample=%s" % [
					critical_bridge_count,
					_format_bridge_samples(critical.samples),
				]
			)

		if _total_failures() == failures_before:
			passed += 1
		floor.free()

	var average_bridges := 0.0 if seed_count == 0 else float(total_bridges) / float(seed_count)
	var average_critical := 0.0 if seed_count == 0 else float(total_critical_bridges) / float(seed_count)
	if min_bridges == 2147483647:
		min_bridges = 0
	print("FLOOR_GENERATION_TEST summary passed=%d failed_seeds=%d assertions_failed=%d" % [
		passed,
		seed_count - passed,
		_total_failures(),
	])
	print("  generated_seed_shifted=%d/%d" % [shifted_seed_count, seed_count])
	print("  corridor_bridges total=%d avg=%.2f min=%d max=%d affected_seeds=%d/%d" % [
		total_bridges,
		average_bridges,
		min_bridges,
		max_bridges,
		seeds_with_bridges,
		seed_count,
	])
	print("  critical_reroute_bridges total=%d avg=%.2f affected_seeds=%d/%d affected_room_ids=%d" % [
		total_critical_bridges,
		average_critical,
		seeds_with_critical_bridges,
		seed_count,
		critical_room_ids.size(),
	])
	_print_failures()
	quit(0 if _failure_counts.is_empty() else 1)


func _read_options() -> Dictionary:
	var options := {"seed_count": 500, "seed_start": 0}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			options.seed_count = maxi(1, int(argument.trim_prefix("--seeds=")))
		elif argument.begins_with("--seed-start="):
			options.seed_start = maxi(0, int(argument.trim_prefix("--seed-start=")))
	return options


func _validate_counts(floor, requested_seed: int) -> void:
	var total: int = floor.rooms.size()
	if total < floor.MIN_ROOMS or total > floor.MAX_ROOMS:
		_fail("room_total", requested_seed, "total=%d expected=%d..%d" % [total, floor.MIN_ROOMS, floor.MAX_ROOMS])
	if floor.loop_count < floor.MIN_LOOPS or floor.loop_count > floor.MAX_LOOPS:
		_fail("loop_count", requested_seed, "loops=%d expected=%d..%d" % [floor.loop_count, floor.MIN_LOOPS, floor.MAX_LOOPS])
	if floor.room_descriptors.size() != total:
		_fail("descriptor_count", requested_seed, "descriptors=%d rooms=%d" % [floor.room_descriptors.size(), total])

	var guest_count := 0
	var function_counts: Dictionary = {}
	var room_ids: Dictionary = {}
	for descriptor in floor.room_descriptors:
		var room_type: String = descriptor.get("room_type", "")
		if room_type == "guest":
			guest_count += 1
		else:
			function_counts[room_type] = int(function_counts.get(room_type, 0)) + 1
		var room_id: String = descriptor.get("room_id", "")
		if room_id.is_empty() or room_ids.has(room_id):
			_fail("stable_room_ids", requested_seed, "missing or duplicate room_id=%s" % room_id)
		room_ids[room_id] = true
	if guest_count < floor.MIN_GUEST_ROOMS or guest_count > floor.MAX_GUEST_ROOMS:
		_fail("guest_count", requested_seed, "guests=%d expected=%d..%d" % [guest_count, floor.MIN_GUEST_ROOMS, floor.MAX_GUEST_ROOMS])
	if total - guest_count != EXPECTED_FUNCTIONS.size():
		_fail("function_count", requested_seed, "functions=%d expected=%d" % [total - guest_count, EXPECTED_FUNCTIONS.size()])
	for expected_type in EXPECTED_FUNCTIONS:
		if int(function_counts.get(expected_type, 0)) != 1:
			_fail("function_types", requested_seed, "%s count=%d expected=1" % [expected_type, function_counts.get(expected_type, 0)])
	for actual_type in function_counts:
		if not EXPECTED_FUNCTIONS.has(actual_type):
			_fail("function_types", requested_seed, "unexpected function type=%s" % actual_type)


func _validate_boundary(floor, requested_seed: int) -> void:
	for y in range(floor.GH):
		for x in range(floor.GW):
			if x <= floor.MAP_MARGIN or x >= floor.GW - 1 - floor.MAP_MARGIN or y <= floor.MAP_MARGIN or y >= floor.GH - 1 - floor.MAP_MARGIN:
				if floor.grid[y][x] != floor.Cell.WALL:
					_fail("boundary", requested_seed, "non-wall cell at (%d,%d) type=%s" % [x, y, floor.grid[y][x]])
					return
	for room in floor.rooms:
		for cell in room.cells:
			if cell.x <= floor.MAP_MARGIN or cell.x >= floor.GW - 1 - floor.MAP_MARGIN or cell.y <= floor.MAP_MARGIN or cell.y >= floor.GH - 1 - floor.MAP_MARGIN:
				_fail("boundary", requested_seed, "room %s reaches boundary at %s" % [room.get("room_id", "?"), cell])
				return


func _validate_connectivity(floor, requested_seed: int) -> void:
	var walkable_total := 0
	for y in range(floor.GH):
		for x in range(floor.GW):
			if floor.grid[y][x] != floor.Cell.WALL:
				walkable_total += 1
	var seen := _grid_reachable(floor, floor.lc)
	if seen.size() != walkable_total:
		_fail("walkable_connectivity", requested_seed, "reachable=%d walkable=%d" % [seen.size(), walkable_total])


func _grid_reachable(floor, start: Vector2i) -> Dictionary:
	var seen: Dictionary = {start: true}
	var queue: Array = [start]
	var cursor := 0
	while cursor < queue.size():
		var here: Vector2i = queue[cursor]
		cursor += 1
		for direction in CARDINALS:
			var neighbor: Vector2i = here + direction
			if floor._is_walkable_cell(neighbor) and not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	return seen


func _validate_doors_and_bindings(floor, requested_seed: int) -> void:
	if floor.rooms.size() != floor.door_spots.size():
		_fail("door_cardinality", requested_seed, "rooms=%d doors=%d" % [floor.rooms.size(), floor.door_spots.size()])
		return
	var door_room_ids: Dictionary = {}
	var door_room_tiles: Dictionary = {}
	for index in range(floor.rooms.size()):
		var room: Dictionary = floor.rooms[index]
		var spot: Dictionary = floor.door_spots[index]
		var room_id: String = room.get("room_id", "")
		var spot_room_id: String = spot.get("room_id", "")
		if room_id != spot_room_id:
			_fail("door_binding", requested_seed, "index=%d room_id=%s door_room_id=%s" % [index, room_id, spot_room_id])
		if door_room_ids.has(spot_room_id):
			_fail("door_binding", requested_seed, "room_id=%s has more than one door" % spot_room_id)
		door_room_ids[spot_room_id] = true

		var tile: Vector2i = spot.get("tile", Vector2i(-999, -999))
		var corridor: Vector2i = spot.get("corridor", Vector2i(-999, -999))
		var direction: Vector2i = spot.get("dir", Vector2i.ZERO)
		if door_room_tiles.has(tile):
			_fail("door_binding", requested_seed, "door tile %s is shared" % tile)
		door_room_tiles[tile] = true
		if direction not in CARDINALS:
			_fail("door_direction", requested_seed, "room=%s invalid direction=%s" % [room_id, direction])
			continue
		if corridor != tile + direction:
			_fail("door_direction", requested_seed, "room=%s corridor=%s expected=%s" % [room_id, corridor, tile + direction])
		if room.get("door_tile") != tile or room.get("corridor_tile") != corridor or room.get("door_dir") != direction:
			_fail("door_binding", requested_seed, "room=%s room/door metadata differs" % room_id)
		if not floor._in(tile.x, tile.y) or floor.grid[tile.y][tile.x] != floor.Cell.ROOM:
			_fail("door_opening", requested_seed, "room=%s door tile %s is not ROOM" % [room_id, tile])
			continue
		if not floor._in(corridor.x, corridor.y) or floor.grid[corridor.y][corridor.x] != floor.Cell.CORRIDOR:
			_fail("door_opening", requested_seed, "room=%s corridor side %s is not CORRIDOR" % [room_id, corridor])
		var inner: Vector2i = tile - direction
		if not floor._in(inner.x, inner.y) or floor.grid[inner.y][inner.x] != floor.Cell.ROOM:
			_fail("door_opening", requested_seed, "room=%s interior side %s is not ROOM" % [room_id, inner])
		if not room.cells.has(tile) or not room.cells.has(inner):
			_fail("door_opening", requested_seed, "room=%s opening cells are absent from room cell list" % room_id)
		if not floor.door_tiles.has(corridor):
			_fail("door_binding", requested_seed, "room=%s corridor tile missing from door_tiles" % room_id)
		for cell in room.cells:
			if floor.room_by_id.get(cell, "") != room_id:
				_fail("room_cell_binding", requested_seed, "cell=%s maps to %s expected=%s" % [cell, floor.room_by_id.get(cell, ""), room_id])
				break
	if door_room_ids.size() != floor.descriptor_by_id.size():
		_fail("door_binding", requested_seed, "door room ids=%d descriptor ids=%d" % [door_room_ids.size(), floor.descriptor_by_id.size()])


func _build_corridor_graph(floor) -> Dictionary:
	var graph: Dictionary = {}
	for y in range(floor.GH):
		for x in range(floor.GW):
			if floor.grid[y][x] in [floor.Cell.CORRIDOR, floor.Cell.LOBBY]:
				graph[Vector2i(x, y)] = []
	for cell in graph:
		var neighbors: Array = graph[cell]
		for direction in CARDINALS:
			var neighbor: Vector2i = cell + direction
			if graph.has(neighbor):
				neighbors.append(neighbor)
		graph[cell] = neighbors
	return graph


func _find_bridges(graph: Dictionary) -> Array:
	_tarjan_clock = 0
	_tarjan_discovery = {}
	_tarjan_low = {}
	_tarjan_parent = {}
	_tarjan_bridges = []
	for node in graph:
		if not _tarjan_discovery.has(node):
			_bridge_dfs(node, graph)
	return _tarjan_bridges.duplicate(true)


func _bridge_dfs(node: Vector2i, graph: Dictionary) -> void:
	_tarjan_clock += 1
	_tarjan_discovery[node] = _tarjan_clock
	_tarjan_low[node] = _tarjan_clock
	for neighbor in graph[node]:
		if not _tarjan_discovery.has(neighbor):
			_tarjan_parent[neighbor] = node
			_bridge_dfs(neighbor, graph)
			_tarjan_low[node] = mini(int(_tarjan_low[node]), int(_tarjan_low[neighbor]))
			if int(_tarjan_low[neighbor]) > int(_tarjan_discovery[node]):
				_tarjan_bridges.append({"a": node, "b": neighbor})
		elif _tarjan_parent.get(node, Vector2i(-999, -999)) != neighbor:
			_tarjan_low[node] = mini(int(_tarjan_low[node]), int(_tarjan_discovery[neighbor]))


func _critical_bridge_report(floor, graph: Dictionary, bridges: Array) -> Dictionary:
	var critical_nodes: Dictionary = {}
	for spot in floor.door_spots:
		critical_nodes[spot.corridor] = spot.get("room_id", "?")
	var critical_bridge_count := 0
	var samples: Array = []
	var affected_room_ids: Dictionary = {}
	for bridge in bridges:
		var reachable := _graph_reachable_without_edge(graph, floor.lc, bridge.a, bridge.b)
		var disconnected: Array = []
		for node in critical_nodes:
			if not reachable.has(node):
				var room_id: String = critical_nodes[node]
				disconnected.append(room_id)
				affected_room_ids[room_id] = true
		if not disconnected.is_empty():
			critical_bridge_count += 1
			if samples.size() < 3:
				samples.append({"a": bridge.a, "b": bridge.b, "rooms": disconnected.slice(0, mini(3, disconnected.size()))})
	return {
		"bridge_count": critical_bridge_count,
		"samples": samples,
		"room_ids": affected_room_ids.keys(),
	}


func _graph_reachable_without_edge(graph: Dictionary, start: Vector2i, edge_a: Vector2i, edge_b: Vector2i) -> Dictionary:
	var seen: Dictionary = {start: true}
	var queue: Array = [start]
	var cursor := 0
	while cursor < queue.size():
		var here: Vector2i = queue[cursor]
		cursor += 1
		for neighbor in graph.get(here, []):
			if (here == edge_a and neighbor == edge_b) or (here == edge_b and neighbor == edge_a):
				continue
			if not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	return seen


func _format_bridge_samples(samples: Array) -> String:
	var parts: Array[String] = []
	for sample in samples:
		parts.append("%s-%s => %s" % [sample.a, sample.b, sample.rooms])
	return "; ".join(parts)


func _fail(category: String, seed_value: int, detail: String) -> void:
	_failure_counts[category] = int(_failure_counts.get(category, 0)) + 1
	if not _failure_examples.has(category):
		_failure_examples[category] = []
	var examples: Array = _failure_examples[category]
	if examples.size() < MAX_EXAMPLES_PER_FAILURE:
		examples.append("seed=%d %s" % [seed_value, detail])
	_failure_examples[category] = examples


func _total_failures() -> int:
	var total := 0
	for count in _failure_counts.values():
		total += int(count)
	return total


func _print_failures() -> void:
	if _failure_counts.is_empty():
		print("  assertions: PASS")
		return
	print("  assertions: FAIL")
	var categories: Array = _failure_counts.keys()
	categories.sort()
	for category in categories:
		print("    %s count=%d" % [category, _failure_counts[category]])
		for example in _failure_examples.get(category, []):
			print("      %s" % example)
