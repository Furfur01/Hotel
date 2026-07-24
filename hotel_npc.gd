class_name HotelNPC
extends CharacterBody3D

## Lightweight hotel NPC which deliberately does not depend on a baked
## NavigationRegion3D.  The floor host may supply grid/path waypoints through
## find_path_world(); when it does not, the NPC walks directly between the
## configured patrol points.

const KIND_GUARD: StringName = &"guard"
const KIND_CLEANER: StringName = &"cleaner"
const KIND_TENANT: StringName = &"tenant"
const ROLE_CHASER: StringName = &"chaser"
const ROLE_AMBUSHER: StringName = &"ambusher"
const FOOTSTEP_PATHS := [
	"res://assets/audio/kenney/footstep_carpet_000.ogg",
	"res://assets/audio/kenney/footstep_carpet_001.ogg",
	"res://assets/audio/kenney/footstep_carpet_002.ogg",
	"res://assets/audio/kenney/footstep_carpet_003.ogg",
	"res://assets/audio/kenney/footstep_carpet_004.ogg",
]
const _RunState = preload("res://game_state.gd")

@export var patrol_speed := 1.45
@export var cleaner_speed := 1.25
@export var chase_speed := _RunState.TENANT_CHASE_SPEED
@export var acceleration := 12.0
@export var turn_speed := 7.0
@export var gravity := 20.0
@export var sight_distance := 11.0
@export var cleaner_sight_distance := 8.0
@export_range(30.0, 180.0, 1.0) var field_of_view_degrees := 105.0
@export var catch_distance := 0.82
@export var daytime_personal_space := 1.05
@export var incident_duration := 14.0
@export var cleaner_block_duration := 10.0

var host: Node = null
var player: Node3D = null
var kind: StringName = KIND_GUARD
var pursuit_role: StringName = ROLE_CHASER
var patrol_points := PackedVector3Array()
var night_mode := false

var _patrol_index := 0
var _route := PackedVector3Array()
var _route_index := 0
var _destination := Vector3.ZERO
var _has_destination := false
var _repath_timer := 0.0

var _chasing := false
var _chase_permanent := false
var _lost_sight_time := 0.0
var _incident_active := false
var _incident_position := Vector3.ZERO
var _incident_time_left := 0.0

var _stun_time_left := 0.0
var _lure_time_left := 0.0
var _lure_position := Vector3.ZERO
var _cleaner_block_time_left := 0.0
var _loose_scan_time_left := 0.0
var _loose_target: Node3D = null
var _lockpick_report_latched := false
var _catch_cooldown := 0.0

var _visual_root: Node3D = null
var _loaded_visual_kind: StringName = &""
var _footstep_player: AudioStreamPlayer3D = null
var _footstep_streams: Array[AudioStream] = []
var _footstep_distance := 0.0
var _last_footstep_index := -1


func _ready() -> void:
	floor_snap_length = 0.35
	floor_stop_on_slope = true
	_setup_footstep_audio()
	_build_low_poly_body()
	_apply_kind_appearance()
	if kind == KIND_TENANT:
		start_chase(true)
	elif not patrol_points.is_empty():
		_patrol_index = _nearest_patrol_index()


func configure(
	new_host: Node,
	new_player: Node3D,
	npc_kind: Variant,
	new_patrol_points: Variant,
	start_at_night: bool = false,
	new_pursuit_role: StringName = ROLE_CHASER
	) -> void:
	host = new_host
	player = new_player
	kind = StringName(str(npc_kind).to_lower())
	if kind != KIND_GUARD and kind != KIND_CLEANER and kind != KIND_TENANT:
		push_warning("Unknown HotelNPC kind '%s'; using guard." % str(npc_kind))
		kind = KIND_GUARD
	patrol_points = _coerce_vector3_array(new_patrol_points)
	night_mode = start_at_night
	pursuit_role = new_pursuit_role if new_pursuit_role in [ROLE_CHASER, ROLE_AMBUSHER] else ROLE_CHASER
	_patrol_index = _nearest_patrol_index()
	_invalidate_route()
	_incident_active = false
	_incident_time_left = 0.0
	_cleaner_block_time_left = 0.0
	_loose_target = null
	if kind == KIND_TENANT:
		start_chase(true)
	else:
		_chasing = false
		_chase_permanent = false
	_apply_kind_appearance()


func set_night_mode(enabled: bool) -> void:
	night_mode = enabled
	if kind == KIND_TENANT:
		start_chase(true)
	elif kind == KIND_GUARD and not enabled:
		_chasing = false
		_chase_permanent = false
		_incident_active = false
		_incident_time_left = 0.0
		_invalidate_route()


func start_chase(permanent: bool = true) -> void:
	if kind == KIND_CLEANER:
		return
	_chasing = true
	_chase_permanent = permanent or kind == KIND_TENANT or (kind == KIND_GUARD and night_mode)
	_lost_sight_time = 0.0
	_repath_timer = 0.0


func report_incident(world_position: Vector3) -> void:
	if kind != KIND_GUARD:
		return
	_incident_active = true
	_incident_position = world_position
	_incident_time_left = incident_duration
	if not night_mode and not _chase_permanent:
		_chasing = false
	_invalidate_route()


func stun(duration: float = 2.0) -> void:
	_stun_time_left = maxf(_stun_time_left, maxf(0.0, duration))
	velocity.x = 0.0
	velocity.z = 0.0


func lure_to(world_position: Vector3, duration: float = 5.0) -> void:
	## Used by the wind-up clock.  Even a permanently chasing tenant can be
	## redirected briefly, then resumes its normal state when the sound ends.
	_lure_position = world_position
	_lure_time_left = maxf(_lure_time_left, maxf(duration, 0.0))
	_invalidate_route()


func is_chasing() -> bool:
	return _chasing


func _physics_process(delta: float) -> void:
	_catch_cooldown = maxf(0.0, _catch_cooldown - delta)
	_apply_gravity(delta)

	if _stun_time_left > 0.0:
		_stun_time_left = maxf(0.0, _stun_time_left - delta)
		_hold_position(delta)
		return
	if _lure_time_left > 0.0:
		_lure_time_left = maxf(0.0, _lure_time_left - delta)
		var lure_speed := cleaner_speed if kind == KIND_CLEANER else patrol_speed * 1.2
		_follow_static_target(_lure_position, lure_speed, delta)
		_try_capture_player()
		return

	match kind:
		KIND_CLEANER:
			_tick_cleaner(delta)
		KIND_TENANT:
			_tick_tenant(delta)
		_:
			_tick_guard(delta)

	_try_capture_player()


func _tick_guard(delta: float) -> void:
	if night_mode:
		if not _chasing and _can_see_player(sight_distance):
			start_chase(true)
		if _chasing and _player_is_available():
			_follow_dynamic_target(_pursuit_target(), chase_speed, delta)
		else:
			_follow_patrol(delta, patrol_speed)
		return

	if _incident_active:
		_incident_time_left = maxf(0.0, _incident_time_left - delta)
		var sees_player := _can_see_player(sight_distance)
		if sees_player:
			_chasing = true
			_chase_permanent = false
			_lost_sight_time = 0.0
			_incident_time_left = maxf(_incident_time_left, 4.0)
		elif _chasing:
			_lost_sight_time += delta
			if _lost_sight_time >= 3.5:
				_chasing = false
				_invalidate_route()

		if _chasing and _player_is_available():
			_follow_dynamic_target(player.global_position, chase_speed, delta)
		else:
			_follow_static_target(_incident_position, patrol_speed * 1.25, delta)

		if _incident_time_left <= 0.0:
			_incident_active = false
			_chasing = false
			_chase_permanent = false
			_invalidate_route()
		return

	_chasing = false
	_chase_permanent = false
	_follow_patrol(delta, patrol_speed)


func _tick_tenant(delta: float) -> void:
	if not _chasing:
		start_chase(true)
	if _player_is_available():
		_follow_dynamic_target(player.global_position, chase_speed, delta)
	else:
		_hold_position(delta)


func _pursuit_target() -> Vector3:
	if not _player_is_available() or pursuit_role != ROLE_AMBUSHER:
		return player.global_position if _player_is_available() else global_position
	var lead_direction := Vector3.ZERO
	if player is CharacterBody3D:
		lead_direction = (player as CharacterBody3D).velocity
		lead_direction.y = 0.0
	if lead_direction.length_squared() < 0.16:
		lead_direction = -player.global_transform.basis.z
		lead_direction.y = 0.0
	if lead_direction.length_squared() < 0.001:
		return player.global_position
	return player.global_position + lead_direction.normalized() * 4.5


func _tick_cleaner(delta: float) -> void:
	if _cleaner_block_time_left > 0.0:
		_cleaner_block_time_left = maxf(0.0, _cleaner_block_time_left - delta)
		_hold_position(delta)
		return

	_check_for_lockpicking()
	if _cleaner_block_time_left > 0.0:
		_hold_position(delta)
		return

	_loose_scan_time_left -= delta
	if _loose_scan_time_left <= 0.0:
		_loose_scan_time_left = 0.8
		_scan_for_loose_item()

	if _loose_target != null and is_instance_valid(_loose_target):
		var item_distance := _horizontal_distance(global_position, _loose_target.global_position)
		if item_distance <= 0.9:
			if host != null and is_instance_valid(host) and host.has_method("return_loose_item"):
				host.call("return_loose_item", _loose_target)
			_loose_target = null
			_invalidate_route()
			_hold_position(delta)
		else:
			_follow_dynamic_target(_loose_target.global_position, cleaner_speed, delta, 0.8)
		return

	_loose_target = null
	_follow_patrol(delta, cleaner_speed)


func _check_for_lockpicking() -> void:
	if host == null or not is_instance_valid(host) or not host.has_method("is_player_lockpicking"):
		_lockpick_report_latched = false
		return
	if not _player_is_available():
		_lockpick_report_latched = false
		return
	var lockpicking := bool(host.call("is_player_lockpicking", player))
	if not lockpicking:
		_lockpick_report_latched = false
		return
	if _lockpick_report_latched or not _can_see_player(cleaner_sight_distance):
		return

	_lockpick_report_latched = true
	_cleaner_block_time_left = cleaner_block_duration
	_loose_target = null
	_invalidate_route()
	if host.has_method("cleaner_report"):
		host.call("cleaner_report", player.global_position)


func _scan_for_loose_item() -> void:
	if host == null or not is_instance_valid(host) or not host.has_method("get_loose_items"):
		_loose_target = null
		return
	var loose_items: Variant = host.call("get_loose_items")
	if not loose_items is Array:
		_loose_target = null
		return

	var nearest: Node3D = null
	var nearest_distance_sq := INF
	for candidate: Variant in loose_items:
		if candidate is Node3D and is_instance_valid(candidate):
			var candidate_node := candidate as Node3D
			var distance_sq := global_position.distance_squared_to(candidate_node.global_position)
			if distance_sq < nearest_distance_sq:
				nearest = candidate_node
				nearest_distance_sq = distance_sq
	_loose_target = nearest


func _follow_patrol(delta: float, move_speed: float) -> void:
	if patrol_points.is_empty():
		_hold_position(delta)
		return
	_patrol_index = posmod(_patrol_index, patrol_points.size())
	var target := patrol_points[_patrol_index]
	if _horizontal_distance(global_position, target) <= 0.55:
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		target = patrol_points[_patrol_index]
		_invalidate_route()
	_follow_static_target(target, move_speed, delta)


func _follow_static_target(target: Vector3, move_speed: float, delta: float) -> void:
	_repath_timer -= delta
	if not _has_destination or _horizontal_distance(_destination, target) > 0.25 or _repath_timer <= 0.0:
		_build_route(target)
		_repath_timer = 1.25
	_move_along_route(move_speed, delta)


func _follow_dynamic_target(
	target: Vector3,
	move_speed: float,
	delta: float,
	repath_interval: float = 0.3
	) -> void:
	_repath_timer -= delta
	if not _has_destination or _horizontal_distance(_destination, target) > 0.7 or _repath_timer <= 0.0:
		_build_route(target)
		_repath_timer = repath_interval
	_move_along_route(move_speed, delta)


func _build_route(target: Vector3) -> void:
	_route = PackedVector3Array()
	_route_index = 0
	_destination = target
	_has_destination = true

	if host != null and is_instance_valid(host) and host.has_method("find_path_world"):
		var supplied_path: Variant = host.call("find_path_world", global_position, target)
		_route = _coerce_vector3_array(supplied_path)

	while not _route.is_empty() and _horizontal_distance(global_position, _route[0]) <= 0.35:
		_route.remove_at(0)
	if _route.is_empty() or _horizontal_distance(_route[_route.size() - 1], target) > 0.35:
		_route.append(target)


func _move_along_route(move_speed: float, delta: float) -> void:
	while _route_index < _route.size() and _horizontal_distance(global_position, _route[_route_index]) <= 0.38:
		_route_index += 1
	if _route_index >= _route.size():
		_hold_position(delta)
		return

	var target := _route[_route_index]
	if host != null and is_instance_valid(host) and host.has_method("ensure_npc_passage"):
		if not bool(host.call("ensure_npc_passage", global_position, target)):
			_hold_position(delta)
			return
	var direction := target - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		_hold_position(delta)
		return
	direction = direction.normalized()
	velocity.x = move_toward(velocity.x, direction.x * move_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * move_speed, acceleration * delta)
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1.0, turn_speed * delta))
	var position_before_move := global_position
	move_and_slide()
	_tick_footsteps(_horizontal_distance(position_before_move, global_position), move_speed)


func _hold_position(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	move_and_slide()


func _setup_footstep_audio() -> void:
	_footstep_player = AudioStreamPlayer3D.new()
	_footstep_player.name = "Footsteps"
	_footstep_player.max_distance = 14.0
	_footstep_player.unit_size = 3.0
	_footstep_player.max_polyphony = 2
	_footstep_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_footstep_player)
	for path in FOOTSTEP_PATHS:
		var stream := load(path) as AudioStream
		if stream != null:
			_footstep_streams.append(stream)


func _tick_footsteps(horizontal_travel: float, move_speed: float) -> void:
	if horizontal_travel <= 0.0001 or _footstep_streams.is_empty():
		return
	_footstep_distance += horizontal_travel
	var stride := 1.45 if move_speed >= chase_speed * 0.9 else 1.65
	if _footstep_distance < stride:
		return
	_footstep_distance = fmod(_footstep_distance, stride)
	var next_index := randi_range(0, _footstep_streams.size() - 1)
	if _footstep_streams.size() > 1 and next_index == _last_footstep_index:
		next_index = (next_index + 1) % _footstep_streams.size()
	_last_footstep_index = next_index
	_footstep_player.stream = _footstep_streams[next_index]
	_footstep_player.pitch_scale = randf_range(0.88, 1.04) * (0.92 if kind == KIND_TENANT else 1.0)
	_footstep_player.volume_db = -7.0 if kind == KIND_TENANT else (-9.0 if kind == KIND_GUARD else -12.0)
	_footstep_player.play()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)


func _try_capture_player() -> void:
	if _catch_cooldown > 0.0 or not _player_is_available():
		return
	var distance_to_player := _horizontal_distance(global_position, player.global_position)
	var can_capture := false
	if kind == KIND_TENANT:
		can_capture = _chasing and distance_to_player <= catch_distance
	elif kind == KIND_GUARD:
		if night_mode:
			can_capture = _chasing and distance_to_player <= catch_distance
		else:
			var personal_space := daytime_personal_space
			if host != null and is_instance_valid(host) and host.has_method("guard_personal_space"):
				personal_space = float(host.call("guard_personal_space", personal_space))
			can_capture = distance_to_player <= personal_space
	if not can_capture:
		return

	_catch_cooldown = 1.0
	velocity.x = 0.0
	velocity.z = 0.0
	if host != null and is_instance_valid(host) and host.has_method("npc_caught"):
		host.call("npc_caught", kind)


func _can_see_player(max_distance: float) -> bool:
	if not _player_is_available() or _player_is_hidden():
		return false
	var eye := global_position + Vector3(0.0, 1.45, 0.0)
	var target := player.global_position + Vector3(0.0, 1.25, 0.0)
	var to_target := target - eye
	if to_target.length() > max_distance:
		return false
	var flat_target := Vector3(to_target.x, 0.0, to_target.z)
	if flat_target.length_squared() > 0.0001:
		var forward := -global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var minimum_dot := cos(deg_to_rad(field_of_view_degrees * 0.5))
		if forward.dot(flat_target.normalized()) < minimum_dot:
			return false

	var query := PhysicsRayQueryParameters3D.create(eye, target)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider: Variant = hit.get("collider")
	if collider == player:
		return true
	return collider is Node and player.is_ancestor_of(collider as Node)


func _player_is_available() -> bool:
	return player != null and is_instance_valid(player) and player.is_inside_tree()


func _player_is_hidden() -> bool:
	if host != null and is_instance_valid(host) and host.has_method("is_player_hidden"):
		return bool(host.call("is_player_hidden", player))
	if _object_has_property(player, &"in_wardrobe"):
		return bool(player.get("in_wardrobe"))
	return false


func _object_has_property(object: Object, property_name: StringName) -> bool:
	if object == null:
		return false
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _nearest_patrol_index() -> int:
	if patrol_points.is_empty():
		return 0
	var nearest_index := 0
	var nearest_distance_sq := INF
	for index in range(patrol_points.size()):
		var point := patrol_points[index]
		var distance_sq := Vector2(global_position.x, global_position.z).distance_squared_to(Vector2(point.x, point.z))
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest_index = index
	return nearest_index


func _coerce_vector3_array(source: Variant) -> PackedVector3Array:
	var result := PackedVector3Array()
	if source is PackedVector3Array:
		return source
	if source is Array:
		for value: Variant in source:
			if value is Vector3:
				result.append(value)
	return result


func _invalidate_route() -> void:
	_route = PackedVector3Array()
	_route_index = 0
	_has_destination = false
	_repath_timer = 0.0


func _build_low_poly_body() -> void:
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.31
		capsule.height = 1.7
		collision.shape = capsule
		collision.position.y = 0.85
		add_child(collision)

	_visual_root = get_node_or_null("CharacterVisual") as Node3D
	if _visual_root == null:
		_visual_root = Node3D.new()
		_visual_root.name = "CharacterVisual"
		add_child(_visual_root)


func _apply_kind_appearance() -> void:
	if _visual_root == null:
		return
	if _loaded_visual_kind == kind and _visual_root.get_child_count() > 0:
		return
	for child: Node in _visual_root.get_children():
		child.queue_free()
	_loaded_visual_kind = kind
	var texture_path := "res://assets/characters/final/%s.png" % String(kind)
	var texture := load(texture_path) as Texture2D
	if texture == null:
		push_warning("Missing hotel character sprite: %s" % texture_path)
		return
	var sprite := Sprite3D.new()
	sprite.name = "%sNextbot" % String(kind).capitalize()
	sprite.texture = texture
	sprite.position.y = 0.91
	sprite.pixel_size = 0.01125
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = true
	_visual_root.add_child(sprite)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	return material
