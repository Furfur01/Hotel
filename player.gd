class_name HotelPlayer
extends CharacterBody3D

const _HUD = preload("res://hud.gd")
const FOOTSTEP_PATHS := [
	"res://assets/audio/kenney/footstep_carpet_000.ogg",
	"res://assets/audio/kenney/footstep_carpet_001.ogg",
	"res://assets/audio/kenney/footstep_carpet_002.ogg",
	"res://assets/audio/kenney/footstep_carpet_003.ogg",
	"res://assets/audio/kenney/footstep_carpet_004.ogg",
]
const DOOR_ACTION_COLUMNS := 4
const DOOR_ACTION_ROWS := 2
const DOOR_ACTION_OPEN_SECONDS := 0.42
const DOOR_ACTION_KNOCK_SECONDS := 0.50
const LISTEN_CAMERA_OFFSET := Vector3(0.18, -0.06, -0.32)
const LISTEN_CAMERA_ROLL := deg_to_rad(-7.0)
const LISTEN_BLEND_FRACTION := 0.18
@export var speed := 4.0
@export var sprint_speed := 7.0
@export var acceleration := 30.0
@export var mouse_sensitivity := 0.0025
@export var gravity := 20.0
@export var interaction_distance := 2.6

@onready var camera: Camera3D = $Camera3D
@onready var door_action_sprite: Sprite2D = $DoorActionLayer/DoorActionSprite

var controller: Node = null
var level: Node3D = null
var hud: HotelHUD = null
var managed_mode := false

var _yaw := 0.0
var _pitch := 0.0
var current_interact: Node = null
var _wardrobe_interact: Node = null
var in_wardrobe := false
var _saved_pos := Vector3.ZERO
var _saved_yaw := 0.0

var safe_pos := Vector3.ZERO
var spawn_pos := Vector3.ZERO
var safe_world_bounds := Rect2()
var map_world_bounds := Rect2()
var level_configured := false

var stamina := 100.0
var max_stamina := 100.0
var is_sprinting := false
var selected_slot := 0

var notebook_open := false
var suitcase_open := false
var debug_map_open := false
var watch_open := false
var context_options: Array = []
var context_index := 0
var _context_target: Node = null

var _action_time_left := 0.0
var _action_total := 0.0
var _action_id := ""
var _action_label := ""
var _action_target: Node = null
var _action_callback: Callable
var footstep_player: AudioStreamPlayer
var _footstep_streams: Array[AudioStream] = []
var _footstep_distance := 0.0
var _last_footstep_index := -1
var _door_action_sequence := PackedInt32Array()
var _door_action_elapsed := 0.0
var _door_action_duration := 0.0
var _door_action_animating := false
var _door_action_id := ""
var _camera_neutral_position := Vector3.ZERO
var _camera_neutral_roll := 0.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = camera.rotation.x
	_camera_neutral_position = camera.position
	_camera_neutral_roll = camera.rotation.z
	floor_snap_length = 0.25
	floor_stop_on_slope = true
	_setup_footstep_audio()
	_setup_door_action_sprite()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if not managed_mode:
		hud = _HUD.new()
		add_child(hud)
	safe_pos = global_position
	spawn_pos = global_position
	if hud != null:
		hud.show_help("T 表  ·  N 本", 3.0)


func configure_runtime(p_controller: Node, p_hud: HotelHUD) -> void:
	managed_mode = true
	controller = p_controller
	hud = p_hud
	if is_inside_tree() and hud != null:
		hud.show_help("T 表  ·  N 本", 3.0)


func configure_floor(p_level: Node3D, start_position: Vector3, start_yaw := 0.0) -> void:
	reset_transient_floor_state()
	level = p_level
	global_position = start_position
	_yaw = start_yaw
	rotation.y = _yaw
	velocity = Vector3.ZERO
	_footstep_distance = 0.0
	spawn_pos = start_position
	safe_pos = start_position
	level_configured = true
	if level != null:
		if level.has_method("_map_world_bounds"):
			map_world_bounds = level._map_world_bounds()
		if level.has_method("_safe_world_bounds"):
			safe_world_bounds = level._safe_world_bounds()
		if hud != null and level.has_method("_create_map_texture"):
			hud.set_map_texture(level._create_map_texture())
		if hud != null:
			hud.set_level_info(int(level.get("map_seed")), int(level.get("rooms").size()))
	_update_debug_map()


func reset_transient_floor_state() -> void:
	cancel_timed_action("")
	stop_door_interaction()
	in_wardrobe = false
	_wardrobe_interact = null
	notebook_open = false
	suitcase_open = false
	debug_map_open = false
	_set_watch_open(false)
	_clear_context_action()
	if hud != null:
		hud.set_notebook([], false)
		hud.set_suitcase([], false)
		hud.set_map_open(false)


func configure_level(
	map_texture: Texture2D,
	world_map_bounds: Rect2,
	world_safe_bounds: Rect2,
	level_seed: int,
	room_count: int,
	start_position: Vector3
	) -> void:
	map_world_bounds = world_map_bounds
	safe_world_bounds = world_safe_bounds
	spawn_pos = start_position
	safe_pos = start_position
	level_configured = true
	level = get_parent() as Node3D
	if hud != null:
		hud.set_map_texture(map_texture)
		hud.set_level_info(level_seed, room_count)
	_update_debug_map()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, -PI / 2.0 + 0.05, PI / 2.0 - 0.05)
		rotation.y = _yaw
		camera.rotation.x = _pitch

	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_E:
			if event.pressed and not is_action_busy() and not _interaction_blocked():
				_execute_context_action()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_T:
			_set_watch_open(event.pressed)
			get_viewport().set_input_as_handled()
		elif event.pressed:
			match event.keycode:
				KEY_1, KEY_2, KEY_3, KEY_4:
					var pressed_slot := int(event.keycode - KEY_1)
					if suitcase_open and controller != null:
						if event.shift_pressed and controller.has_method("move_suitcase_slot_to_carry"):
							controller.move_suitcase_slot_to_carry(pressed_slot)
						elif controller.has_method("move_carry_slot_to_suitcase"):
							controller.move_carry_slot_to_suitcase(pressed_slot)
						refresh_suitcase_data()
					else:
						selected_slot = pressed_slot
						if controller != null and controller.has_method("set_selected_slot"):
							controller.set_selected_slot(selected_slot)
					get_viewport().set_input_as_handled()
				KEY_F:
					if controller != null and controller.has_method("use_selected_item"):
						controller.use_selected_item()
					get_viewport().set_input_as_handled()
				KEY_N:
					notebook_open = not notebook_open
					_refresh_notebook()
					get_viewport().set_input_as_handled()
				KEY_I:
					_toggle_suitcase()
					get_viewport().set_input_as_handled()
				KEY_F3:
					if OS.is_debug_build():
						debug_map_open = not debug_map_open
						_update_debug_map()
						get_viewport().set_input_as_handled()
				KEY_G:
					if controller != null and controller.has_method("drop_two_handed"):
						controller.drop_two_handed(get_drop_position())
					get_viewport().set_input_as_handled()
				KEY_R:
					if not _interaction_blocked() and not is_action_busy():
						_cycle_context_action()
						get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event.is_action_pressed("ui_cancel"):
		if suitcase_open:
			suitcase_open = false
			_refresh_suitcase()
		elif notebook_open:
			notebook_open = false
			_refresh_notebook()
		elif debug_map_open:
			debug_map_open = false
			_update_debug_map()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			if hud != null:
				hud.show_help("鼠标已释放 · 点击画面继续", 3.0)


func _set_watch_open(open: bool) -> void:
	watch_open = open
	if hud != null and hud.has_method("set_watch_open"):
		hud.set_watch_open(watch_open)


func _physics_process(delta: float) -> void:
	if _must_recover():
		_recover()
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

	var input := Vector2.ZERO
	if not in_wardrobe and not is_action_busy():
		if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
			input.y += 1.0
		if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
			input.y -= 1.0
		if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
			input.x -= 1.0
		if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
			input.x += 1.0
	input = input.limit_length()

	var two_handed := _is_two_handed()
	is_sprinting = not two_handed and Input.is_key_pressed(KEY_SHIFT) and input.length() > 0.1 and stamina > 1.0
	var move_speed := sprint_speed if is_sprinting else speed
	if two_handed:
		if input.length() > 0.1:
			stamina = maxf(0.0, stamina - 28.0 * delta)
		if stamina <= 0.0:
			move_speed = speed * 0.5
	elif is_sprinting:
		stamina = maxf(0.0, stamina - 28.0 * delta)
	else:
		stamina = minf(max_stamina, stamina + 18.0 * delta)

	var forward := -transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var wish := forward * input.y + right * input.x
	velocity.x = move_toward(velocity.x, wish.x * move_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, wish.z * move_speed, acceleration * delta)
	var position_before_move := global_position
	move_and_slide()
	var horizontal_travel := Vector2(
		global_position.x - position_before_move.x,
		global_position.z - position_before_move.z
	).length()
	_tick_footsteps(horizontal_travel, input.length() > 0.1, two_handed)

	if _must_recover():
		_recover()
		return
	if is_on_floor() and _is_level_position_safe(global_position):
		safe_pos = global_position
	_update_hud()


func _process(delta: float) -> void:
	_tick_door_interaction(delta)
	_tick_timed_action(delta)
	_update_interaction()
	_update_hud()


func begin_timed_action(duration: float, label: String, callback: Callable, action_id := "", target: Node = null) -> bool:
	if is_action_busy():
		return false
	_action_total = maxf(duration, 0.0)
	_action_time_left = _action_total
	_action_label = label
	_action_id = action_id
	_action_target = target
	_action_callback = callback
	if target is HotelInteractable and String((target as HotelInteractable).kind) == "door":
		play_door_interaction(action_id, _action_total)
	if controller != null and controller.has_method("on_player_action_started"):
		controller.on_player_action_started(action_id, target)
	if _action_total <= 0.0:
		_finish_timed_action()
	return true


func _setup_footstep_audio() -> void:
	if footstep_player != null:
		return
	footstep_player = AudioStreamPlayer.new()
	footstep_player.name = "Footsteps"
	footstep_player.volume_db = -13.0
	footstep_player.max_polyphony = 2
	add_child(footstep_player)
	for path in FOOTSTEP_PATHS:
		var stream := load(path) as AudioStream
		if stream != null:
			_footstep_streams.append(stream)


func _setup_door_action_sprite() -> void:
	if door_action_sprite == null:
		return
	door_action_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	door_action_sprite.hframes = DOOR_ACTION_COLUMNS
	door_action_sprite.vframes = DOOR_ACTION_ROWS
	door_action_sprite.visible = false
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_layout_door_action_sprite):
		viewport.size_changed.connect(_layout_door_action_sprite)
	_layout_door_action_sprite()


func _layout_door_action_sprite() -> void:
	if door_action_sprite == null or door_action_sprite.texture == null:
		return
	var viewport_size := Vector2(get_viewport().get_visible_rect().size)
	var frame_size := door_action_sprite.texture.get_size() / Vector2(DOOR_ACTION_COLUMNS, DOOR_ACTION_ROWS)
	var integer_scale := maxi(1, int(round(viewport_size.y * 0.72 / frame_size.y)))
	door_action_sprite.scale = Vector2.ONE * float(integer_scale)
	door_action_sprite.position = viewport_size - frame_size * float(integer_scale) * 0.5


func play_door_interaction(action_id: String, action_duration := 0.0) -> void:
	var sequence := PackedInt32Array()
	var duration := 0.0
	match action_id:
		"open_door":
			sequence = PackedInt32Array([0, 1, 2, 3])
			duration = DOOR_ACTION_OPEN_SECONDS
		"close_door":
			sequence = PackedInt32Array([3, 2, 1, 0])
			duration = DOOR_ACTION_OPEN_SECONDS
		"knock":
			# Contact poses land at 0.00, 0.17 and 0.33 seconds, matching the
			# three existing knock sounds before the player waits for an answer.
			sequence = PackedInt32Array([5, 4, 7, 6, 5, 4])
			duration = DOOR_ACTION_KNOCK_SECONDS
		"listen":
			duration = maxf(action_duration, 0.75)
		_:
			return
	_start_door_interaction(sequence, duration, action_id)


func _start_door_interaction(sequence: PackedInt32Array, duration: float, action_id: String) -> void:
	if door_action_sprite == null:
		return
	_reset_listen_camera()
	_door_action_sequence = sequence
	_door_action_elapsed = 0.0
	_door_action_duration = maxf(duration, 0.01)
	_door_action_animating = true
	_door_action_id = action_id
	if _door_action_sequence.is_empty():
		door_action_sprite.visible = false
	else:
		door_action_sprite.frame = _door_action_sequence[0]
		door_action_sprite.visible = true


func _tick_door_interaction(delta: float) -> void:
	if not _door_action_animating or door_action_sprite == null:
		return
	_door_action_elapsed += maxf(delta, 0.0)
	if _door_action_elapsed >= _door_action_duration:
		stop_door_interaction()
		return
	var progress := clampf(_door_action_elapsed / _door_action_duration, 0.0, 0.9999)
	if _door_action_id == "listen":
		_apply_listen_camera(progress)
	if not _door_action_sequence.is_empty():
		var sequence_index := mini(int(floor(progress * float(_door_action_sequence.size()))), _door_action_sequence.size() - 1)
		door_action_sprite.frame = _door_action_sequence[sequence_index]


func _apply_listen_camera(progress: float) -> void:
	if camera == null:
		return
	var enter_weight := smoothstep(0.0, LISTEN_BLEND_FRACTION, progress)
	var exit_weight := 1.0 - smoothstep(1.0 - LISTEN_BLEND_FRACTION, 1.0, progress)
	var weight := minf(enter_weight, exit_weight)
	camera.position = _camera_neutral_position.lerp(_camera_neutral_position + LISTEN_CAMERA_OFFSET, weight)
	camera.rotation.z = lerp_angle(_camera_neutral_roll, _camera_neutral_roll + LISTEN_CAMERA_ROLL, weight)


func _reset_listen_camera() -> void:
	if camera == null:
		return
	camera.position = _camera_neutral_position
	camera.rotation.z = _camera_neutral_roll


func stop_door_interaction() -> void:
	_door_action_animating = false
	_door_action_elapsed = 0.0
	_door_action_duration = 0.0
	_door_action_sequence = PackedInt32Array()
	_door_action_id = ""
	_reset_listen_camera()
	if door_action_sprite != null:
		door_action_sprite.visible = false


func is_door_interaction_animating() -> bool:
	return _door_action_animating


func _tick_footsteps(horizontal_travel: float, moving: bool, two_handed: bool) -> void:
	if not moving or not is_on_floor() or horizontal_travel <= 0.0001 or _footstep_streams.is_empty():
		return
	_footstep_distance += horizontal_travel
	var stride := 1.35 if is_sprinting else (1.95 if two_handed else 1.65)
	if _footstep_distance < stride:
		return
	_footstep_distance = fmod(_footstep_distance, stride)
	var next_index := randi_range(0, _footstep_streams.size() - 1)
	if _footstep_streams.size() > 1 and next_index == _last_footstep_index:
		next_index = (next_index + 1) % _footstep_streams.size()
	_last_footstep_index = next_index
	footstep_player.stream = _footstep_streams[next_index]
	footstep_player.pitch_scale = randf_range(0.92, 1.08) * (1.05 if is_sprinting else 1.0)
	footstep_player.volume_db = -11.0 if is_sprinting else (-15.0 if two_handed else -13.0)
	footstep_player.play()


func cancel_timed_action(message := "动作已中断") -> void:
	_action_time_left = 0.0
	_action_total = 0.0
	_action_id = ""
	_action_label = ""
	_action_target = null
	_action_callback = Callable()
	stop_door_interaction()
	if hud != null and not message.is_empty():
		hud.show_help(message, 1.5)


func is_action_busy() -> bool:
	return _action_total > 0.0 and _action_time_left > 0.0


func active_action_id() -> String:
	return _action_id


func _tick_timed_action(delta: float) -> void:
	if not is_action_busy():
		return
	_action_time_left = maxf(0.0, _action_time_left - delta)
	if hud != null:
		hud.set_prompt("%s  %.1fs" % [_action_label, _action_time_left])
	if _action_time_left <= 0.0:
		_finish_timed_action()


func _finish_timed_action() -> void:
	var callback := _action_callback
	var finished_action_id := _action_id
	_action_time_left = 0.0
	_action_total = 0.0
	_action_id = ""
	_action_label = ""
	_action_target = null
	_action_callback = Callable()
	if finished_action_id == "listen":
		stop_door_interaction()
	if callback.is_valid():
		callback.call()
	context_index = 0


func _execute_context_action() -> void:
	_refresh_context_actions()
	if _context_target == null or not is_instance_valid(_context_target) or context_options.is_empty():
		return
	var option: Dictionary = context_options[clampi(context_index, 0, context_options.size() - 1)]
	if not bool(option.get("enabled", true)):
		return
	_execute_action(_context_target, option)


func _cycle_context_action() -> void:
	_refresh_context_actions()
	if context_options.size() <= 1:
		return
	for offset in range(1, context_options.size() + 1):
		var candidate := posmod(context_index + offset, context_options.size())
		if bool((context_options[candidate] as Dictionary).get("enabled", true)):
			context_index = candidate
			break
	_update_context_prompt()


func _clear_context_action() -> void:
	context_options = []
	context_index = 0
	_context_target = null
	current_interact = null
	if hud != null:
		hud.set_prompt("")


func _interaction_blocked() -> bool:
	return notebook_open or suitcase_open or debug_map_open or watch_open


func _refresh_context_actions() -> void:
	if _context_target == null or not is_instance_valid(_context_target):
		context_options = []
		context_index = 0
		return
	context_options = _context_target.get_actions(self)
	context_index = clampi(context_index, 0, maxi(context_options.size() - 1, 0))


func _update_context_prompt() -> void:
	if hud == null or context_options.is_empty():
		if hud != null:
			hud.set_prompt("")
		return
	var option: Dictionary = context_options[clampi(context_index, 0, context_options.size() - 1)]
	var label := String(option.get("label", "交互"))
	hud.set_prompt("E  %s%s" % [label, "   R  ›" if context_options.size() > 1 else ""])


func _execute_action(target: Node, option: Dictionary) -> void:
	var action_id := String(option.get("id", ""))
	var label := String(option.get("label", "交互"))
	var duration := float(option.get("duration", 0.0))
	begin_timed_action(duration, label, func() -> void:
		if is_instance_valid(target):
			target.perform_action(action_id, self)
	, action_id, target)


func _update_hud() -> void:
	if hud == null:
		return
	hud.set_stamina(stamina, max_stamina, is_sprinting)
	if controller != null and controller.has_method("get_carry_slots_for_ui"):
		hud.set_inventory(controller.get_carry_slots_for_ui(), selected_slot, _is_two_handed())
	_update_debug_map()


func _refresh_notebook() -> void:
	if hud == null:
		return
	var entries: Variant = []
	if controller != null and controller.has_method("get_notebook_for_ui"):
		entries = controller.get_notebook_for_ui()
	hud.set_notebook(entries, notebook_open)


func refresh_notebook_data() -> void:
	_refresh_notebook()


func _toggle_suitcase() -> void:
	if controller == null or not controller.has_method("can_open_suitcase"):
		return
	if not controller.can_open_suitcase():
		if hud != null:
			hud.show_help("旅行箱必须放下并靠近后才能整理", 2.0)
		return
	suitcase_open = not suitcase_open
	_refresh_suitcase()


func _refresh_suitcase() -> void:
	if hud == null:
		return
	var slots: Array = []
	if controller != null and controller.has_method("get_suitcase_slots_for_ui"):
		slots = controller.get_suitcase_slots_for_ui()
	hud.set_suitcase(slots, suitcase_open)


func refresh_suitcase_data() -> void:
	_refresh_suitcase()


func _update_interaction() -> void:
	if hud == null:
		return
	if is_action_busy():
		return
	if _interaction_blocked():
		_clear_context_action()
		return
	var next_target: Node = null
	if in_wardrobe and _wardrobe_interact != null and is_instance_valid(_wardrobe_interact):
		next_target = _wardrobe_interact
	else:
		next_target = _raycast_interactable()
	if next_target != _context_target:
		context_index = 0
	_context_target = next_target
	current_interact = next_target
	_refresh_context_actions()
	_update_context_prompt()


func raycast_interactable(max_distance: float) -> Node:
	return _raycast_interactable(max_distance)


func _raycast_interactable(max_distance := -1.0) -> Node:
	var from := camera.global_position
	var distance := interaction_distance if max_distance <= 0.0 else max_distance
	var to := from + (-camera.global_transform.basis.z * distance)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var node := hit.get("collider") as Node
	while node != null:
		if node.is_in_group("interactable"):
			return node
		node = node.get_parent()
	return null


func _is_two_handed() -> bool:
	return controller != null and controller.has_method("is_two_handed") and controller.is_two_handed()


func get_drop_position() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	return global_position + forward.normalized() * 1.15 + Vector3(0.0, 0.08, 0.0)


func _must_recover() -> bool:
	if in_wardrobe:
		return false
	if global_position.y < -1.5:
		return true
	if not level_configured:
		return false
	var point := Vector2(global_position.x, global_position.z)
	if not safe_world_bounds.has_point(point):
		return true
	return not _is_level_position_safe(global_position)


func _is_level_position_safe(position: Vector3) -> bool:
	if not level_configured:
		return true
	if level != null and is_instance_valid(level) and level.has_method("is_position_walkable"):
		return level.is_position_walkable(position)
	return safe_world_bounds.has_point(Vector2(position.x, position.z))


func _recover() -> void:
	var target := safe_pos
	if not _is_level_position_safe(target):
		target = spawn_pos
	global_position = target + Vector3(0.0, 0.12, 0.0)
	velocity = Vector3.ZERO
	in_wardrobe = false
	_wardrobe_interact = null
	if hud != null:
		hud.show_help("已返回最近的安全位置", 2.0)


func enter_wardrobe(position: Vector3, yaw: float) -> void:
	_saved_pos = global_position
	_saved_yaw = _yaw
	global_position = position
	_yaw = yaw
	rotation.y = yaw
	velocity = Vector3.ZERO
	in_wardrobe = true


func exit_wardrobe() -> void:
	global_position = _saved_pos
	_yaw = _saved_yaw
	rotation.y = _saved_yaw
	velocity = Vector3.ZERO
	in_wardrobe = false
	_wardrobe_interact = null


func _update_debug_map() -> void:
	if hud == null or map_world_bounds.size.x <= 0.0 or map_world_bounds.size.y <= 0.0:
		return
	var normalized := Vector2(
		(global_position.x - map_world_bounds.position.x) / map_world_bounds.size.x,
		(global_position.z - map_world_bounds.position.y) / map_world_bounds.size.y
	)
	hud.set_debug_map(hud._map_texture, normalized, _yaw, debug_map_open)
