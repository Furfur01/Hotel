class_name ModuleKit
extends RefCounted

const TILE := 2.0
const HALF := 1.0
const WALL_H := 3.0
const WOBBLE_SNAP := 160.0

const _Inter = preload("res://interactable.gd")

var flicker: Array = []
var paintings: Array = []
var placeholder_tex: Texture2D

var wobble_shader: Shader

var wall_mesh: BoxMesh
var slab_mesh: BoxMesh
var wall_shape: BoxShape3D

var mat_wall: ShaderMaterial
var mat_floor: ShaderMaterial
var mat_ceil: ShaderMaterial
var mat_door: ShaderMaterial
var mat_frame: ShaderMaterial
var mat_bed: ShaderMaterial
var mat_linen: ShaderMaterial
var mat_wood: ShaderMaterial
var mat_brass: ShaderMaterial
var mat_rug: ShaderMaterial
var mat_metal: ShaderMaterial
var mat_stone: ShaderMaterial
var mat_mirror: StandardMaterial3D

func setup() -> void:
	wobble_shader = load("res://wobble.gdshader")
	wall_mesh = _boxmesh(Vector3(TILE, WALL_H, TILE))
	slab_mesh = _boxmesh(Vector3(TILE, 0.1, TILE))
	wall_shape = BoxShape3D.new()
	wall_shape.size = Vector3(TILE, WALL_H, TILE)
	_build_materials()
	_build_paintings()

func _build_materials() -> void:
	mat_wall = _wobble(_wallpaper_tex(), Vector2(1.0, 1.0), Color.WHITE, 0.95)
	mat_floor = _wobble(_carpet_tex(), Vector2(2.0, 2.0), Color.WHITE, 1.0)
	mat_ceil = _wobble(_ceiling_tex(), Vector2(2.0, 2.0), Color.WHITE, 0.9)
	mat_door = _wobble(_wood_tex(), Vector2(1.0, 1.0), Color.WHITE, 0.7)
	mat_frame = _wobble(_wood_tex(), Vector2(1.0, 1.0), Color(0.45, 0.34, 0.22), 0.8)
	mat_wood = _wobble(_wood_tex(), Vector2(1.0, 1.0), Color(0.55, 0.4, 0.25), 0.75)
	mat_bed = _wobble(_linen_tex(), Vector2(2.0, 2.0), Color(0.85, 0.8, 0.7), 1.0)
	mat_linen = _wobble(_linen_tex(), Vector2(1.0, 1.0), Color(0.9, 0.86, 0.78), 1.0)
	mat_brass = _wobble(_metal_tex(), Vector2(1.0, 1.0), Color(0.72, 0.55, 0.25), 0.3)
	mat_rug = _wobble(_rug_tex(), Vector2(1.0, 1.0), Color.WHITE, 1.0)
	mat_metal = _wobble(_metal_tex(), Vector2(1.0, 2.0), Color(0.5, 0.5, 0.52), 0.4)
	mat_stone = _wobble(_ceiling_tex(), Vector2(1.0, 2.0), Color(0.62, 0.58, 0.5), 0.5)
	mat_mirror = StandardMaterial3D.new()
	mat_mirror.albedo_color = Color(0.4, 0.44, 0.5)
	mat_mirror.roughness = 0.12
	mat_mirror.metallic = 0.0
	mat_mirror.emission_enabled = true
	mat_mirror.emission = Color(0.16, 0.19, 0.24)
	mat_mirror.emission_energy_multiplier = 0.5
	mat_mirror.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

func _wobble(tex: ImageTexture, tiling: Vector2, tint: Color, rough: float) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = wobble_shader
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("tiling", tiling)
	m.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b))
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("snap", WOBBLE_SNAP)
	return m

func _emit(color: Color, energy: float) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

func _paint_mat(tex: Texture2D) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_texture = tex
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission_energy_multiplier = 0.45
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.6
	return m

func _px(base: Color, spread: float) -> Color:
	var n = randf_range(-spread, spread)
	return Color(clampf(base.r + n, 0.0, 1.0), clampf(base.g + n, 0.0, 1.0), clampf(base.b + n, 0.0, 1.0))

func _ss(a: float, b: float, x: float) -> float:
	return clampf((x - a) / (b - a), 0.0, 1.0)

func _wallpaper_tex() -> ImageTexture:
	var s := 32
	var img = Image.create_empty(s, s, false, Image.FORMAT_RGB8)
	var base = Color(0.34, 0.12, 0.13)
	var gold = Color(0.62, 0.46, 0.2)
	for y in range(s):
		for x in range(s):
			var c = base
			if y <= 1:
				c = gold if y == 1 else Color(0.18, 0.08, 0.08)
			elif y >= 29:
				c = gold if y == 29 else Color(0.12, 0.06, 0.06)
			else:
				var dx = (x % 8) - 4
				var dy = (y % 8) - 4
				if abs(dx) + abs(dy) <= 1:
					c = gold
				elif x % 8 == 0:
					c = c.darkened(0.18)
			img.set_pixel(x, y, _px(c, 0.03))
	return ImageTexture.create_from_image(img)

func _carpet_tex() -> ImageTexture:
	var s := 32
	var img = Image.create_empty(s, s, false, Image.FORMAT_RGB8)
	var base = Color(0.28, 0.1, 0.1)
	var trim = Color(0.5, 0.36, 0.16)
	for y in range(s):
		for x in range(s):
			var c = base
			if x < 2 or y < 2 or x > 29 or y > 29:
				c = trim
			elif (x + y) % 6 == 0:
				c = c.darkened(0.12)
			if randf() < 0.04:
				c = c.darkened(0.25)
			img.set_pixel(x, y, _px(c, 0.05))
	return ImageTexture.create_from_image(img)

func _rug_tex() -> ImageTexture:
	var s := 32
	var img = Image.create_empty(s, s, false, Image.FORMAT_RGB8)
	var base = Color(0.4, 0.16, 0.16)
	var gold = Color(0.6, 0.44, 0.2)
	for y in range(s):
		for x in range(s):
			var c = base
			if x < 3 or y < 3 or x > 28 or y > 28:
				c = gold
			elif abs(x - 16) + abs(y - 16) < 6:
				c = gold.darkened(0.1)
			img.set_pixel(x, y, _px(c, 0.03))
	return ImageTexture.create_from_image(img)

func _ceiling_tex() -> ImageTexture:
	var s := 32
	var img = Image.create_empty(s, s, false, Image.FORMAT_RGB8)
	var base = Color(0.6, 0.55, 0.44)
	for y in range(s):
		for x in range(s):
			var c = base
			if x % 16 == 0 or y % 16 == 0:
				c = c.darkened(0.3)
			img.set_pixel(x, y, _px(c, 0.03))
	return ImageTexture.create_from_image(img)

func _wood_tex() -> ImageTexture:
	var s := 32
	var img = Image.create_empty(s, s, false, Image.FORMAT_RGB8)
	var base = Color(0.3, 0.17, 0.09)
	for y in range(s):
		for x in range(s):
			var grain = sin(y * 0.8 + sin(x * 0.3) * 2.0) * 0.05
			var c = Color(clampf(base.r + grain, 0.0, 1.0), clampf(base.g + grain, 0.0, 1.0), clampf(base.b + grain * 0.5, 0.0, 1.0))
			img.set_pixel(x, y, _px(c, 0.03))
	return ImageTexture.create_from_image(img)

func _metal_tex() -> ImageTexture:
	var s := 32
	var img = Image.create_empty(s, s, false, Image.FORMAT_RGB8)
	var base = Color(0.5, 0.5, 0.52)
	for y in range(s):
		for x in range(s):
			img.set_pixel(x, y, _px(base, 0.05))
	return ImageTexture.create_from_image(img)

func _linen_tex() -> ImageTexture:
	var s := 32
	var img = Image.create_empty(s, s, false, Image.FORMAT_RGB8)
	var base = Color(0.7, 0.66, 0.56)
	for y in range(s):
		for x in range(s):
			var weave = 0.03 if (x + y) % 2 == 0 else -0.03
			var c = Color(base.r + weave, base.g + weave, base.b + weave)
			img.set_pixel(x, y, _px(c, 0.02))
	return ImageTexture.create_from_image(img)

func _build_paintings() -> void:
	paintings = []
	for i in range(1, 9):
		var path := "res://assets/paintings/final/portrait_%02d.png" % i
		var texture := load(path) as Texture2D
		if texture != null:
			paintings.append(texture)
	if paintings.is_empty():
		for i in range(8):
			paintings.append(_sepia_portrait())
	placeholder_tex = paintings[0]

func _sepia_portrait() -> ImageTexture:
	var s := 48
	var img = Image.create_empty(s, s, false, Image.FORMAT_RGB8)
	var cx = s * 0.5
	var bg = Color(0.52, 0.4, 0.23).lerp(Color(0.42, 0.32, 0.18), randf())
	var fig = bg.lerp(Color(0.3, 0.22, 0.12), 0.5) if randf() < 0.5 else bg.lerp(Color(0.66, 0.54, 0.34), 0.5)
	var face = fig.lerp(Color(0.72, 0.6, 0.4), 0.6)
	var hx = cx + randf_range(-3.0, 3.0)
	var hy = s * 0.34 + randf_range(-2.0, 2.0)
	var hrx = s * randf_range(0.13, 0.17)
	var hry = s * randf_range(0.16, 0.2)
	var sy0 = hy + hry * 0.75
	var has_eyes = randf() < 0.35
	var ex = hrx * 0.42
	var ey = hy - hry * 0.05
	var scratch_x = randi() % s
	var scratch_x2 = randi() % s
	for y in range(s):
		for x in range(s):
			var vx = (x - cx) / (s * 0.5)
			var vy = (y - s * 0.5) / (s * 0.5)
			var vig = 1.0 - clampf(sqrt(vx * vx + vy * vy) - 0.5, 0.0, 1.0) * 0.7
			var c = bg * vig
			var dxh = (x - hx) / hrx
			var dyh = (y - hy) / hry
			var dh = sqrt(dxh * dxh + dyh * dyh)
			var head_m = _ss(1.0, 0.65, dh)
			var shoulder_m = 0.0
			if y > sy0:
				var wdt = 0.32 + (y - sy0) / maxf(s - sy0, 1.0) * 0.5
				var sx = abs(x - cx) / (s * wdt)
				shoulder_m = _ss(1.0, 0.6, sx) * _ss(float(s) + 2.0, sy0, float(y))
			var fig_m = maxf(head_m, shoulder_m)
			c = c.lerp(fig, fig_m)
			var fdx = (x - hx) / (hrx * 0.62)
			var fdy = (y - (hy - hry * 0.1)) / (hry * 0.7)
			var face_m = head_m * _ss(1.0, 0.5, sqrt(fdx * fdx + fdy * fdy))
			c = c.lerp(face, face_m * 0.55)
			if has_eyes:
				var el = sqrt(pow(x - (hx - ex), 2) + pow(y - ey, 2))
				var er = sqrt(pow(x - (hx + ex), 2) + pow(y - ey, 2))
				var eye_m = maxf(_ss(1.4, 0.0, el), _ss(1.4, 0.0, er))
				c = c.lerp(Color(0.12, 0.09, 0.06), eye_m * 0.5 * head_m)
			c = _px(c, 0.045)
			if x == scratch_x or x == scratch_x2:
				c = c.lerp(Color(0.7, 0.6, 0.4), 0.25)
			if y < 2 or y > s - 3:
				c = c.darkened(0.3)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _pick_paint() -> Texture2D:
	if paintings.size() > 0:
		return paintings[randi() % paintings.size()]
	return placeholder_tex

func _boxmesh(size: Vector3) -> BoxMesh:
	var m = BoxMesh.new()
	m.size = size
	return m

func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, ry: float = 0.0) -> MeshInstance3D:
	var m = MeshInstance3D.new()
	m.mesh = mesh
	if mat != null:
		m.material_override = mat
	m.position = pos
	if ry != 0.0:
		m.rotation.y = ry
	parent.add_child(m)
	return m

func _sb(parent: Node3D, shape: Shape3D, pos: Vector3) -> StaticBody3D:
	var b = StaticBody3D.new()
	b.position = pos
	var c = CollisionShape3D.new()
	c.shape = shape
	b.add_child(c)
	parent.add_child(b)
	return b

func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, ry: float = 0.0) -> MeshInstance3D:
	return _mi(parent, _boxmesh(size), mat, pos, ry)

func _boxc(parent: Node3D, size: Vector3, mat: Material, pos: Vector3) -> void:
	_box(parent, size, mat, pos)
	var sh = BoxShape3D.new()
	sh.size = size
	_sb(parent, sh, pos)

func _ry(facing: Vector2i) -> float:
	if facing.x == 1:
		return -PI / 2.0
	if facing.x == -1:
		return PI / 2.0
	if facing.y == 1:
		return PI
	return 0.0

func _fv(facing: Vector2i) -> Vector3:
	return Vector3(facing.x, 0.0, facing.y)

func _yaw_of(vec: Vector3) -> float:
	return atan2(-vec.x, -vec.z)

func _sz2(dir: Vector2i, d_door: float, d_perp: float, h: float) -> Vector3:
	if abs(dir.x) == 1:
		return Vector3(d_door, h, d_perp)
	return Vector3(d_perp, h, d_door)

func _add_flicker(omni: OmniLight3D, panel_mat: Material, base: float) -> void:
	flicker.append({
		"omni": omni,
		"panel_mat": panel_mat,
		"base": base,
		"phase": randf() * TAU,
		"timer": randf_range(1.0, 6.0),
		"flick": 0.0,
	})

func wall_segment() -> Node3D:
	var root = Node3D.new()
	_mi(root, wall_mesh, mat_wall, Vector3(0, WALL_H * 0.5, 0))
	_sb(root, wall_shape, Vector3(0, WALL_H * 0.5, 0))
	return root

func floor_tile() -> Node3D:
	var root = Node3D.new()
	_mi(root, slab_mesh, mat_floor, Vector3(0, -0.05, 0))
	return root

func ceiling_tile() -> Node3D:
	var root = Node3D.new()
	var m = _mi(root, slab_mesh, mat_ceil, Vector3(0, WALL_H + 0.05, 0))
	m.add_to_group("ceiling")
	return root

func door_unit(dir: Vector2i) -> Node3D:
	var root = Node3D.new()
	var perp = Vector2i(-dir.y, dir.x)
	var theta = atan2(-perp.y, perp.x)
	_box(root, _sz2(dir, 0.2, 0.12, 2.2), mat_frame, Vector3(perp.x * 0.85, 1.1, perp.y * 0.85))
	_box(root, _sz2(dir, 0.2, 0.12, 2.2), mat_frame, Vector3(-perp.x * 0.85, 1.1, -perp.y * 0.85))
	_box(root, _sz2(dir, 0.2, 1.9, 0.2), mat_frame, Vector3(0, 2.3, 0))
	var pivot = Node3D.new()
	pivot.position = Vector3(-perp.x * 0.8, 0.0, -perp.y * 0.8)
	pivot.rotation.y = theta
	_mi(pivot, _boxmesh(Vector3(1.6, 2.2, 0.06)), mat_door, Vector3(0.8, 1.1, 0))
	var pbody = StaticBody3D.new()
	pbody.position = Vector3(0.8, 1.1, 0)
	var pc = CollisionShape3D.new()
	var ps = BoxShape3D.new()
	ps.size = Vector3(1.6, 2.2, 0.06)
	pc.shape = ps
	pbody.add_child(pc)
	pivot.add_child(pbody)
	root.add_child(pivot)
	root.set_script(_Inter)
	root.kind = "door"
	root.pivot = pivot
	root.door_theta = theta
	return root

func wall_sconce(facing: Vector2i) -> Node3D:
	var root = Node3D.new()
	var ry = _ry(facing)
	var shade_mat = _emit(Color(1.0, 0.78, 0.42), 2.2)
	_box(root, Vector3(0.12, 0.18, 0.3), mat_brass, Vector3(0, 0, 0), ry)
	_box(root, Vector3(0.28, 0.32, 0.18), shade_mat, _fv(facing) * -0.12, ry)
	var omni = OmniLight3D.new()
	omni.position = _fv(facing) * -0.35
	omni.light_color = Color(1.0, 0.8, 0.5)
	omni.light_energy = 0.9
	omni.omni_range = 4.0
	root.add_child(omni)
	_add_flicker(omni, shade_mat, 0.9)
	return root

func framed_painting(face_into: Vector2i, w: float, h: float) -> Node3D:
	var root = Node3D.new()
	var n = Vector3(face_into.x, 0.0, face_into.y)
	var ry = atan2(n.x, n.z)
	var tex = _pick_paint()
	var sz = tex.get_size()
	var aspect = sz.x / float(maxi(sz.y, 1))
	var ph = h
	var pw = clampf(ph * aspect, 0.5, 1.7)
	_box(root, Vector3(pw + 0.14, ph + 0.14, 0.06), mat_frame, n * -0.04, ry)
	_mi(root, _boxmesh(Vector3(pw, ph, 0.02)), _paint_mat(tex), n * -0.02, ry)
	return root

func room_module(kind: int, door_dir: Vector2i) -> Node3D:
	var root = Node3D.new()
	var depth = 3 if kind == 1 else 2
	var hw = 2 if kind == 1 else 1
	var inw_a = float(depth) - 0.15
	var inw_p = float(2 * hw + 1) - 0.15
	var d3 = Vector3(door_dir.x, 0.0, door_dir.y)
	var perp_dir = Vector2i(-door_dir.y, door_dir.x)
	var p3 = Vector3(perp_dir.x, 0.0, perp_dir.y)
	var door_opening: float = 1.8
	var front_depth := float(depth)
	var front_half_width := float(2 * hw + 1)
	var front_side_span: float = front_half_width - door_opening * 0.5
	for side in [-1.0, 1.0]:
		var front_side_pos: Vector3 = d3 * front_depth + p3 * side * (door_opening * 0.5 + front_side_span * 0.5)
		_boxc(root, _sz2(door_dir, 0.12, front_side_span, WALL_H), mat_wall, front_side_pos + Vector3(0, WALL_H * 0.5, 0))
	_boxc(root, _sz2(door_dir, 0.12, door_opening, 0.7), mat_wall, d3 * front_depth + Vector3(0, 2.65, 0))
	var n_door = Vector2i(-door_dir.x, -door_dir.y)
	var n_perp = Vector2i(-perp_dir.x, -perp_dir.y)
	var bed_l = 2.2 if kind == 1 else 1.9
	var bed_w = 1.8 if kind == 1 else 1.4
	var bed_along = -(inw_a - bed_l * 0.5)
	_box(root, _sz2(door_dir, bed_l, bed_w, 0.45), mat_linen, d3 * bed_along + Vector3(0, 0.225, 0))
	_box(root, _sz2(door_dir, 0.12, bed_w, 1.0), mat_wood, d3 * -(inw_a - 0.06) + Vector3(0, 0.5, 0))
	_box(root, _sz2(door_dir, 0.3, bed_w * 0.8, 0.18), mat_bed, d3 * -(inw_a - 0.4) + Vector3(0, 0.52, 0))
	var bsh = BoxShape3D.new()
	bsh.size = _sz2(door_dir, bed_l, bed_w, 0.5)
	_sb(root, bsh, d3 * bed_along + Vector3(0, 0.25, 0))
	for side in [1.0, -1.0]:
		var noff = d3 * -(inw_a - 0.5) + p3 * side * (bed_w * 0.5 + 0.35)
		_box(root, _sz2(door_dir, 0.4, 0.4, 0.5), mat_wood, noff + Vector3(0, 0.25, 0))
		_box(root, _sz2(door_dir, 0.22, 0.22, 0.24), _emit(Color(1.0, 0.82, 0.5), 1.5), noff + Vector3(0, 0.62, 0))
	_boxc(root, _sz2(door_dir, 0.4, bed_w * 0.9, 0.45), mat_wood, d3 * (bed_along + bed_l * 0.5 + 0.35) + Vector3(0, 0.225, 0))
	var dress_p = inw_p - 0.25
	_boxc(root, _sz2(perp_dir, 0.5, 1.2, 0.8), mat_wood, p3 * dress_p + d3 * 0.5 + Vector3(0, 0.4, 0))
	_box(root, _sz2(perp_dir, 0.05, 1.0, 1.2), mat_mirror, p3 * (inw_p - 0.03) + d3 * 0.5 + Vector3(0, 1.5, 0))
	_box(root, _sz2(perp_dir, 0.4, 0.4, 0.45), mat_linen, p3 * (dress_p - 0.55) + d3 * 0.5 + Vector3(0, 0.225, 0))
	var ward_p = -(inw_p - 0.5)
	_build_wardrobe(root, door_dir, perp_dir, p3 * ward_p + d3 * -0.5)
	_boxc(root, _sz2(perp_dir, 0.8, 0.8, 0.5), mat_linen, p3 * -(inw_p - 0.5) + d3 * 1.3 + Vector3(0, 0.25, 0))
	_box(root, _sz2(perp_dir, 0.1, 0.7, 0.7), mat_linen, p3 * -(inw_p - 0.12) + d3 * 1.3 + Vector3(0, 0.6, 0))
	_boxc(root, _sz2(door_dir, 0.6, 0.6, 0.5), mat_wood, p3 * 1.3 + d3 * -1.3 + Vector3(0, 0.25, 0))
	_box(root, _sz2(door_dir, 0.18, 0.18, 0.3), mat_brass, p3 * 1.3 + d3 * -1.3 + Vector3(0, 0.62, 0))
	var pn_back = framed_painting(door_dir, 1.2, 0.85)
	pn_back.position = d3 * -(inw_a - 0.04) + Vector3(0, 1.7, 0)
	root.add_child(pn_back)
	var pn_front = framed_painting(n_door, 0.9, 0.7)
	pn_front.position = d3 * (inw_a - 0.04) + p3 * 1.3 + Vector3(0, 1.7, 0)
	root.add_child(pn_front)
	var pn_side_a = framed_painting(n_perp, 1.0, 0.75)
	pn_side_a.position = p3 * (inw_p - 0.04) + d3 * -1.2 + Vector3(0, 1.7, 0)
	root.add_child(pn_side_a)
	var pn_side_b = framed_painting(perp_dir, 1.0, 0.75)
	pn_side_b.position = p3 * -(inw_p - 0.04) + d3 * 1.3 + Vector3(0, 1.7, 0)
	root.add_child(pn_side_b)
	if kind == 1:
		_box(root, _sz2(door_dir, 0.9, 1.7, 0.45), mat_linen, p3 * (inw_p - 0.45) + d3 * 1.5 + Vector3(0, 0.225, 0))
		_box(root, _sz2(door_dir, 0.7, 0.7, 0.4), mat_wood, p3 * -1.7 + d3 * 1.5 + Vector3(0, 0.2, 0))
		var pn_extra = framed_painting(n_perp, 1.3, 0.95)
		pn_extra.position = p3 * (inw_p - 0.04) + d3 * 1.5 + Vector3(0, 1.7, 0)
		root.add_child(pn_extra)
	_box(root, _sz2(door_dir, inw_a * 1.4, inw_p * 1.4, 0.04), mat_rug, Vector3(0, 0.02, 0))
	var disc = _box(root, Vector3(0.8, 0.08, 0.8), _emit(Color(1.0, 0.85, 0.55), 1.3), Vector3(0, WALL_H - 0.05, 0))
	var room_light = OmniLight3D.new()
	room_light.position = Vector3(0, WALL_H - 0.3, 0)
	room_light.light_color = Color(1.0, 0.82, 0.52)
	room_light.light_energy = 1.6 if kind == 1 else 1.2
	room_light.omni_range = 7.0 if kind == 1 else 5.0
	root.add_child(room_light)
	_add_flicker(room_light, disc.material_override, room_light.light_energy)
	return root


func function_room_module(room_type: String, kind: int, door_dir: Vector2i) -> Node3D:
	var root := Node3D.new()
	var depth := 3 if kind == 1 else 2
	var hw := 2 if kind == 1 else 1
	var d3 := Vector3(door_dir.x, 0.0, door_dir.y)
	var perp_dir := Vector2i(-door_dir.y, door_dir.x)
	var p3 := Vector3(perp_dir.x, 0.0, perp_dir.y)
	var door_opening := 1.8
	var front_depth := float(depth)
	var front_half_width := float(2 * hw + 1)
	var front_side_span := front_half_width - door_opening * 0.5
	for side in [-1.0, 1.0]:
		var front_side_pos: Vector3 = d3 * front_depth + p3 * side * (door_opening * 0.5 + front_side_span * 0.5)
		_boxc(root, _sz2(door_dir, 0.12, front_side_span, WALL_H), mat_wall, front_side_pos + Vector3(0.0, WALL_H * 0.5, 0.0))
	_boxc(root, _sz2(door_dir, 0.12, door_opening, 0.7), mat_wall, d3 * front_depth + Vector3(0.0, 2.65, 0.0))

	match room_type:
		"storage":
			for side in [-1.0, 1.0]:
				var shelf_pos: Vector3 = p3 * side * 1.35 - d3 * 0.6
				_boxc(root, _sz2(perp_dir, 0.48, 1.8, 2.15), mat_wood, shelf_pos + Vector3(0.0, 1.075, 0.0))
				for level in [0.45, 1.05, 1.65]:
					_box(root, _sz2(perp_dir, 0.62, 1.95, 0.08), mat_brass, shelf_pos + Vector3(0.0, level, 0.0))
			_box(root, Vector3(0.72, 0.62, 0.72), mat_wood, -d3 * 1.45 + Vector3(0.0, 0.31, 0.0))
		"laundry":
			for side in [-0.8, 0.8]:
				var machine_pos: Vector3 = p3 * side - d3 * 1.15
				_boxc(root, _sz2(door_dir, 0.82, 0.72, 0.88), mat_metal, machine_pos + Vector3(0.0, 0.44, 0.0))
				var drum_mat := _emit(Color(0.12, 0.15, 0.16), 0.25)
				_box(root, _sz2(door_dir, 0.05, 0.43, 0.43), drum_mat, machine_pos + d3 * 0.43 + Vector3(0.0, 0.46, 0.0))
			_boxc(root, Vector3(0.9, 0.62, 0.65), mat_linen, p3 * 1.55 + Vector3(0.0, 0.31, 0.0))
		"maintenance":
			_boxc(root, _sz2(door_dir, 0.72, 2.4, 0.82), mat_wood, -d3 * 1.35 + Vector3(0.0, 0.41, 0.0))
			for side in [-0.65, 0.0, 0.65]:
				var panel_pos: Vector3 = p3 * side - d3 * 1.77 + Vector3(0.0, 1.72, 0.0)
				_box(root, _sz2(door_dir, 0.08, 0.5, 0.72), mat_metal, panel_pos)
				_box(root, Vector3(0.12, 0.12, 0.12), _emit(Color(0.75, 0.18, 0.12), 1.5), panel_pos + d3 * 0.05)
		"security":
			for side in [-1.05, 0.0, 1.05]:
				_boxc(root, _sz2(perp_dir, 0.48, 0.78, 1.9), mat_metal, p3 * side - d3 * 1.3 + Vector3(0.0, 0.95, 0.0))
			_boxc(root, _sz2(door_dir, 0.68, 1.8, 0.78), mat_wood, d3 * 0.25 + Vector3(0.0, 0.39, 0.0))
		"service_elevator":
			_boxc(root, _sz2(door_dir, 0.18, 2.65, 2.45), mat_metal, -d3 * 1.65 + Vector3(0.0, 1.225, 0.0))
			_box(root, _sz2(door_dir, 0.08, 0.1, 2.1), mat_brass, -d3 * 1.76 + Vector3(0.0, 1.2, 0.0))
			_boxc(root, Vector3(1.15, 0.62, 0.72), mat_metal, p3 * 1.25 + Vector3(0.0, 0.31, 0.0))
		_:
			_boxc(root, Vector3(1.2, 0.8, 1.2), mat_wood, -d3 + Vector3(0.0, 0.4, 0.0))

	var lamp_material := _emit(Color(0.78, 0.88, 0.82), 1.2)
	var disc := _box(root, Vector3(0.8, 0.08, 0.8), lamp_material, Vector3(0.0, WALL_H - 0.05, 0.0))
	var room_light := OmniLight3D.new()
	room_light.position = Vector3(0.0, WALL_H - 0.3, 0.0)
	room_light.light_color = Color(0.74, 0.86, 0.82)
	room_light.light_energy = 1.05
	room_light.omni_range = 5.5
	root.add_child(room_light)
	_add_flicker(room_light, disc.material_override, room_light.light_energy)
	return root

func _build_wardrobe(parent: Node3D, door_dir: Vector2i, perp_dir: Vector2i, center: Vector3) -> void:
	var wr = Node3D.new()
	wr.position = center
	_boxc(wr, _sz2(door_dir, 1.6, 0.05, 2.2), mat_wood, Vector3(-perp_dir.x * 0.475, 1.1, -perp_dir.y * 0.475))
	_boxc(wr, _sz2(door_dir, 0.05, 1.0, 2.2), mat_wood, Vector3(door_dir.x * 0.775, 1.1, door_dir.y * 0.775))
	_boxc(wr, _sz2(door_dir, 0.05, 1.0, 2.2), mat_wood, Vector3(-door_dir.x * 0.775, 1.1, -door_dir.y * 0.775))
	_boxc(wr, _sz2(door_dir, 1.6, 1.0, 0.1), mat_wood, Vector3(0, 2.15, 0))
	_boxc(wr, _sz2(door_dir, 1.6, 1.0, 0.1), mat_wood, Vector3(0, 0.05, 0))
	_boxc(wr, _sz2(door_dir, 0.77, 0.05, 2.1), mat_wood, Vector3(-door_dir.x * 0.4 + perp_dir.x * 0.475, 1.05, -door_dir.y * 0.4 + perp_dir.y * 0.475))
	_boxc(wr, _sz2(door_dir, 0.77, 0.05, 2.1), mat_wood, Vector3(door_dir.x * 0.4 + perp_dir.x * 0.475, 1.05, door_dir.y * 0.4 + perp_dir.y * 0.475))
	_boxc(wr, _sz2(door_dir, 0.73, 0.05, 2.1), mat_wood, Vector3(perp_dir.x * 0.475 + door_dir.x * 0.435, 1.05, perp_dir.y * 0.475 + door_dir.y * 0.435))
	_boxc(wr, _sz2(door_dir, 0.73, 0.05, 2.1), mat_wood, Vector3(perp_dir.x * 0.475 - door_dir.x * 0.435, 1.05, perp_dir.y * 0.475 - door_dir.y * 0.435))
	wr.set_script(_Inter)
	wr.kind = "wardrobe"
	wr.inner_yaw = _yaw_of(Vector3(perp_dir.x, 0.0, perp_dir.y))
	parent.add_child(wr)

func lobby_column() -> Node3D:
	var root = Node3D.new()
	_boxc(root, Vector3(0.5, WALL_H, 0.5), mat_stone, Vector3(0, WALL_H * 0.5, 0))
	return root

func lobby_desk() -> Node3D:
	var root = Node3D.new()
	_boxc(root, Vector3(2.6, 1.1, 0.6), mat_wood, Vector3(0, 0.55, 0))
	_box(root, Vector3(2.8, 0.1, 0.8), mat_stone, Vector3(0, 1.12, 0))
	_box(root, Vector3(2.6, 0.5, 0.1), mat_wood, Vector3(0, 1.35, -0.25))
	return root

func lobby_chandelier() -> Node3D:
	var root = Node3D.new()
	_box(root, Vector3(0.06, 0.7, 0.06), mat_brass, Vector3(0, WALL_H - 0.35, 0))
	_box(root, Vector3(1.4, 0.16, 1.4), _emit(Color(1.0, 0.84, 0.55), 2.4), Vector3(0, WALL_H - 0.78, 0))
	var omni = OmniLight3D.new()
	omni.position = Vector3(0, WALL_H - 1.0, 0)
	omni.light_color = Color(1.0, 0.85, 0.58)
	omni.light_energy = 2.6
	omni.omni_range = 13.0
	root.add_child(omni)
	return root

func elevator_module() -> Node3D:
	var root = Node3D.new()
	_box(root, Vector3(0.1, 2.4, 2.4), mat_metal, Vector3(0, 1.2, 0))
	_box(root, Vector3(0.08, 2.2, 0.95), mat_metal, Vector3(-0.06, 1.1, -0.48))
	_box(root, Vector3(0.08, 2.2, 0.95), mat_metal, Vector3(-0.06, 1.1, 0.48))
	var glow = _box(root, Vector3(0.04, 0.3, 0.6), _emit(Color(0.8, 0.2, 0.2), 2.0), Vector3(-0.12, 2.2, 0))
	glow.material_override = _emit(Color(0.8, 0.2, 0.2), 2.0)
	return root
