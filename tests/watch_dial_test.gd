extends SceneTree

const WatchDialScript = preload("res://watch_dial.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var watch = WatchDialScript.new()
	root.add_child(watch)
	# Let the CanvasItem receive a real draw notification so the procedural
	# watch face is exercised in addition to its progress arithmetic.
	await process_frame
	var failures := 0

	watch.set_state(1, 120.0, 120.0, 0, "day")
	failures += _expect_close(watch.get_outer_ratio(), 1.0, "120s starts with a full green ring")
	failures += _expect_close(watch.get_inner_ratio(), 0.0, "120s starts with an empty red ring")

	watch.set_state(1, 90.0, 120.0, 1, "day")
	failures += _expect_close(watch.get_outer_ratio(), 0.5, "90s leaves half of the green ring")
	failures += _expect_close(watch.get_inner_ratio(), 0.0, "red stays empty during the first lap")

	watch.set_state(1, 60.0, 120.0, 2, "day")
	failures += _expect_close(watch.get_outer_ratio(), 0.0, "green is empty at the lap boundary")
	failures += _expect_close(watch.get_inner_ratio(), 0.0, "red starts empty at the lap boundary")

	watch.set_state(2, 30.0, 120.0, 0, "night")
	failures += _expect_close(watch.get_outer_ratio(), 0.0, "green stays empty during the second lap")
	failures += _expect_close(watch.get_inner_ratio(), 0.5, "30s fills half of the red ring")

	watch.set_state(2, 0.0, 120.0, 3, "night")
	failures += _expect_close(watch.get_inner_ratio(), 1.0, "zero fills the red ring")
	await process_frame

	if watch.custom_minimum_size != Vector2(360.0, 440.0):
		failures += 1
		push_error("watch should keep its 360x440 presentation footprint")

	print("WATCH_DIAL_TEST assertions=10 failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func _expect_close(actual: float, expected: float, message: String) -> int:
	if is_equal_approx(actual, expected):
		return 0
	push_error("%s: expected %.3f, got %.3f" % [message, expected, actual])
	return 1
