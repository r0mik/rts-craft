extends Control
## Screen-space overlay on top of the 3D view: health bars, progress bars, selection box,
## rally lines and the attack cursor.

const I18N = preload("res://scripts/i18n.gd")
var game


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	var v = game.view
	var vs := get_viewport_rect().size
	var all: Array = game.get_tree().get_nodes_in_group("units") + game.get_tree().get_nodes_in_group("buildings")
	for e in all:
		if not game.valid(e) or not game.visible_to_player(e):
			continue
		var is_b: bool = e.is_in_group("buildings")
		var damaged: bool = e.hp < e.max_hp
		var busy: bool = is_b and (e.constructing or not e.queue.is_empty())
		if not (e.selected or damaged or busy or game.Settings.always_hp):
			continue
		var top: float = v.top_of(e)
		var sp: Vector2 = v.to_screen(e.position, top + 0.5)
		if sp.x < -100 or sp.y < -100 or sp.x > vs.x + 100 or sp.y > vs.y + 100:
			continue
		var w_world: float = (e.size.x * 0.75 if is_b else e.radius * 2.6) / v.PX
		var w := clampf(v.px_size(e.position, w_world, top), 18.0, 220.0)
		var h := 5.0 if is_b else 4.0
		if e.selected or damaged or game.Settings.always_hp:
			_bar(Vector2(sp.x - w / 2.0, sp.y - h), w, h, e.hp / e.max_hp, _hp_color(e.hp / e.max_hp), e.max_hp)
			if is_b and e.max_shield > 0.0:  # energy shield from the ages, above the HP bar
				_bar(Vector2(sp.x - w / 2.0, sp.y - h - 5.0), w, 3.0, e.shield / e.max_shield, Color(0.4, 0.8, 1.0), 0)
		if is_b and e.constructing:
			_bar(Vector2(sp.x - w / 2.0, sp.y + 3.0), w, 4.0, e.build_progress, Color(0.35, 0.8, 1.0), 0)
		elif is_b and not e.queue.is_empty():
			_bar(Vector2(sp.x - w / 2.0, sp.y + 3.0), w, 4.0, e.prod_progress, Color(1.0, 0.85, 0.25), 0)
	for b in game.selected_buildings():
		if b.has_rally:
			var a: Vector2 = v.to_screen(b.position, 0.1)
			var r: Vector2 = v.to_screen(b.rally, 0.1)
			draw_dashed_line(a, r, Color(1.0, 0.9, 0.3, 0.7), 1.5, 6.0)
			draw_circle(r, 4.0, Color(1.0, 0.9, 0.3, 0.9))
	var mp := get_viewport().get_mouse_position()
	if game.dragging:
		var rect := Rect2(game.drag_start, Vector2.ZERO).expand(mp)
		draw_rect(rect, Color(0.3, 1.0, 0.35, 0.1), true)
		draw_rect(rect, Color(0.3, 1.0, 0.35, 0.9), false, 1.5)
	var silo = game.missile_silo()
	if game.missile_mode and silo != null:  # missile target: silo range and blast radius at the cursor
		var md: Dictionary = game.Defs.MISSILES[silo.missile_type]
		var wp: Vector2 = v.screen_to_ground(mp)
		var ok: bool = silo.position.distance_to(wp) <= md.range
		var c := Color(1.0, 0.2, 0.1) if ok else Color(0.5, 0.5, 0.5)
		v.set_range_ring(silo.position, md.range)
		_ground_circle(wp, md.radius, c, 2.0)
		draw_circle(mp, 4.0, c)
		if not ok:
			draw_string(get_theme_default_font(), mp + Vector2(12, -10), I18N.t("слишком далеко"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)
	else:
		v.set_range_ring(Vector2.ZERO, 0.0)
	if game.attack_mode:
		var c := Color(1.0, 0.25, 0.2)
		draw_arc(mp, 12.0, 0.0, TAU, 24, c, 2.0)
		draw_line(mp + Vector2(-18, 0), mp + Vector2(-6, 0), c, 2.0)
		draw_line(mp + Vector2(6, 0), mp + Vector2(18, 0), c, 2.0)
		draw_line(mp + Vector2(0, -18), mp + Vector2(0, -6), c, 2.0)
		draw_line(mp + Vector2(0, 6), mp + Vector2(0, 18), c, 2.0)


func _ground_circle(center: Vector2, r: float, c: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 65:
		pts.append(game.view.to_screen(center + Vector2.from_angle(i * TAU / 64.0) * r, 0.2))
	draw_polyline(pts, c, w)


func _hp_color(f: float) -> Color:
	if f > 0.6:
		return Color(0.25, 0.95, 0.3)
	if f > 0.3:
		return Color(1.0, 0.8, 0.15)
	return Color(1.0, 0.25, 0.15)


## Segmented bar in StarCraft II style (one notch per 50 HP when max_value > 0).
func _bar(pos: Vector2, w: float, h: float, f: float, col: Color, max_value: float) -> void:
	var r := Rect2(pos, Vector2(w, h))
	draw_rect(r.grow(1.0), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(pos, Vector2(w * clampf(f, 0.0, 1.0), h)), col)
	draw_rect(Rect2(pos, Vector2(w * clampf(f, 0.0, 1.0), h * 0.4)), Color(1, 1, 1, 0.25))
	if max_value > 0.0:
		var n := int(max_value / 50.0)
		if n > 1 and w / n >= 3.0:
			for i in range(1, n):
				var x := pos.x + w * i / n
				draw_line(Vector2(x, pos.y), Vector2(x, pos.y + h), Color(0, 0, 0, 0.5), 1.0)
