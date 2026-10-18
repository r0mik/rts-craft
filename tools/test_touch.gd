extends SceneTree
## Touch controls check: starts a battle, plays fingers on it and checks what happened.
## Usage: godot --headless --path . --script tools/test_touch.gd

var game
var failed := 0


func _initialize() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	root.push_input(e, true)  # viewport coordinates
	await _frames(1)


func _drag(index: int, from: Vector2, to: Vector2, steps := 6) -> void:
	for i in range(1, steps + 1):
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = from.lerp(to, float(i) / steps)
		e.relative = (to - from) / steps
		root.push_input(e, true)
		await _frames(1)


func _tap(pos: Vector2) -> void:
	await _touch(0, pos, true)
	await _touch(0, pos, false)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failed += 1


func _run() -> void:
	await _frames(10)
	var v = game.view
	var workers: Array = game.team_units(game.PLAYER)
	var w = workers[0]
	v.focus = w.position
	await _frames(3)
	var wsp: Vector2 = v.to_screen(w.position, v.mid_of(w))

	await _tap(wsp + Vector2(6, 4))  # a fingertip slightly off the unit still picks it
	_check(game.touch_mode, "a touch turns touch mode on")
	_check(game.selection == [w], "tap selects a unit")
	_check(game.hud.touch_bar.visible, "touch bar is shown")

	await _tap(wsp)
	_check(game.selection.size() == workers.size(), "double tap selects every worker on screen (%d)" % game.selection.size())

	var ground: Vector2 = wsp + Vector2(0, -160)
	var goal: Vector2 = v.screen_to_ground(ground)
	await _tap(ground)
	_check(w.position.distance_to(w.target_pos) < 2000 and w.target_pos.distance_to(goal) < 80, "tap on the ground moves the selection")

	game.set_selection([])
	await _touch(0, wsp + Vector2(-140, -120), true)
	await _drag(0, wsp + Vector2(-140, -120), wsp + Vector2(140, 120))
	_check(game.dragging and game.drag_touch == 0, "dragging a finger draws a selection box")
	await _touch(0, wsp + Vector2(140, 120), false)
	_check(not game.dragging and game.selection.size() >= 1, "lifting the finger selects the units in the box (%d)" % game.selection.size())

	var before_focus: Vector2 = v.focus
	var before_dist: float = v.dist
	var a := Vector2(700, 400)
	var b := Vector2(900, 400)
	await _touch(0, a, true)
	await _touch(1, b, true)
	await _drag(1, b, b + Vector2(200, 0))  # spread: zoom in
	_check(v.dist < before_dist, "pinch zooms the camera (%.1f -> %.1f)" % [before_dist, v.dist])
	var sel_before: Array = game.selection.duplicate()
	await _drag(0, a, a + Vector2(-150, 0))
	await _touch(1, b + Vector2(200, 0), false)
	await _touch(0, a + Vector2(-150, 0), false)
	_check(v.focus != before_focus, "two fingers move the camera")
	_check(game.selection == sel_before, "a two-finger gesture gives no orders and keeps the selection")

	game.set_selection([w])
	var hold: Vector2 = wsp + Vector2(120, 60)
	var hold_goal: Vector2 = v.screen_to_ground(hold)
	await _touch(0, hold, true)
	await create_timer(0.6).timeout
	await _frames(2)
	await _touch(0, hold, false)
	_check(w.target_pos.distance_to(hold_goal) < 80, "holding a finger gives an order")
	_check(game.selection == [w], "the long press keeps the selection")

	# a building: the ghost follows the finger, lifting it places the building
	game.set_selection([w])
	game.bank[game.PLAYER] = 1000
	game.placing = "depot"
	var site: Vector2 = game.start_positions[game.PLAYER] + Vector2(260, 260)
	_check(game.can_place("depot", game.snap(site)), "test site is free")
	v.focus = site
	await _frames(2)
	var spot: Vector2 = v.to_screen(site)
	await _touch(0, spot + Vector2(0, 80), true)
	await _drag(0, spot + Vector2(0, 80), spot)
	await _touch(0, spot, false)
	_check(game.placing == "" and w.build_kind == "depot", "drag and lift places a building (%s, %s)" % [game.placing, w.build_kind])

	# a finger on an on-screen button (through the engine's touch-to-mouse emulation) presses it
	game.set_selection([])
	var add_btn: Button = game.hud._touch_add
	var at: Vector2 = root.get_final_transform() * add_btn.get_global_rect().get_center()
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new()
		e.position = at
		e.pressed = pressed
		Input.parse_input_event(e)
		Input.flush_buffered_events()
		await _frames(2)
	_check(game.touch_add, "tapping the + Select button turns it on")
	game.touch_add = false
	_check(w.build_kind == "depot", "a tap on a button gives no order in the world")

	game.select_army()
	_check(game.selection.all(func(u): return not u.is_worker()), "Army button selects combat units only")
	game.set_selection([w])
	game.control_group(1, true)
	game.set_selection([])
	game.control_group(1, false)
	_check(game.selection == [w], "control groups assign and recall")

	var real := InputEventMouseButton.new()
	real.button_index = MOUSE_BUTTON_LEFT
	real.pressed = true
	real.position = Vector2(800, 300)
	root.push_input(real, true)
	real = real.duplicate()
	real.pressed = false
	root.push_input(real, true)
	await _frames(2)
	_check(not game.touch_mode, "a real mouse click switches back to mouse controls")
	await _frames(2)
	_check(not game.hud.touch_bar.visible, "touch bar hides in mouse mode")

	print("touch test: %s" % ("OK" if failed == 0 else "%d FAILED" % failed))
	quit(1 if failed else 0)
