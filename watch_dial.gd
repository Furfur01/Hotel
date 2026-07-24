class_name HotelWatchDial
extends Control

## A text-free, hand-drawn wristwatch used as the run clock.  During the first
## first half of the active phase its green outer ring drains to cream; during
## the second half its red inner ring fills from cream.

const WATCH_SIZE := Vector2(360.0, 440.0)
const DURATION_FALLBACK := 120.0

const CREAM := Color("d7c9a5")
const CREAM_DARK := Color("8f8267")
const GREEN := Color("496d4e")
const RED := Color("8d3029")
const BRASS := Color("a88243")
const GLASS := Color(0.91, 0.90, 0.82, 0.10)
const LEATHER := Color("3a2a22")
const INK := Color("191512")

var _day := 1
var _time_remaining := DURATION_FALLBACK
var _duration := DURATION_FALLBACK
var _strikes := 0
var _phase: Variant = "day"


func _init() -> void:
	custom_minimum_size = WATCH_SIZE
	size = WATCH_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func set_state(day: int, time_remaining: float, duration: float, strikes: int, phase: Variant) -> void:
	_day = maxi(day, 1)
	_duration = maxf(duration, 0.001)
	_time_remaining = clampf(time_remaining, 0.0, _duration)
	_strikes = clampi(strikes, 0, 3)
	_phase = phase
	queue_redraw()


func get_outer_ratio() -> float:
	var half := _duration * 0.5
	return clampf((_time_remaining - half) / half, 0.0, 1.0)


func get_inner_ratio() -> float:
	var half := _duration * 0.5
	return clampf((half - _time_remaining) / half, 0.0, 1.0)


func _draw() -> void:
	var strike_mix := clampf(float(_strikes) / 3.0, 0.0, 1.0)
	var danger_ink := INK.lerp(Color("080405"), strike_mix)
	var danger_leather := LEATHER.lerp(Color("241012"), strike_mix * 0.88)
	var danger_cream := CREAM.lerp(Color("b69a87"), strike_mix * 0.42)
	var danger_brass := BRASS.lerp(Color("6a3a32"), strike_mix * 0.62)
	var wrist := Color("765340").lerp(Color("4e292b"), strike_mix * 0.46)
	var sleeve := Color("282521").lerp(Color("170d0f"), strike_mix * 0.72)

	# The watch sits on a raised wrist instead of floating as an isolated HUD
	# circle.  Most of the wrist is covered by the case and the dark cuff.
	_draw_rounded_box(Rect2(106.0, -24.0, 148.0, 385.0), wrist, 52.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(96.0, 322.0),
		Vector2(264.0, 322.0),
		Vector2(310.0, 452.0),
		Vector2(45.0, 452.0),
	]), sleeve)
	draw_line(Vector2(97.0, 329.0), Vector2(263.0, 329.0), danger_ink.lightened(0.18), 5.0, true)

	# A restrained leather strap makes the circular timer read as an object in
	# the player's hand, not a floating game HUD.
	_draw_rounded_box(Rect2(127.0, -8.0, 106.0, 148.0), danger_leather, 24.0)
	_draw_rounded_box(Rect2(127.0, 300.0, 106.0, 150.0), danger_leather, 24.0)
	for y in [18.0, 43.0, 371.0, 396.0, 421.0]:
		draw_line(Vector2(145.0, y), Vector2(215.0, y), danger_ink.lightened(0.12), 2.0, true)

	var center := Vector2(180.0, 220.0)
	# Drop shadow, dark case and worn brass bezel.
	draw_circle(center + Vector2(7.0, 10.0), 157.0, Color(0.02, 0.015, 0.012, 0.54))
	draw_circle(center, 157.0, danger_ink)
	draw_circle(center, 151.0, danger_brass.darkened(0.34))
	draw_circle(center, 145.0, danger_brass)
	draw_circle(center, 137.0, danger_ink)
	draw_circle(center, 132.0, danger_cream)

	# Side crown and guards.
	_draw_rounded_box(Rect2(329.0, 193.0, 25.0, 54.0), danger_ink, 6.0)
	_draw_rounded_box(Rect2(335.0, 200.0, 22.0, 40.0), danger_brass, 5.0)
	for y in [206.0, 214.0, 222.0, 230.0, 238.0]:
		draw_line(Vector2(339.0, y), Vector2(353.0, y), danger_ink, 1.5, true)

	# Two full cream tracks remain visible as time is consumed/fills.
	var ring_base := CREAM_DARK.lerp(Color("63534e"), strike_mix * 0.45)
	draw_arc(center, 112.0, -PI * 0.5, PI * 1.5, 128, ring_base, 19.0, true)
	draw_arc(center, 82.0, -PI * 0.5, PI * 1.5, 128, ring_base, 17.0, true)

	var outer_ratio := get_outer_ratio()
	var inner_ratio := get_inner_ratio()
	_draw_progress_arc(center, 112.0, 19.0, outer_ratio, GREEN.lerp(Color("35433b"), strike_mix * 0.48))
	_draw_progress_arc(center, 82.0, 17.0, inner_ratio, RED.lerp(Color("4c161a"), strike_mix * 0.34))

	# Unnumbered index marks keep the dial readable without adding UI text.
	for i in range(12):
		var angle := -PI * 0.5 + TAU * float(i) / 12.0
		var outer := center + Vector2(cos(angle), sin(angle)) * 64.0
		var inner := center + Vector2(cos(angle), sin(angle)) * (56.0 if i % 3 == 0 else 59.0)
		draw_line(inner, outer, danger_ink, 3.0 if i % 3 == 0 else 1.7, true)

	# A small mechanical centre is decorative only; progress lives exclusively
	# in the coloured rings.
	draw_circle(center, 13.0, danger_ink)
	draw_circle(center, 8.0, danger_brass)
	draw_circle(center - Vector2(2.0, 2.0), 2.5, danger_cream.lightened(0.22))

	# Uneven highlights and scratches prevent the watch from looking like a
	# vector dashboard widget.
	draw_arc(center - Vector2(4.0, 5.0), 126.0, PI * 1.07, PI * 1.72, 32, GLASS, 7.0, true)
	draw_line(Vector2(102.0, 118.0), Vector2(135.0, 97.0), Color(0.95, 0.91, 0.76, 0.12), 3.0, true)
	draw_line(Vector2(224.0, 337.0), Vector2(249.0, 321.0), danger_ink.lightened(0.20), 2.0, true)


func _draw_progress_arc(center: Vector2, radius: float, width: float, ratio: float, color: Color) -> void:
	if ratio <= 0.001:
		return
	var start := -PI * 0.5
	var finish := start + TAU * clampf(ratio, 0.0, 1.0)
	draw_arc(center, radius, start, finish, maxi(3, ceili(128.0 * ratio)), color, width, true)
	var cap_radius := width * 0.5
	draw_circle(center + Vector2(cos(start), sin(start)) * radius, cap_radius, color)
	if ratio < 0.995:
		draw_circle(center + Vector2(cos(finish), sin(finish)) * radius, cap_radius, color)


func _draw_rounded_box(rect: Rect2, color: Color, radius: float) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	var corner := roundi(radius)
	style.corner_radius_top_left = corner
	style.corner_radius_top_right = corner
	style.corner_radius_bottom_left = corner
	style.corner_radius_bottom_right = corner
	draw_style_box(style, rect)
