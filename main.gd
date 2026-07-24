extends Node3D

var player: RigidBody3D
var camera: Camera3D
var spawn := Vector3(0, 1.5, 0)

func _ready() -> void:
	_add_environment()
	_add_sun()
	_add_ground()
	_add_walls()
	_add_player()
	_add_boxes()
	_add_camera()
	_add_ui()

func _physics_process(_delta: float) -> void:
	var input := Vector3.ZERO
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input.z -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input.z += 1.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input.x += 1.0
	player.apply_central_force(input * 30.0)

	var target := player.position + Vector3(0, 6, 12)
	camera.position = camera.position.lerp(target, 0.1)
	camera.look_at(player.position, Vector3.UP)

	if player.position.y < -20:
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.position = spawn

func _add_environment() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.5, 0.9)
	sky_mat.sky_horizon_color = Color(0.7, 0.8, 0.95)
	sky_mat.ground_horizon_color = Color(0.4, 0.4, 0.4)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env_node.environment = env
	add_child(env_node)

func _add_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)

func _add_ground() -> void:
	var ground := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	mesh.mesh = plane
	mesh.material_override = _material(Color(0.35, 0.6, 0.35))
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40, 0.2, 40)
	col.shape = shape
	col.position.y = -0.1
	ground.add_child(mesh)
	ground.add_child(col)
	add_child(ground)

func _add_walls() -> void:
	var half := 20.0
	var h := 1.5
	var t := 0.5
	var specs := [
		[Vector3(0, h / 2.0, -half), Vector3(40 + t, h, t)],
		[Vector3(0, h / 2.0, half), Vector3(40 + t, h, t)],
		[Vector3(-half, h / 2.0, 0), Vector3(t, h, 40 + t)],
		[Vector3(half, h / 2.0, 0), Vector3(t, h, 40 + t)],
	]
	for s in specs:
		var wall := StaticBody3D.new()
		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = s[1]
		mesh.mesh = box_mesh
		mesh.material_override = _material(Color(0.6, 0.5, 0.4))
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = s[1]
		col.shape = shape
		wall.position = s[0]
		wall.add_child(mesh)
		wall.add_child(col)
		add_child(wall)

func _add_player() -> void:
	player = RigidBody3D.new()
	player.mass = 2.0
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	mesh.mesh = sphere
	mesh.material_override = _material(Color(0.9, 0.2, 0.2))
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.5
	col.shape = shape
	player.add_child(mesh)
	player.add_child(col)
	player.position = spawn
	add_child(player)

func _add_boxes() -> void:
	var colors := [Color(0.2, 0.6, 0.9), Color(0.9, 0.8, 0.2), Color(0.7, 0.3, 0.8), Color(0.2, 0.8, 0.7)]
	var positions := [Vector3(-4, 0.5, -6), Vector3(3, 0.5, -8), Vector3(6, 0.5, -4), Vector3(0, 0.5, -12)]
	for i in range(positions.size()):
		var box := RigidBody3D.new()
		var mesh := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(1, 1, 1)
		mesh.mesh = box_mesh
		mesh.material_override = _material(colors[i])
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1, 1, 1)
		col.shape = shape
		box.add_child(mesh)
		box.add_child(col)
		box.position = positions[i]
		add_child(box)

func _add_camera() -> void:
	camera = Camera3D.new()
	camera.position = spawn + Vector3(0, 6, 12)
	camera.fov = 70.0
	add_child(camera)

func _add_ui() -> void:
	var canvas := CanvasLayer.new()
	var label := Label.new()
	label.text = "方向键 / WASD 移动小球，去撞飞那些方块吧！"
	label.position = Vector2(24, 20)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	canvas.add_child(label)
	add_child(canvas)

func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m
