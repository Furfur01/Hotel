class_name HotelHUD
extends CanvasLayer

signal capture_scare_finished

## Native 1920 x 1080 HUD.  Text is rendered at its final screen size instead
## of rasterising a 5–8 px font and enlarging the completed viewport.

const INK := Color(0.045, 0.037, 0.029, 0.94)
const INK_SOFT := Color(0.045, 0.037, 0.029, 0.80)
const INK_GLASS := Color(0.045, 0.037, 0.029, 0.68)
const PAPER := Color(0.88, 0.83, 0.68)
const PAPER_DIM := Color(0.60, 0.56, 0.46)
const BRASS := Color(0.72, 0.53, 0.24)
const BRASS_BRIGHT := Color(0.92, 0.72, 0.32)
const DANGER := Color(0.78, 0.23, 0.17)
const SAFE := Color(0.38, 0.70, 0.48)
const DISABLED := Color(0.30, 0.28, 0.24)
const MAX_NOTEBOOK_ROWS := 14
const NOTEBOOK_SOURCE_COUNT := 4
const MAP_DRAW_SIZE := 700.0
const DAY_DURATION := 240.0
const NIGHT_DURATION := 120.0
const FOG_MASK_SIZE := 96
const FOG_REVEAL_RADIUS := 9
const NOTE_MAP_DRAW_SIZE := 650.0
const NOTE_MAP_OFFSET := Vector2(0.0, 55.0)
const ITEM_ICON_DIR := "res://assets/icons/final/"
const UI_FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const NOTE_FONT_PATH := "res://assets/fonts/MaShanZheng-Regular.ttf"
const NOTEBOOK_TEXTURE_PATH := "res://assets/ui/field_notebook_pixel_v3.png"
const NOTE_MARK_DIR := "res://assets/ui/notebook_marks/"
const NOTE_HEADER_DIR := "res://assets/ui/notebook_headers/"
const CHARACTER_FACE_DIR := "res://assets/characters/final/"
const CAPTURE_HIT_PATH := "res://assets/audio/kenney/impactPunch_heavy_001.ogg"
const CAPTURE_STATIC_PATH := "res://assets/audio/open_game_art/high_pitch_hitted.mp3"
const WatchDialScript = preload("res://watch_dial.gd")
const NOTE_INK := Color(0.15, 0.12, 0.09, 0.96)
const NOTE_DIM := Color(0.34, 0.29, 0.22, 0.88)
const NOTE_SAFE := Color(0.12, 0.34, 0.23, 1.0)
const NOTE_DANGER := Color(0.48, 0.14, 0.11, 1.0)

var hud_root: Control
var strike_vignette: TextureRect
var watch_overlay: Control
var watch_dial: HotelWatchDial

var status_panel: Panel
var status_label: Label
var time_label: Label
var strike_label: Label

var prompt_panel: Panel
var prompt_label: Label
var stamina_panel: Panel
var stamina_bar: ProgressBar
var stamina_caption: Label
var stamina_value_label: Label
var stamina_fill_style: StyleBoxFlat
var help_panel: Panel
var help_label: Label
var lead_panel: Panel
var lead_label: Label
var reticle_parts: Array[ColorRect] = []

var inventory_panel: Panel
var inventory_slots: Array[Panel] = []
var inventory_number_labels: Array[Label] = []
var inventory_icon_tiles: Array[ColorRect] = []
var inventory_icon_textures: Array[TextureRect] = []
var inventory_icon_labels: Array[Label] = []
var inventory_name_labels: Array[Label] = []
var two_hand_label: Label

var notebook_overlay: Control
var notebook_rows: Array[Panel] = []
var notebook_room_labels: Array[Label] = []
var notebook_source_marks: Array[TextureRect] = []
var notebook_map_texture: TextureRect
var notebook_map_marker: Polygon2D
var notebook_map_plates: Array[Panel] = []
var notebook_map_plate_labels: Array[Label] = []

var suitcase_overlay: Control
var suitcase_slots: Array[Panel] = []
var suitcase_icon_tiles: Array[ColorRect] = []
var suitcase_icon_textures: Array[TextureRect] = []
var suitcase_icon_labels: Array[Label] = []
var suitcase_name_labels: Array[Label] = []

var debug_map_overlay: Control
var map_panel: Panel
var map_texture_rect: TextureRect
var map_marker: Polygon2D
var map_caption: Label

var end_overlay: Control
var end_title_label: Label
var end_detail_label: Label
var capture_overlay: Control
var capture_backdrop: ColorRect
var capture_face: TextureRect
var capture_hit_player: AudioStreamPlayer
var capture_static_player: AudioStreamPlayer

var map_open := false
var _notebook_open := false
var _suitcase_open := false
var _end_open := false
var _watch_requested := false
var _prompt_text := ""

var _run_day := 1
var _run_phase: Variant = "白天"
var _run_time := DAY_DURATION
var _run_strikes := 0
var _head_start_time := 0.0

var _stamina_value := 100.0
var _stamina_max := 100.0
var _stamina_display := 100.0
var _sprinting := false
var _help_tween: Tween
var _capture_tween: Tween

var _map_texture: Texture2D
var _map_position := Vector2(0.5, 0.5)
var _map_yaw := 0.0
var _fog_image: Image
var _fog_texture: ImageTexture
var _last_fog_cell := Vector2i(-999, -999)
var _debug_seed := 0
var _debug_room_count := 0
var _item_icon_cache: Dictionary = {}
var _ui_font: Font
var _note_font: Font
var _vacant_mark_texture: Texture2D
var _rented_mark_texture: Texture2D


func _ready() -> void:
	layer = 20
	_ui_font = load(UI_FONT_PATH) as Font
	_note_font = load(NOTE_FONT_PATH) as Font
	_vacant_mark_texture = load(NOTE_MARK_DIR + "vacant_check.png") as Texture2D
	_rented_mark_texture = load(NOTE_MARK_DIR + "rented_cross.png") as Texture2D
	_build_hud()
	_build_debug_map()
	_build_notebook()
	_build_suitcase()
	_build_end_overlay()
	_build_capture_overlay()
	_refresh_run_status()
	_refresh_stamina_immediate()
	_refresh_prompt_visibility()


func _process(delta: float) -> void:
	if stamina_bar != null:
		_stamina_display = move_toward(_stamina_display, _stamina_value, delta * 90.0)
		stamina_bar.max_value = maxf(_stamina_max, 1.0)
		stamina_bar.value = _stamina_display
		var ratio := _stamina_value / maxf(_stamina_max, 1.0)
		var target_alpha := 1.0 if _sprinting or ratio < 0.98 else 0.42
		stamina_panel.modulate.a = move_toward(stamina_panel.modulate.a, target_alpha, delta * 5.0)
		var fill := PAPER if ratio > 0.25 else DANGER
		stamina_fill_style.bg_color = fill
		stamina_fill_style.border_color = fill
	if strike_vignette != null:
		var strike_alpha: float = float([0.0, 0.34, 0.62, 0.86][_run_strikes])
		strike_vignette.modulate.a = move_toward(strike_vignette.modulate.a, strike_alpha, delta * 2.2)


func _build_hud() -> void:
	hud_root = Control.new()
	hud_root.name = "HUDRoot"
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.z_index = 10
	add_child(hud_root)

	_build_strike_vignette()
	_build_reticle()
	_build_prompt()
	_build_lead_timer()
	_build_stamina()
	_build_inventory()
	_build_help()
	_build_watch()


func _build_capture_overlay() -> void:
	capture_overlay = Control.new()
	capture_overlay.name = "CaptureScare"
	capture_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	capture_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	capture_overlay.z_index = 200
	capture_overlay.visible = false
	add_child(capture_overlay)

	capture_backdrop = ColorRect.new()
	capture_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	capture_backdrop.color = Color(0.06, 0.0, 0.0, 0.0)
	capture_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capture_overlay.add_child(capture_backdrop)

	capture_face = TextureRect.new()
	capture_face.name = "Face"
	capture_face.anchor_left = 0.5
	capture_face.anchor_top = 0.5
	capture_face.anchor_right = 0.5
	capture_face.anchor_bottom = 0.5
	capture_face.offset_left = -450.0
	capture_face.offset_top = -450.0
	capture_face.offset_right = 450.0
	capture_face.offset_bottom = 450.0
	capture_face.pivot_offset = Vector2(450.0, 450.0)
	capture_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	capture_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	capture_face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	capture_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capture_overlay.add_child(capture_face)

	capture_hit_player = AudioStreamPlayer.new()
	capture_hit_player.name = "CaptureHit"
	capture_hit_player.stream = load(CAPTURE_HIT_PATH) as AudioStream
	capture_hit_player.volume_db = -6.5
	add_child(capture_hit_player)

	capture_static_player = AudioStreamPlayer.new()
	capture_static_player.name = "CaptureRadioStatic"
	capture_static_player.stream = load(CAPTURE_STATIC_PATH) as AudioStream
	capture_static_player.volume_db = 0.0
	add_child(capture_static_player)


func play_capture_scare(kind: StringName = &"guard") -> void:
	if capture_overlay == null:
		capture_scare_finished.emit()
		return
	if _capture_tween != null and _capture_tween.is_valid():
		_capture_tween.kill()
	var face_kind := "tenant" if kind == &"tenant" else "guard"
	capture_face.texture = load(CHARACTER_FACE_DIR + face_kind + "_face.png") as Texture2D
	capture_face.scale = Vector2(0.34, 0.34)
	capture_face.rotation = deg_to_rad(-3.0)
	capture_face.modulate = Color(1.25, 1.08, 0.96, 0.0)
	capture_backdrop.color = Color(0.08, 0.0, 0.0, 0.0)
	capture_overlay.visible = true
	if capture_hit_player.stream != null:
		capture_hit_player.pitch_scale = randf_range(0.88, 0.96)
		capture_hit_player.play()
	if capture_static_player.stream != null:
		capture_static_player.pitch_scale = randf_range(0.94, 1.04)
		capture_static_player.play()

	_capture_tween = create_tween()
	_capture_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_capture_tween.set_parallel(true)
	_capture_tween.tween_property(capture_face, "scale", Vector2(2.35, 2.35), 0.11).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_capture_tween.tween_property(capture_face, "modulate:a", 1.0, 0.025)
	_capture_tween.tween_property(capture_backdrop, "color:a", 0.72, 0.08)
	_capture_tween.set_parallel(false)
	_capture_tween.tween_property(capture_face, "rotation", deg_to_rad(2.5), 0.035)
	_capture_tween.tween_property(capture_face, "rotation", deg_to_rad(-1.5), 0.035)
	_capture_tween.tween_interval(0.20)
	_capture_tween.set_parallel(true)
	_capture_tween.tween_property(capture_face, "modulate:a", 0.0, 0.045)
	_capture_tween.tween_property(capture_backdrop, "color", Color(0.0, 0.0, 0.0, 1.0), 0.045)
	_capture_tween.set_parallel(false)
	_capture_tween.tween_interval(0.10)
	_capture_tween.tween_callback(_finish_capture_scare)


func _finish_capture_scare() -> void:
	capture_overlay.visible = false
	capture_scare_finished.emit()


func _build_strike_vignette() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.56, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.05, 0.0, 0.0, 0.0),
		Color(0.08, 0.0, 0.0, 0.08),
		Color(0.18, 0.005, 0.008, 0.92),
	])
	var texture := GradientTexture2D.new()
	texture.width = 1920
	texture.height = 1080
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.gradient = gradient

	strike_vignette = TextureRect.new()
	strike_vignette.name = "StrikeVignette"
	strike_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strike_vignette.texture = texture
	strike_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strike_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	strike_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strike_vignette.modulate.a = 0.0
	hud_root.add_child(strike_vignette)


func _build_watch() -> void:
	watch_overlay = Control.new()
	watch_overlay.name = "RaisedWatch"
	watch_overlay.anchor_left = 1.0
	watch_overlay.anchor_top = 1.0
	watch_overlay.anchor_right = 1.0
	watch_overlay.anchor_bottom = 1.0
	watch_overlay.offset_left = -470
	watch_overlay.offset_top = -540
	watch_overlay.offset_right = -110
	watch_overlay.offset_bottom = -100
	watch_overlay.pivot_offset = Vector2(180.0, 440.0)
	watch_overlay.rotation = deg_to_rad(-4.0)
	watch_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	watch_overlay.visible = false
	hud_root.add_child(watch_overlay)

	watch_dial = WatchDialScript.new() as HotelWatchDial
	watch_overlay.add_child(watch_dial)


func _build_status() -> void:
	status_panel = Panel.new()
	status_panel.name = "RunStatus"
	status_panel.anchor_left = 0.5
	status_panel.anchor_right = 0.5
	status_panel.offset_left = -700
	status_panel.offset_top = 28
	status_panel.offset_right = 700
	status_panel.offset_bottom = 108
	status_panel.add_theme_stylebox_override("panel", _style(INK_GLASS, Color(0.30, 0.25, 0.17, 0.92), 2, 8))
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(status_panel)

	status_label = _make_label("DAY 1  //  白天", 28, PAPER)
	status_label.position = Vector2(28, 18)
	status_label.size = Vector2(430, 44)
	status_panel.add_child(status_label)

	time_label = _make_label("02:00", 44, PAPER)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.position = Vector2(525, 6)
	time_label.size = Vector2(350, 62)
	status_panel.add_child(time_label)

	strike_label = _make_label("被抓 0/3", 27, PAPER_DIM)
	strike_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	strike_label.position = Vector2(930, 18)
	strike_label.size = Vector2(440, 44)
	status_panel.add_child(strike_label)


func _build_reticle() -> void:
	var specs := [
		Rect2(-16, -2, 10, 3),
		Rect2(6, -2, 10, 3),
		Rect2(-2, -16, 3, 10),
		Rect2(-2, 6, 3, 10),
	]
	for spec: Rect2 in specs:
		var part := ColorRect.new()
		part.color = Color(PAPER.r, PAPER.g, PAPER.b, 0.62)
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		part.anchor_left = 0.5
		part.anchor_top = 0.5
		part.anchor_right = 0.5
		part.anchor_bottom = 0.5
		part.offset_left = spec.position.x
		part.offset_top = spec.position.y
		part.offset_right = spec.position.x + spec.size.x
		part.offset_bottom = spec.position.y + spec.size.y
		hud_root.add_child(part)
		reticle_parts.append(part)


func _build_prompt() -> void:
	prompt_panel = Panel.new()
	prompt_panel.name = "InteractionPrompt"
	prompt_panel.add_theme_stylebox_override("panel", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	prompt_panel.anchor_left = 0.5
	prompt_panel.anchor_top = 1.0
	prompt_panel.anchor_right = 0.5
	prompt_panel.anchor_bottom = 1.0
	prompt_panel.offset_left = -420
	prompt_panel.offset_top = -180
	prompt_panel.offset_right = 420
	prompt_panel.offset_bottom = -132
	prompt_panel.visible = false
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(prompt_panel)

	prompt_label = _make_label("", 23, PAPER)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prompt_label.offset_left = 20
	prompt_label.offset_right = -20
	prompt_panel.add_child(prompt_label)


func _build_lead_timer() -> void:
	lead_panel = Panel.new()
	lead_panel.name = "HeadStartTimer"
	lead_panel.anchor_left = 0.5
	lead_panel.anchor_right = 0.5
	lead_panel.offset_left = -80
	lead_panel.offset_top = 90
	lead_panel.offset_right = 80
	lead_panel.offset_bottom = 150
	lead_panel.add_theme_stylebox_override("panel", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	lead_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lead_panel.visible = false
	hud_root.add_child(lead_panel)

	lead_label = _make_label("5", 38, Color(0.76, 0.20, 0.16))
	lead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lead_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lead_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lead_panel.add_child(lead_label)


func _build_stamina() -> void:
	stamina_panel = Panel.new()
	stamina_panel.name = "Stamina"
	stamina_panel.add_theme_stylebox_override("panel", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	stamina_panel.anchor_top = 1.0
	stamina_panel.anchor_bottom = 1.0
	stamina_panel.offset_left = 28
	stamina_panel.offset_top = -42
	stamina_panel.offset_right = 288
	stamina_panel.offset_bottom = -28
	stamina_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(stamina_panel)

	stamina_bar = ProgressBar.new()
	stamina_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stamina_bar.show_percentage = false
	stamina_bar.min_value = 0.0
	stamina_bar.max_value = 100.0
	stamina_bar.value = 100.0
	stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamina_bar.add_theme_stylebox_override("background", _style(Color(0.47, 0.42, 0.32, 0.70), Color.TRANSPARENT, 0, 2))
	stamina_fill_style = _style(PAPER, PAPER, 0, 2)
	stamina_bar.add_theme_stylebox_override("fill", stamina_fill_style)
	stamina_panel.add_child(stamina_bar)


func _build_inventory() -> void:
	inventory_panel = Panel.new()
	inventory_panel.name = "CarryInventory"
	inventory_panel.anchor_left = 0.5
	inventory_panel.anchor_top = 1.0
	inventory_panel.anchor_right = 0.5
	inventory_panel.anchor_bottom = 1.0
	inventory_panel.offset_left = -182
	inventory_panel.offset_top = -108
	inventory_panel.offset_right = 182
	inventory_panel.offset_bottom = -26
	inventory_panel.add_theme_stylebox_override("panel", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	inventory_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(inventory_panel)

	for i in range(4):
		var slot := Panel.new()
		slot.name = "CarrySlot%d" % (i + 1)
		slot.position = Vector2(i * 94, 0)
		slot.size = Vector2(82, 82)
		slot.add_theme_stylebox_override("panel", _style(Color(0.035, 0.028, 0.022, 0.58), Color(0.68, 0.62, 0.49, 0.72), 2, 5))
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inventory_panel.add_child(slot)
		inventory_slots.append(slot)

		var icon_texture := TextureRect.new()
		icon_texture.name = "ItemIcon"
		icon_texture.position = Vector2(9, 9)
		icon_texture.size = Vector2(64, 64)
		icon_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_texture.visible = false
		slot.add_child(icon_texture)
		inventory_icon_textures.append(icon_texture)


func _build_help() -> void:
	help_panel = Panel.new()
	help_panel.name = "HelpToast"
	help_panel.add_theme_stylebox_override("panel", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	help_panel.anchor_left = 0.5
	help_panel.anchor_top = 1.0
	help_panel.anchor_right = 0.5
	help_panel.anchor_bottom = 1.0
	help_panel.offset_left = -500
	help_panel.offset_top = -232
	help_panel.offset_right = 500
	help_panel.offset_bottom = -190
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(help_panel)

	help_label = _make_label("", 21, PAPER_DIM)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	help_panel.add_child(help_label)
	help_panel.visible = false


func _build_notebook() -> void:
	notebook_overlay = Control.new()
	notebook_overlay.name = "LiveNotebook"
	notebook_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	notebook_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notebook_overlay.z_index = 5
	notebook_overlay.visible = false
	add_child(notebook_overlay)

	var shade := ColorRect.new()
	shade.color = Color(0.018, 0.012, 0.008, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notebook_overlay.add_child(shade)

	var paper := TextureRect.new()
	paper.name = "FieldNotebookPaper"
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.texture = load(NOTEBOOK_TEXTURE_PATH) as Texture2D
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	paper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notebook_overlay.add_child(paper)

	var board := Control.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notebook_overlay.add_child(board)

	var title := _make_note_label("走过的地方", 35, NOTE_INK)
	title.position = Vector2(275, 82)
	title.size = Vector2(610, 50)
	board.add_child(title)
	var hint := _make_note_label("脚印记得路，门牌记在路旁", 22, NOTE_DIM)
	hint.position = Vector2(300, 124)
	hint.size = Vector2(560, 34)
	board.add_child(hint)

	var map_back := Control.new()
	map_back.position = Vector2(265, 165)
	map_back.size = Vector2(650, 760)
	map_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(map_back)

	notebook_map_texture = TextureRect.new()
	notebook_map_texture.position = NOTE_MAP_OFFSET
	notebook_map_texture.size = Vector2(NOTE_MAP_DRAW_SIZE, NOTE_MAP_DRAW_SIZE)
	notebook_map_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	notebook_map_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	notebook_map_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	notebook_map_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_fog_of_war()
	var fog_material := ShaderMaterial.new()
	fog_material.shader = load("res://fog_of_war.gdshader") as Shader
	fog_material.set_shader_parameter("fog_mask", _fog_texture)
	notebook_map_texture.material = fog_material
	map_back.add_child(notebook_map_texture)

	for plate_index in range(MAX_NOTEBOOK_ROWS):
		var plate := Panel.new()
		plate.size = Vector2(88, 34)
		plate.pivot_offset = plate.size * 0.5
		plate.rotation = deg_to_rad(float((plate_index % 5) - 2) * 0.7)
		plate.add_theme_stylebox_override("panel", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.visible = false
		map_back.add_child(plate)
		notebook_map_plates.append(plate)
		var plate_label := _make_note_label("?", 23, NOTE_INK)
		plate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plate_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plate_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		plate.add_child(plate_label)
		notebook_map_plate_labels.append(plate_label)

	notebook_map_marker = Polygon2D.new()
	notebook_map_marker.polygon = PackedVector2Array([Vector2(0, -13), Vector2(8, 10), Vector2(0, 6), Vector2(-8, 10)])
	notebook_map_marker.color = NOTE_DANGER
	notebook_map_marker.position = NOTE_MAP_OFFSET + Vector2.ONE * NOTE_MAP_DRAW_SIZE * 0.5
	map_back.add_child(notebook_map_marker)

	var list_title := _make_note_label("挨门挨户记下来的", 35, NOTE_INK)
	list_title.position = Vector2(1050, 82)
	list_title.size = Vector2(590, 50)
	board.add_child(list_title)
	var source_ids := ["registration", "doorstep", "listen", "knock"]
	for source_index in range(NOTEBOOK_SOURCE_COUNT):
		var header := TextureRect.new()
		header.name = "EvidenceHeader_%s" % source_ids[source_index]
		header.position = Vector2(1168 + source_index * 78, 133)
		header.size = Vector2(38, 38)
		header.texture = load(NOTE_HEADER_DIR + source_ids[source_index] + ".png") as Texture2D
		header.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		header.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		header.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		header.modulate = NOTE_DIM
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(header)

	for row_index in range(MAX_NOTEBOOK_ROWS):
		var row := Panel.new()
		row.position = Vector2(1030, 174 + row_index * 55)
		row.size = Vector2(610, 50)
		row.add_theme_stylebox_override("panel", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.visible = false
		board.add_child(row)
		notebook_rows.append(row)

		var room := _make_note_label("", 29, NOTE_INK)
		room.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		room.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		room.position = Vector2(8, 0)
		room.size = Vector2(116, 48)
		row.add_child(room)
		notebook_room_labels.append(room)

		for source_index in range(NOTEBOOK_SOURCE_COUNT):
			var mark := TextureRect.new()
			mark.name = "EvidenceMark%d" % (source_index + 1)
			mark.position = Vector2(132 + source_index * 78 + 8, 8)
			mark.size = Vector2(34, 34)
			mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			mark.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mark.visible = false
			row.add_child(mark)
			notebook_source_marks.append(mark)

	var footer := _make_note_label("N  合上手记", 22, NOTE_DIM)
	footer.position = Vector2(1440, 957)
	footer.size = Vector2(200, 34)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	board.add_child(footer)


func _build_suitcase() -> void:
	suitcase_overlay = Control.new()
	suitcase_overlay.name = "SuitcaseOrganizer"
	suitcase_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	suitcase_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	suitcase_overlay.z_index = 20
	suitcase_overlay.visible = false
	add_child(suitcase_overlay)

	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.012, 0.01, 0.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	suitcase_overlay.add_child(shade)

	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -226
	panel.offset_top = -226
	panel.offset_right = 226
	panel.offset_bottom = 226
	panel.add_theme_stylebox_override("panel", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	suitcase_overlay.add_child(panel)

	for i in range(4):
		var slot := Panel.new()
		slot.name = "SuitcaseSlot%d" % (i + 1)
		slot.position = Vector2((i % 2) * 244, floori(float(i) / 2.0) * 244)
		slot.size = Vector2(208, 208)
		slot.add_theme_stylebox_override("panel", _style(Color(0.035, 0.028, 0.022, 0.62), Color(0.68, 0.62, 0.49, 0.72), 3, 7))
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(slot)
		suitcase_slots.append(slot)

		var icon_texture := TextureRect.new()
		icon_texture.name = "ItemIcon"
		icon_texture.position = Vector2(40, 40)
		icon_texture.size = Vector2(128, 128)
		icon_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_texture.visible = false
		slot.add_child(icon_texture)
		suitcase_icon_textures.append(icon_texture)


func _build_debug_map() -> void:
	debug_map_overlay = Control.new()
	debug_map_overlay.name = "DeveloperMap"
	debug_map_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	debug_map_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_map_overlay.z_index = 40
	debug_map_overlay.visible = false
	add_child(debug_map_overlay)

	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.008, 0.006, 0.91)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_map_overlay.add_child(shade)

	map_panel = Panel.new()
	map_panel.anchor_left = 0.5
	map_panel.anchor_top = 0.5
	map_panel.anchor_right = 0.5
	map_panel.anchor_bottom = 0.5
	map_panel.offset_left = -410
	map_panel.offset_top = -510
	map_panel.offset_right = 410
	map_panel.offset_bottom = 510
	map_panel.add_theme_stylebox_override("panel", _style(Color(0.075, 0.061, 0.045, 0.99), BRASS, 3, 12))
	map_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_map_overlay.add_child(map_panel)

	map_caption = _make_label("DEV FLOOR // 0000", 34, PAPER)
	map_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_caption.position = Vector2(30, 22)
	map_caption.size = Vector2(760, 52)
	map_panel.add_child(map_caption)

	var warning := _make_label("开发模式：地图预览 / 房门绑定 / 边界", 22, DANGER)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.position = Vector2(30, 78)
	warning.size = Vector2(760, 36)
	map_panel.add_child(warning)

	var map_back := Panel.new()
	map_back.position = Vector2(50, 132)
	map_back.size = Vector2(720, 720)
	map_back.add_theme_stylebox_override("panel", _style(Color(0.020, 0.018, 0.014), Color(0.28, 0.23, 0.15), 2, 2))
	map_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_panel.add_child(map_back)

	map_texture_rect = TextureRect.new()
	map_texture_rect.position = Vector2(10, 10)
	map_texture_rect.size = Vector2(MAP_DRAW_SIZE, MAP_DRAW_SIZE)
	map_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_back.add_child(map_texture_rect)

	map_marker = Polygon2D.new()
	map_marker.polygon = PackedVector2Array([
		Vector2(0, -18),
		Vector2(11, 14),
		Vector2(0, 8),
		Vector2(-11, 14),
	])
	map_marker.color = BRASS_BRIGHT
	map_marker.position = Vector2(360, 360)
	map_back.add_child(map_marker)

	var footer := _make_label("F3 关闭开发图 · 正式游戏不会提供地图", 23, PAPER_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.position = Vector2(30, 900)
	footer.size = Vector2(760, 40)
	map_panel.add_child(footer)


func _build_end_overlay() -> void:
	end_overlay = Control.new()
	end_overlay.name = "RunEndOverlay"
	end_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	end_overlay.z_index = 100
	end_overlay.visible = false
	add_child(end_overlay)

	var shade := ColorRect.new()
	shade.color = Color(0.008, 0.006, 0.004, 0.95)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	end_overlay.add_child(shade)

	var frame := Panel.new()
	frame.anchor_left = 0.5
	frame.anchor_top = 0.5
	frame.anchor_right = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -600
	frame.offset_top = -250
	frame.offset_right = 600
	frame.offset_bottom = 250
	frame.add_theme_stylebox_override("panel", _style(Color(0.07, 0.055, 0.04, 0.98), BRASS, 3, 14))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_overlay.add_child(frame)

	end_title_label = _make_label("", 56, PAPER)
	end_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title_label.position = Vector2(50, 60)
	end_title_label.size = Vector2(1100, 84)
	frame.add_child(end_title_label)

	end_detail_label = _make_label("", 29, PAPER_DIM)
	end_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	end_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_detail_label.position = Vector2(110, 170)
	end_detail_label.size = Vector2(980, 240)
	frame.add_child(end_detail_label)


## --- Public runtime API ----------------------------------------------------

func set_run_status(day: int, phase: Variant, time_remaining: float, strikes: int) -> void:
	_run_day = maxi(day, 1)
	_run_phase = phase
	_run_time = maxf(time_remaining, 0.0)
	_run_strikes = clampi(strikes, 0, 3)
	_refresh_run_status()


func set_stamina(value: float, maximum := 100.0, sprinting := false) -> void:
	_stamina_value = clampf(value, 0.0, maxf(float(maximum), 1.0))
	_stamina_max = maxf(float(maximum), 1.0)
	_sprinting = bool(sprinting)
	if stamina_bar != null and not is_processing():
		_refresh_stamina_immediate()


func set_prompt(text: String) -> void:
	_prompt_text = text
	if prompt_label != null:
		prompt_label.text = text
	_refresh_prompt_visibility()


func set_inventory(items: Array, selected: int, _two_handed: bool) -> void:
	if inventory_panel == null:
		return
	var selected_index := clampi(selected, 0, 3)
	var selected_uid := 0
	if selected_index < items.size() and items[selected_index] is Dictionary:
		selected_uid = int(items[selected_index].get("uid", 0))
	for i in range(4):
		var item: Variant = items[i] if i < items.size() else null
		var linked_item := item is Dictionary and (bool(item.get("reserved", false)) or int(item.get("slot_cost", 1)) >= 2)
		var occupied_by_hands := linked_item and not bool(item.get("anchor", true))
		_set_small_item_slot(i, item, occupied_by_hands)
		var same_selected_item := selected_uid != 0 and item is Dictionary and int(item.get("uid", 0)) == selected_uid
		var is_selected := i == selected_index or same_selected_item
		var border := PAPER if is_selected else Color(0.68, 0.62, 0.49, 0.72)
		var background := Color(0.08, 0.06, 0.045, 0.72) if is_selected else Color(0.035, 0.028, 0.022, 0.58)
		inventory_slots[i].add_theme_stylebox_override("panel", _style(background, border, 2, 5))


func set_notebook(entries: Variant, open: bool) -> void:
	_notebook_open = open
	if notebook_overlay == null:
		return
	var entry_array := _entries_to_array(entries)
	for row_index in range(MAX_NOTEBOOK_ROWS):
		var has_entry := row_index < entry_array.size()
		notebook_rows[row_index].visible = has_entry
		notebook_map_plates[row_index].visible = has_entry
		if not has_entry:
			continue
		var entry := _entry_to_dictionary(entry_array[row_index], row_index)
		_update_notebook_row(row_index, entry)
		_update_notebook_map_plate(row_index, entry)
	if notebook_map_texture != null:
		notebook_map_texture.texture = _map_texture
	if notebook_map_marker != null:
		notebook_map_marker.position = _notebook_map_point(_map_position)
		notebook_map_marker.rotation = -_map_yaw
	notebook_overlay.visible = open
	_refresh_prompt_visibility()


func set_suitcase(items: Array, open: bool) -> void:
	_suitcase_open = open
	if suitcase_overlay == null:
		return
	for i in range(4):
		var item: Variant = items[i] if i < items.size() else null
		_set_suitcase_slot(i, item)
	suitcase_overlay.visible = open
	_refresh_prompt_visibility()


func set_watch_open(open: bool) -> void:
	_watch_requested = open
	_refresh_prompt_visibility()


func set_head_start(seconds: float) -> void:
	_head_start_time = maxf(seconds, 0.0)
	if lead_panel == null:
		return
	lead_panel.visible = _head_start_time > 0.0
	lead_label.text = str(maxi(ceili(_head_start_time), 0))
	if lead_panel.visible:
		lead_panel.move_to_front()


func set_lead_time(seconds: float) -> void:
	set_head_start(seconds)


func show_help(text: String, duration := 5.0) -> void:
	if help_panel == null:
		return
	if _help_tween != null and _help_tween.is_valid():
		_help_tween.kill()
	help_label.text = text
	help_panel.visible = true
	help_panel.modulate.a = 1.0
	_help_tween = create_tween()
	_help_tween.tween_interval(maxf(float(duration), 0.0))
	_help_tween.tween_property(help_panel, "modulate:a", 0.0, 0.5)
	_help_tween.tween_callback(func() -> void: help_panel.visible = false)


func show_end(title: String, detail: String) -> void:
	_end_open = true
	if end_overlay == null:
		return
	end_title_label.text = title
	end_detail_label.text = detail
	var lower := title.to_lower()
	var failed := lower.contains("fail") or lower.contains("game over") or title.contains("失败") or title.contains("封锁")
	end_title_label.add_theme_color_override("font_color", DANGER if failed else BRASS_BRIGHT)
	end_overlay.visible = true
	_refresh_prompt_visibility()


func hide_end() -> void:
	_end_open = false
	if end_overlay != null:
		end_overlay.visible = false
	_refresh_prompt_visibility()


func set_debug_map(texture: Texture2D, normalized_position: Vector2, yaw: float, open: bool) -> void:
	_map_texture = texture
	_map_position = normalized_position
	_map_yaw = yaw
	_reveal_fog(normalized_position)
	map_open = open
	if debug_map_overlay == null:
		return
	map_texture_rect.texture = texture
	_update_map_marker(normalized_position, yaw)
	if notebook_map_marker != null:
		notebook_map_marker.position = _notebook_map_point(normalized_position)
		notebook_map_marker.rotation = -yaw
	debug_map_overlay.visible = open
	_refresh_prompt_visibility()


## Compatibility wrappers for the previous prototype. New runtime code should call
## set_debug_map from its F3 handler; the production HUD itself exposes no map button.
func set_level_info(level_seed: int, room_count: int) -> void:
	_debug_seed = level_seed
	_debug_room_count = room_count
	if map_caption != null:
		map_caption.text = "DEV FLOOR // %04X · %02d" % [level_seed & 0xFFFF, room_count]


func set_map_texture(texture: Texture2D) -> void:
	var changed := texture != _map_texture
	_map_texture = texture
	if changed:
		_reset_fog_of_war()
	if map_texture_rect != null:
		map_texture_rect.texture = texture
	if notebook_map_texture != null:
		notebook_map_texture.texture = texture


func set_map_marker(normalized_position: Vector2, yaw: float) -> void:
	_map_position = normalized_position
	_map_yaw = yaw
	_reveal_fog(normalized_position)
	_update_map_marker(normalized_position, yaw)
	if notebook_map_marker != null:
		notebook_map_marker.position = _notebook_map_point(normalized_position)
		notebook_map_marker.rotation = -yaw


func set_map_open(open: bool) -> void:
	map_open = open
	if debug_map_overlay != null:
		debug_map_overlay.visible = open
	_refresh_prompt_visibility()


## --- Presentation helpers -------------------------------------------------

func _refresh_run_status() -> void:
	if watch_dial != null:
		var duration := DAY_DURATION if String(_run_phase) == "白天" or String(_run_phase) == "day" else NIGHT_DURATION
		watch_dial.set_state(_run_day, _run_time, duration, _run_strikes, _run_phase)


func _reset_fog_of_war() -> void:
	_fog_image = Image.create_empty(FOG_MASK_SIZE, FOG_MASK_SIZE, false, Image.FORMAT_RGBA8)
	_fog_image.fill(Color.BLACK)
	if _fog_texture == null:
		_fog_texture = ImageTexture.create_from_image(_fog_image)
	else:
		_fog_texture.update(_fog_image)
	_last_fog_cell = Vector2i(-999, -999)
	if notebook_map_texture != null and notebook_map_texture.material is ShaderMaterial:
		(notebook_map_texture.material as ShaderMaterial).set_shader_parameter("fog_mask", _fog_texture)


func _reveal_fog(normalized_position: Vector2) -> void:
	if _fog_image == null or _fog_texture == null:
		return
	var center := Vector2i(
		clampi(roundi(clampf(normalized_position.x, 0.0, 1.0) * float(FOG_MASK_SIZE - 1)), 0, FOG_MASK_SIZE - 1),
		clampi(roundi(clampf(normalized_position.y, 0.0, 1.0) * float(FOG_MASK_SIZE - 1)), 0, FOG_MASK_SIZE - 1)
	)
	if center == _last_fog_cell:
		return
	_last_fog_cell = center
	for y in range(maxi(0, center.y - FOG_REVEAL_RADIUS), mini(FOG_MASK_SIZE, center.y + FOG_REVEAL_RADIUS + 1)):
		for x in range(maxi(0, center.x - FOG_REVEAL_RADIUS), mini(FOG_MASK_SIZE, center.x + FOG_REVEAL_RADIUS + 1)):
			var distance := Vector2(x - center.x, y - center.y).length()
			if distance > FOG_REVEAL_RADIUS:
				continue
			var reveal := 1.0 - smoothstep(float(FOG_REVEAL_RADIUS - 3), float(FOG_REVEAL_RADIUS), distance)
			var existing := _fog_image.get_pixel(x, y).r
			if reveal > existing:
				_fog_image.set_pixel(x, y, Color(reveal, reveal, reveal, 1.0))
	_fog_texture.update(_fog_image)


func _refresh_stamina_immediate() -> void:
	if stamina_bar == null:
		return
	_stamina_display = _stamina_value
	stamina_bar.max_value = _stamina_max
	stamina_bar.value = _stamina_value


func _refresh_prompt_visibility() -> void:
	if prompt_panel == null:
		return
	var blocked := map_open or _notebook_open or _suitcase_open or _end_open or _watch_requested
	if blocked and help_panel != null:
		help_panel.visible = false
	var has_prompt := not _prompt_text.is_empty() and not blocked
	prompt_panel.visible = has_prompt
	var full_screen_overlay := map_open or _notebook_open or _suitcase_open or _end_open or _watch_requested
	if inventory_panel != null:
		inventory_panel.visible = not full_screen_overlay
	if stamina_panel != null:
		stamina_panel.visible = not full_screen_overlay
	if status_panel != null:
		status_panel.visible = not _end_open
	_refresh_watch_visibility()
	for part in reticle_parts:
		part.visible = not blocked
		part.color = Color(BRASS.r, BRASS.g, BRASS.b, 0.95) if has_prompt else Color(PAPER.r, PAPER.g, PAPER.b, 0.62)


func _refresh_watch_visibility() -> void:
	if watch_overlay == null:
		return
	var blocked := map_open or _notebook_open or _suitcase_open or _end_open
	watch_overlay.visible = _watch_requested and not blocked


func _update_map_marker(normalized_position: Vector2, yaw: float) -> void:
	if map_marker == null:
		return
	map_marker.position = Vector2(
		10.0 + clampf(normalized_position.x, 0.0, 1.0) * MAP_DRAW_SIZE,
		10.0 + clampf(normalized_position.y, 0.0, 1.0) * MAP_DRAW_SIZE
	)
	map_marker.rotation = -yaw


func _notebook_map_point(normalized_position: Vector2) -> Vector2:
	return NOTE_MAP_OFFSET + Vector2(
		clampf(normalized_position.x, 0.0, 1.0) * NOTE_MAP_DRAW_SIZE,
		clampf(normalized_position.y, 0.0, 1.0) * NOTE_MAP_DRAW_SIZE
	)


func _set_small_item_slot(index: int, item: Variant, occupied_by_hands: bool) -> void:
	var texture := _item_texture(item)
	inventory_icon_textures[index].texture = texture
	inventory_icon_textures[index].visible = texture != null
	inventory_icon_textures[index].modulate = Color(1.0, 1.0, 1.0, 0.42 if occupied_by_hands else 1.0)


func _set_suitcase_slot(index: int, item: Variant) -> void:
	var texture := _item_texture(item)
	suitcase_icon_textures[index].texture = texture
	suitcase_icon_textures[index].visible = texture != null
	var secondary := item is Dictionary and not bool(item.get("anchor", true))
	suitcase_icon_textures[index].modulate = Color(1.0, 1.0, 1.0, 0.42 if secondary else 1.0)


func _update_notebook_row(row_index: int, entry: Dictionary) -> void:
	var room_text := str(_dict_first(entry, ["room_number", "room_no", "number", "room_id", "id"], "?"))
	notebook_room_labels[row_index].text = room_text
	var sources := _extract_sources(entry)
	for source_index in range(NOTEBOOK_SOURCE_COUNT):
		var value: Variant = sources[source_index] if source_index < sources.size() else null
		var state := _evidence_state(value)
		var mark := notebook_source_marks[row_index * NOTEBOOK_SOURCE_COUNT + source_index]
		mark.texture = _vacant_mark_texture if state > 0 else (_rented_mark_texture if state < 0 else null)
		mark.visible = state != 0


func _update_notebook_map_plate(index: int, entry: Dictionary) -> void:
	var normalized: Variant = entry.get("map_position", Vector2(0.5, 0.5))
	if not (normalized is Vector2):
		normalized = Vector2(0.5, 0.5)
	var plate := notebook_map_plates[index]
	plate.position = _notebook_map_point(normalized) - plate.size * 0.5
	notebook_map_plate_labels[index].text = str(_dict_first(entry, ["room_number", "room_id"], "?"))
	notebook_map_plate_labels[index].add_theme_color_override("font_color", NOTE_INK)


func _entries_to_array(entries: Variant) -> Array:
	if entries is Array:
		return entries
	var result: Array = []
	if entries is Dictionary:
		for key: Variant in entries.keys():
			var value: Variant = entries[key]
			if value is Dictionary:
				var copy: Dictionary = value.duplicate(true)
				if not copy.has("room_id") and not copy.has("room_number"):
					copy["room_id"] = key
				result.append(copy)
			else:
				result.append({"room_id": key, "sources": value})
	return result


func _entry_to_dictionary(value: Variant, index: int) -> Dictionary:
	if value is Dictionary:
		return value
	return {"room_id": index + 1, "sources": value}


func _extract_sources(entry: Dictionary) -> Array:
	var raw: Variant = _dict_first(entry, ["sources", "evidence", "clues", "votes"], null)
	if raw is Array:
		return raw
	var result: Array = []
	if raw is Dictionary:
		var source_keys := [
			["registration", "register", "record", "1", 1],
			["doorstep", "door_observation", "observation", "door", "2", 2],
			["listen", "listening", "3", 3],
			["knock", "knocking", "4", 4],
		]
		for keys: Array in source_keys:
			result.append(_dict_first(raw, keys, null))
		return result
	var flat_keys := [
		["registration", "register", "record", "source_1"],
		["doorstep", "door_observation", "observation", "door", "source_2"],
		["listen", "listening", "source_3"],
		["knock", "knocking", "source_4"],
	]
	for keys: Array in flat_keys:
		result.append(_dict_first(entry, keys, null))
	return result


func _evidence_state(value: Variant) -> int:
	if value == null:
		return 0
	if value is bool:
		return 1 if value else 0
	if value is int or value is float:
		return signi(int(value))
	if value is Dictionary:
		return _evidence_state(_dict_first(value, ["verdict", "result", "state", "value", "assignment"], null))
	var text := str(value).strip_edges().to_lower()
	if text.is_empty() or text in ["none", "unknown", "未调查", "未知", "无", "·", "-"]:
		return 0
	if text in ["vacant", "empty", "unoccupied", "safe", "clear", "no_response", "true", "check", "空置", "无人", "安全", "✓", "+", "1"]:
		return 1
	if text in ["rented", "occupied", "tenant", "danger", "出租", "有人", "租客", "危险", "×", "x", "-1"]:
		return -1
	return 0


func _evidence_count(entry: Dictionary, keys: Array) -> int:
	var value: Variant = _dict_first(entry, keys, null)
	if value == null:
		return -1
	if value is Array:
		return value.size()
	if value is bool:
		return 1 if value else 0
	if value is int or value is float:
		return maxi(int(value), 0)
	return -1


func _phase_text(phase: Variant) -> String:
	if phase is int:
		match int(phase):
			0:
				return "白天"
			1:
				return "领先"
			2:
				return "夜晚"
			3:
				return "结算"
			_:
				return str(phase)
	var text := str(phase)
	match text.to_lower():
		"day", "daytime", "investigation":
			return "白天"
		"night_lead", "head_start", "warning", "grace":
			return "领先"
		"night", "chase", "cleanup":
			return "夜晚"
		"complete", "ended", "result":
			return "结算"
		_:
			return text


func _strike_pips(count: int) -> String:
	var text := ""
	for i in range(3):
		text += "X" if i < count else "·"
	return text


func _option_title(option: Variant) -> String:
	if option is Dictionary:
		return str(_dict_first(option, ["label", "title", "name", "text", "id"], "动作"))
	return str(option)


func _option_enabled(option: Variant) -> bool:
	if option is Dictionary:
		return bool(_dict_first(option, ["enabled", "available"], true))
	return true


func _is_empty_item(item: Variant) -> bool:
	return item == null or (item is String and item.is_empty())


func _item_title(item: Variant) -> String:
	if _is_empty_item(item):
		return ""
	if item is Dictionary:
		return str(_dict_first(item, ["display_name", "name", "title", "label", "id"], "物品"))
	return str(item)


func _item_glyph(item: Variant) -> String:
	if item is Dictionary:
		var explicit: Variant = _dict_first(item, ["glyph", "symbol", "short"], null)
		if explicit != null and not str(explicit).is_empty():
			return str(explicit).substr(0, 1)
	var title := _item_title(item)
	return title.substr(0, 1) if not title.is_empty() else "?"


func _item_texture(item: Variant) -> Texture2D:
	if not (item is Dictionary):
		return null
	var item_id := str(_dict_first(item, ["item_id", "id"], ""))
	if item_id == "body":
		return null
	if item_id.is_empty():
		return null
	if _item_icon_cache.has(item_id):
		return _item_icon_cache[item_id]
	var texture := load(ITEM_ICON_DIR + item_id + ".png") as Texture2D
	_item_icon_cache[item_id] = texture
	return texture


func _item_color(item: Variant) -> Color:
	if item is Dictionary:
		var explicit: Variant = _dict_first(item, ["color", "tint", "ui_color"], null)
		if explicit is Color:
			return explicit
	var title := _item_title(item)
	var hue := float(abs(hash(title)) % 360) / 360.0
	return Color.from_hsv(hue, 0.42, 0.58, 0.96)


func _dict_first(data: Dictionary, keys: Array, fallback: Variant = null) -> Variant:
	for key: Variant in keys:
		if data.has(key):
			return data[key]
	return fallback


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	if _ui_font != null:
		label.add_theme_font_override("font", _ui_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.01, 0.008, 0.006, 0.9))
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_note_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	if _note_font != null:
		label.add_theme_font_override("font", _note_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.22, 0.15, 0.08, 0.14))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _style(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.border_width_left = width
	box.border_width_top = width
	box.border_width_right = width
	box.border_width_bottom = width
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	return box
