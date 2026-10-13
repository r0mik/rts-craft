extends CanvasLayer
## On-screen interface in the style of StarCraft: resources top-right, and a bottom console with
## the minimap (left), the selection panel with a live 3D portrait or unit wireframes (centre) and
## a 5x3 command card of square icon buttons with hotkeys and costs (right).
## Unit and building icons are rendered from the 3D models at startup (skipped when headless).

const Defs = preload("res://scripts/defs.gd")
const MinimapScript = preload("res://scripts/minimap.gd")
const OverlayScript = preload("res://scripts/overlay.gd")

const FRAME := Color(0.3, 0.62, 0.85)
const FRAME_DIM := Color(0.16, 0.32, 0.45)
const BG := Color(0.035, 0.05, 0.075, 0.97)
const TEXT := Color(0.82, 0.92, 1.0)
const ACCENT := Color(0.45, 0.85, 1.0)
const GOLD := Color(1.0, 0.85, 0.35)
const CONSOLE_H := 214.0
const CARD_COLS := 5
const CARD_ROWS := 3
const BTN := 62.0

var game
var res_minerals: Label
var res_supply: Label
var res_time: Label
var res_age: Label
var msg_label: Label
var msg_time := 0.0
var big_label: Label
var minimap
var center: Control           # selection area, rebuilt when the selection changes
var card: GridContainer       # command card
var cmd_signature := ""
var sel_signature := ""
var icons := {}               # kind -> Texture2D rendered from the 3D model
# single-selection widgets, refreshed every frame
var _name_label: Label
var _hp_bar: Control
var _stats_label: Label
var _queue_box: HBoxContainer
var _portrait_vp: SubViewport
var _portrait_holder: Node3D
var _portrait_cam: Camera3D
var _portrait_kind := ""
var _wire_cells: Array = []   # [{button, entity}]
var _combo_label: RichTextLabel  # merge hints under the wireframes
const PART_NAMES := {"marine": "пехотинцев", "medic": "медиков", "tank": "танков", "wraith": "истребителей"}


func setup(g) -> void:
	game = g
	var overlay = OverlayScript.new()  # first child, so panels draw on top of it
	overlay.game = game
	add_child(overlay)
	_build_top()
	_build_console()
	msg_label = Label.new()
	msg_label.anchor_right = 1.0
	msg_label.offset_top = 46.0
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.add_theme_font_size_override("font_size", 20)
	msg_label.add_theme_color_override("font_color", GOLD)
	msg_label.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_label.add_theme_constant_override("outline_size", 4)
	msg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(msg_label)
	big_label = Label.new()
	big_label.anchor_right = 1.0
	big_label.anchor_bottom = 1.0
	big_label.offset_bottom = -CONSOLE_H
	big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big_label.add_theme_font_size_override("font_size", 72)
	big_label.add_theme_color_override("font_outline_color", Color.BLACK)
	big_label.add_theme_constant_override("outline_size", 10)
	big_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(big_label)
	_render_icons()


# --- Layout -------------------------------------------------------------------

static func panel_style(bg: Color, border: Color, width := 2, radius := 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _label(text: String, size: int, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	return l


func _build_top() -> void:
	var help := _label("ЛКМ — выбор   ПКМ — приказ   WASD — камера   G — атака   Ctrl+1..9 — группы   Space — база\n" +
		"Объединение: 5 пехотинцев + 2 медика → батальон (Z), 4 танка → супертанк (C), 3 истребителя → фантом (V)", 13,
		Color(0.8, 0.9, 1.0, 0.55))
	help.position = Vector2(12, 8)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(help)
	var top := PanelContainer.new()
	top.anchor_left = 1.0
	top.anchor_right = 1.0
	top.offset_left = -600.0
	top.offset_right = -8.0
	top.offset_top = 6.0
	top.add_theme_stylebox_override("panel", panel_style(BG, FRAME_DIM, 1, 6))
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	top.add_child(row)
	row.add_child(ResIcon.new("minerals"))
	res_minerals = _label("0", 19)
	res_minerals.custom_minimum_size.x = 70
	row.add_child(res_minerals)
	row.add_child(ResIcon.new("supply"))
	res_supply = _label("0/0", 19)
	res_supply.custom_minimum_size.x = 90
	row.add_child(res_supply)
	res_age = _label("I", 19, GOLD)
	res_age.tooltip_text = "Текущая эпоха"
	res_age.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(res_age)
	row.add_child(ResIcon.new("time"))
	res_time = _label("0:00", 19)
	res_time.custom_minimum_size.x = 60
	row.add_child(res_time)


func _build_console() -> void:
	var console := PanelContainer.new()
	console.anchor_top = 1.0
	console.anchor_bottom = 1.0
	console.anchor_right = 1.0
	console.offset_top = -CONSOLE_H
	var st := panel_style(Color(0.02, 0.03, 0.05, 0.98), FRAME, 2, 0)
	st.border_width_left = 0
	st.border_width_right = 0
	st.border_width_bottom = 0
	st.border_width_top = 3
	st.shadow_color = Color(0.2, 0.6, 1.0, 0.25)
	st.shadow_size = 8
	console.add_theme_stylebox_override("panel", st)
	console.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(console)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	console.add_child(row)
	# minimap in its own frame
	var mm_frame := PanelContainer.new()
	mm_frame.add_theme_stylebox_override("panel", panel_style(Color.BLACK, FRAME, 2, 3))
	row.add_child(mm_frame)
	minimap = MinimapScript.new()
	minimap.game = game
	minimap.custom_minimum_size = Vector2(248, 186)
	mm_frame.add_child(minimap)
	# selection panel
	var sel_frame := PanelContainer.new()
	sel_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_frame.add_theme_stylebox_override("panel", panel_style(BG, FRAME_DIM, 2, 3))
	row.add_child(sel_frame)
	center = MarginContainer.new()
	sel_frame.add_child(center)
	# command card
	var card_frame := PanelContainer.new()
	card_frame.add_theme_stylebox_override("panel", panel_style(BG, FRAME, 2, 3))
	row.add_child(card_frame)
	card = GridContainer.new()
	card.columns = CARD_COLS
	card.add_theme_constant_override("h_separation", 4)
	card.add_theme_constant_override("v_separation", 4)
	card_frame.add_child(card)


func show_message(text: String) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_time = 3.0


func show_big(text: String, color: Color) -> void:
	big_label.text = text + "\n[R] — заново"
	big_label.add_theme_color_override("font_color", color)


func _process(delta: float) -> void:
	if game == null:
		return
	var t := int(game.elapsed)
	res_minerals.text = str(game.bank[0])
	var used: int = game.supply_used(0)
	var cap: int = game.supply_cap(0)
	res_supply.text = "%d/%d" % [used, cap]
	res_supply.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35) if used >= cap else TEXT)
	res_time.text = "%d:%02d" % [t / 60, t % 60]
	var age: Dictionary = Defs.AGES[game.ages[0]]
	res_age.text = "Эпоха %s" % age.short
	res_age.tooltip_text = age.name
	msg_time -= delta
	msg_label.modulate.a = clampf(msg_time, 0.0, 1.0)
	_update_selection(delta)
	_update_commands()


# --- Selection panel ----------------------------------------------------------

func _update_selection(delta: float) -> void:
	var sel: Array = game.selection.filter(func(e): return game.valid(e))
	var ids := []
	for e in sel:
		ids.append(str(e.get_instance_id()))
	var sig := ",".join(ids) + "#" + str(icons.size())
	if sig != sel_signature:
		sel_signature = sig
		_rebuild_selection(sel)
	if sel.size() == 1:
		_refresh_single(sel[0], delta)
	elif sel.size() > 1:
		if _combo_label != null and is_instance_valid(_combo_label):
			_combo_label.text = combo_hint(sel)
		for cell in _wire_cells:
			var b: Control = cell.button
			b.queue_redraw()


func _clear_center() -> void:
	for c in center.get_children():
		c.queue_free()
	_wire_cells.clear()
	_combo_label = null
	_name_label = null
	_portrait_vp = null
	_portrait_kind = ""


func _rebuild_selection(sel: Array) -> void:
	_clear_center()
	if sel.is_empty():
		var hint := _label("Ничего не выбрано.\n\nВыдели рабочих и строй здания,\nвыдели Command Center или Barracks и нанимай юнитов.", 15,
			Color(0.75, 0.85, 0.95, 0.7))
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		center.add_child(hint)
	elif sel.size() == 1:
		_build_single()
	else:
		_build_wireframes(sel)


func _build_single() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	center.add_child(row)
	# live 3D portrait
	var pf := PanelContainer.new()
	pf.add_theme_stylebox_override("panel", panel_style(Color(0.02, 0.06, 0.06), FRAME, 2, 3))
	row.add_child(pf)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(150, 166)
	pf.add_child(svc)
	_portrait_vp = SubViewport.new()
	_portrait_vp.own_world_3d = true
	_portrait_vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(_portrait_vp)
	_setup_stage(_portrait_vp, Color(0.03, 0.1, 0.1))
	_portrait_cam = Camera3D.new()
	_portrait_cam.fov = 32.0
	_portrait_vp.add_child(_portrait_cam)
	_portrait_holder = Node3D.new()
	_portrait_vp.add_child(_portrait_holder)
	# text column
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	_name_label = _label("", 20, ACCENT)
	col.add_child(_name_label)
	_hp_bar = HpBar.new()
	_hp_bar.custom_minimum_size = Vector2(260, 20)
	_hp_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_hp_bar)
	_stats_label = _label("", 15)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_stats_label)
	_queue_box = HBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 4)
	col.add_child(_queue_box)


func _refresh_single(e, delta: float) -> void:
	if _name_label == null:
		return
	var mine: bool = e.team == 0
	_name_label.text = "%s%s" % [e.stats.name, "" if mine else "  — противник"]
	_name_label.add_theme_color_override("font_color", ACCENT if mine else Color(1.0, 0.5, 0.45))
	_hp_bar.set_meta("f", e.hp / e.max_hp)
	_hp_bar.set_meta("text", "%d / %d" % [ceili(e.hp), int(e.max_hp)])
	_hp_bar.queue_redraw()
	_stats_label.text = _stats_text(e)
	# portrait model follows the selected kind and slowly turns
	if _portrait_vp != null:
		var key: String = "%s:%d" % [e.kind, e.team]
		if key != _portrait_kind:
			_portrait_kind = key
			for c in _portrait_holder.get_children():
				c.queue_free()
			var m: Node3D = game.view.builders[maxi(e.team, 0)].build(e.kind)
			_portrait_holder.add_child(m)
			frame_camera(_portrait_cam, m, Vector3(1.0, 0.55, 1.2), 0.75)
		_portrait_holder.rotation.y += delta * 0.5
	# production queue
	var q: Array = e.queue if e.is_in_group("buildings") else []
	var qsig := ",".join(q)
	if _queue_box.get_meta("sig", "") != qsig:
		_queue_box.set_meta("sig", qsig)
		for c in _queue_box.get_children():
			c.queue_free()
		for i in q.size():
			var slot := QueueSlot.new()
			slot.hud = self
			slot.item = q[i]
			slot.building = e
			slot.first = i == 0
			slot.custom_minimum_size = Vector2(44, 44)
			slot.tooltip_text = game.item_name(q[i])
			_queue_box.add_child(slot)
	for c in _queue_box.get_children():
		(c as Control).queue_redraw()


## Merge hints for a selection: progress towards every recipe that uses a selected kind,
## e.g. "Батальон (Z): пехотинцев 3/5, медиков 1/2" (green when ready).
func combo_hint(sel: Array) -> String:
	var lines := []
	for ck in Defs.COMBOS:
		var cd: Dictionary = Defs.COMBOS[ck]
		var have_any := false
		var ready := true
		var parts := []
		for part in cd.parts:
			var n := sel.filter(func(u): return game.valid(u) and u.team == 0 and u.kind == part).size()
			have_any = have_any or n > 0
			ready = ready and n >= int(cd.parts[part])
			parts.append("%s %d/%d" % [PART_NAMES.get(part, part), mini(n, cd.parts[part]), cd.parts[part]])
		if not have_any:
			continue
		if ready:
			lines.append("[color=#7dff8a]Можно объединить → %s: нажмите %s[/color]" % [cd.name, OS.get_keycode_string(cd.key)])
		else:
			lines.append("[color=#9cc8e8]%s (%s): нужно %s[/color]" % [cd.name, OS.get_keycode_string(cd.key), ", ".join(parts)])
	return "\n".join(lines)


func _stats_text(e) -> String:
	var lines := []
	var up: Dictionary = game.upgrades[maxi(e.team, 0)]
	if e.is_in_group("units"):
		if e.stats.get("healer", false):
			lines.append("Лечение %d HP/с   радиус %d" % [e.stats.heal_rate, e.stats.range])
		elif e.stats.get("unarmed", false):
			lines.append("Без оружия   обзор %d" % e.stats.sight)
			if e.kind == "scout":
				lines.append("Маяк: " + ("готов (F)" if e.ability_cd <= 0.0 else "через %d с" % ceili(e.ability_cd)))
			if e.kind == "beacon":
				lines.append("Погаснет через %d с" % ceili(e.life_left))
		else:
			lines.append("Урон %d (+%d)   Броня %d (+%d)   Дальность %d" % [e.stats.damage, up.weapons,
				e.stats.get("armor", 0), up.armor, e.stats.range])
			var vs: Dictionary = Defs.DAMAGE_VS.get(e.kind, {})
			if not vs.is_empty():
				var parts := []
				for c in vs:
					parts.append("%s ×%s" % [Defs.CLASS_NAMES[c], str(vs[c])])
				lines.append("Против: " + ", ".join(parts))
			lines.append("Тип: %s" % Defs.CLASS_NAMES[game.armor_class(e)])
			if e.stats.has("min_range"):
				lines.append("Мёртвая зона: не стреляет ближе %d" % e.stats.min_range)
			lines.append("Скорость %d" % e.stats.speed)
		if e.carrying > 0:
			lines.append("Несёт минералы: %d" % e.carrying)
		for ck in Defs.COMBOS:  # how this unit can be merged
			var cd: Dictionary = Defs.COMBOS[ck]
			if cd.parts.has(e.kind) and e.team == 0:
				var recipe := []
				for part in cd.parts:
					recipe.append("%d %s" % [cd.parts[part], PART_NAMES.get(part, part)])
				lines.append("Объединение: выделите %s → %s (%s)" % [" + ".join(recipe), cd.name, OS.get_keycode_string(cd.key)])
	else:
		if e.constructing:
			lines.append("Строится: %d%%" % int(e.build_progress * 100.0))
		lines.append("Броня %d" % e.stats.get("armor", 0))
		if e.max_shield > 0.0:
			lines.append("Щит: %d / %d (восстанавливается)" % [int(e.shield), int(e.max_shield)])
		if e.kind == "cc" and e.team == 0:
			lines.append("Эпоха: %s" % Defs.AGES[game.ages[0]].name)
		if e.stats.has("damage"):
			lines.append("Оборона: урон %d, дальность %d" % [e.stats.damage, e.stats.range])
		if e.kind == "silo":
			lines.append("Ракета: " + ("%s — готова к пуску (L)" % Defs.MISSILES[e.missile_type].name if e.missile_ready
				else "нет (M, J, N, K — собрать)"))
		if e.stats.has("research"):
			lines.append("Улучшения: Оружие +%d, Броня +%d" % [up.weapons, up.armor])
		if e.team == 0 and not e.stats.trains.is_empty() and not e.constructing:
			lines.append("ПКМ — точка сбора")
	return "\n".join(lines)


func _build_wireframes(sel: Array) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	center.add_child(col)
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	_combo_label = RichTextLabel.new()
	_combo_label.bbcode_enabled = true
	_combo_label.fit_content = true
	_combo_label.scroll_active = false
	_combo_label.add_theme_font_size_override("normal_font_size", 14)
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_combo_label)
	for e in sel.slice(0, 30):
		var b := WireCell.new()
		b.hud = self
		b.entity = e
		b.custom_minimum_size = Vector2(52, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = e.stats.name
		b.add_theme_stylebox_override("normal", panel_style(Color(0.04, 0.08, 0.1), FRAME_DIM, 1, 2))
		b.add_theme_stylebox_override("hover", panel_style(Color(0.06, 0.12, 0.16), ACCENT, 1, 2))
		b.add_theme_stylebox_override("pressed", panel_style(Color(0.1, 0.18, 0.22), ACCENT, 1, 2))
		b.pressed.connect(func():
			if game.valid(e):
				game.set_selection([e]))
		grid.add_child(b)
		_wire_cells.append({"button": b, "entity": e})


# --- Command card -------------------------------------------------------------

func _update_commands() -> void:
	var cmds: Array = game.get_commands()
	var parts := [str(icons.size())]
	for c in cmds:
		parts.append("%s/%s" % [c.label, c.get("disabled", false)])
	var sig := "|".join(parts)
	if sig != cmd_signature:
		cmd_signature = sig
		for child in card.get_children():
			child.queue_free()
		for i in CARD_COLS * CARD_ROWS:
			var b := CmdButton.new()
			b.hud = self
			b.custom_minimum_size = Vector2(BTN, BTN)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_stylebox_override("normal", panel_style(Color(0.05, 0.09, 0.12), FRAME_DIM, 2, 3))
			b.add_theme_stylebox_override("hover", panel_style(Color(0.08, 0.15, 0.2), ACCENT, 2, 3))
			b.add_theme_stylebox_override("pressed", panel_style(Color(0.14, 0.24, 0.3), Color.WHITE, 2, 3))
			b.add_theme_stylebox_override("disabled", panel_style(Color(0.03, 0.04, 0.05), Color(0.1, 0.14, 0.18), 1, 3))
			if i < cmds.size():
				var c: Dictionary = cmds[i]
				b.cmd = c
				b.tooltip_text = c.label
				b.pressed.connect(c["fn"])
			else:
				b.disabled = true
			card.add_child(b)
	for b in card.get_children():
		(b as Control).queue_redraw()


# --- Icons and portraits ------------------------------------------------------

## A lit stage for rendering models into a SubViewport.
func _setup_stage(vp: SubViewport, bg: Color, transparent := false) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = bg
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.68, 0.8)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	env.environment = e
	vp.add_child(env)
	vp.transparent_bg = transparent
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.5
	vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.5, 0.8, 1.0)
	vp.add_child(rim)


## Points the camera at a model so its whole bounding box fits the view.
static func frame_camera(cam: Camera3D, model: Node3D, dir: Vector3, fill := 0.95) -> void:
	var box := _model_aabb(model)
	var c := box.get_center()
	var r := maxf(box.size.length() * 0.5, 0.5)
	var dist := r / sin(deg_to_rad(cam.fov) * 0.5) * fill
	cam.look_at_from_position(c + dir.normalized() * dist, c, Vector3.UP)


static func _model_aabb(root: Node3D) -> AABB:
	var res := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		var hidden := false
		while n != root and n != null:
			var n3 := n as Node3D
			if not n3.visible:
				hidden = true
			xf = n3.transform * xf
			n = n.get_parent()
		if hidden:
			continue
		var bb: AABB = xf * (mi as MeshInstance3D).mesh.get_aabb()
		res = bb if first else res.merge(bb)
		first = false
	return res


## Renders an icon for every unit and building kind, one at a time, into `icons`.
func _render_icons() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(112, 112)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	_setup_stage(vp, Color(0, 0, 0, 0), true)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	var kinds: Array = Defs.UNITS.keys() + Defs.BUILDINGS.keys()
	for kind in kinds:
		var m: Node3D = game.view.builders[0].build(kind)
		vp.add_child(m)
		frame_camera(cam, m, Vector3(1.0, 0.8, 1.15), 0.6)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img != null and not img.is_empty():
			icons[kind] = ImageTexture.create_from_image(img)
		m.queue_free()
	vp.queue_free()


# --- Widgets --------------------------------------------------------------------

## Square command button: icon (model render or vector glyph), hotkey letter, cost.
class CmdButton extends Button:
	var hud
	var cmd := {}

	func _draw() -> void:
		if cmd.is_empty():
			return
		var r := Rect2(Vector2(5, 5), size - Vector2(10, 10))
		var icon: String = cmd.get("icon", "")
		var tex: Texture2D = hud.icons.get(icon)
		var off: bool = cmd.get("disabled", false) or int(cmd.get("cost", 0)) > int(hud.game.bank[0])
		var tint := Color(1, 1, 1, 0.35) if off else Color.WHITE
		var font := get_theme_default_font()
		if tex != null:
			draw_texture_rect(tex, r, false, tint)
		elif icon.begins_with("@"):
			Glyphs.draw(self, icon, r, tint)
		else:  # icon not rendered yet: initials
			var initials: String = String(cmd.label).substr(0, 2)
			draw_string(font, Vector2(r.position.x, r.get_center().y + 8), initials, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22,
				Color(0.6, 0.85, 1.0, tint.a))
		var key := OS.get_keycode_string(int(cmd.key))
		draw_string_outline(font, Vector2(5, 17), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.BLACK)
		draw_string(font, Vector2(5, 17), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GOLD)
		var cost := int(cmd.get("cost", 0))
		if cost > 0:
			var cs := str(cost)
			var col := Color(1.0, 0.45, 0.4) if cost > int(hud.game.bank[0]) else Color(0.5, 0.9, 1.0)
			draw_string_outline(font, Vector2(0, size.y - 5), cs, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 12, 4, Color.BLACK)
			draw_string(font, Vector2(0, size.y - 5), cs, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 12, col)


## Multi-selection cell: unit icon tinted by health, with a health bar; click selects that unit.
class WireCell extends Button:
	var hud
	var entity

	func _draw() -> void:
		if not is_instance_valid(entity) or not entity.is_alive():
			return
		var f: float = entity.hp / entity.max_hp
		var col := HpBar.hp_color(f)
		var tex: Texture2D = hud.icons.get(entity.kind)
		var r := Rect2(Vector2(3, 2), size - Vector2(6, 12))
		if tex != null:
			draw_texture_rect(tex, r, false, Color.WHITE.lerp(col, 0.35))
		else:
			draw_string(get_theme_default_font(), Vector2(0, size.y * 0.55), String(entity.stats.name).substr(0, 3),
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, col)
		draw_rect(Rect2(4, size.y - 8, size.x - 8, 4), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(4, size.y - 8, (size.x - 8) * f, 4), col)


## Production queue slot: icon of the item, the first one with a progress bar.
class QueueSlot extends Control:
	var hud
	var item := ""
	var building
	var first := false

	func _draw() -> void:
		draw_style_box(hud.panel_style(Color(0.04, 0.08, 0.1), ACCENT if first else FRAME_DIM, 1, 2), Rect2(Vector2.ZERO, size))
		var tex: Texture2D = hud.icons.get(item)
		var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		if tex != null:
			draw_texture_rect(tex, r, false)
		else:
			Glyphs.draw(self, "@" + item, r, Color.WHITE)
		if first and is_instance_valid(building):
			draw_rect(Rect2(2, size.y - 6, (size.x - 4) * float(building.prod_progress), 4), Color(0.4, 1.0, 0.5))


## Health bar with numbers, coloured green → yellow → red.
class HpBar extends Control:
	static func hp_color(f: float) -> Color:
		if f < 0.5:
			return Color(0.95, 0.25, 0.2).lerp(Color(1.0, 0.85, 0.2), clampf(f * 2.0, 0.0, 1.0))
		return Color(1.0, 0.85, 0.2).lerp(Color(0.3, 0.95, 0.35), clampf((f - 0.5) * 2.0, 0.0, 1.0))

	func _draw() -> void:
		var f: float = get_meta("f", 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(Vector2(1, 1), Vector2((size.x - 2) * f, size.y - 2)), hp_color(f))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.5, 0.6), false, 1.0)
		var font := get_theme_default_font()
		var t: String = get_meta("text", "")
		draw_string_outline(font, Vector2(0, size.y - 4), t, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, 4, Color.BLACK)
		draw_string(font, Vector2(0, size.y - 4), t, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color.WHITE)


## Resource icons in the top bar: mineral crystal, supply crate, clock.
class ResIcon extends Control:
	var kind := ""

	func _init(k: String) -> void:
		kind = k
		custom_minimum_size = Vector2(24, 24)

	func _draw() -> void:
		var c := size / 2.0
		match kind:
			"minerals":
				var pts := PackedVector2Array([c + Vector2(0, -11), c + Vector2(7, -2), c + Vector2(4, 10), c + Vector2(-4, 10), c + Vector2(-7, -2)])
				draw_colored_polygon(pts, Color(0.35, 0.8, 1.0))
				var outline := pts.duplicate()
				outline.append(pts[0])
				draw_polyline(outline, Color(0.8, 0.95, 1.0), 1.5)
				draw_line(c + Vector2(0, -11), c + Vector2(0, 10), Color(0.7, 0.95, 1.0, 0.7), 1.0)
			"supply":
				draw_rect(Rect2(c - Vector2(9, 7), Vector2(18, 15)), Color(0.35, 0.75, 0.35))
				draw_rect(Rect2(c - Vector2(9, 7), Vector2(18, 15)), Color(0.75, 1.0, 0.7), false, 1.5)
				draw_line(c + Vector2(-9, -1), c + Vector2(9, -1), Color(0.15, 0.4, 0.15), 2.0)
			"time":
				draw_arc(c, 9.0, 0.0, TAU, 24, Color(0.8, 0.9, 1.0), 2.0)
				draw_line(c, c + Vector2(0, -6), Color(0.8, 0.9, 1.0), 2.0)
				draw_line(c, c + Vector2(5, 2), Color(0.8, 0.9, 1.0), 2.0)


## Vector icons for commands that have no 3D model.
class Glyphs:
	static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
		var out := pts.duplicate()
		out.append(pts[0])
		return out

	static func draw(ci: CanvasItem, name: String, r: Rect2, tint: Color) -> void:
		var c := r.get_center()
		var s := minf(r.size.x, r.size.y) * 0.5
		var w := Color(0.85, 0.95, 1.0) * tint
		var red := Color(1.0, 0.35, 0.3) * tint
		var cyan := Color(0.4, 0.85, 1.0) * tint
		var green := Color(0.4, 1.0, 0.5) * tint
		if name.begins_with("@age:"):  # age: a golden pillar with the roman numeral of the age
			var roman: String = Defs.AGES[int(name.get_slice(":", 1))].short
			var gold := Color(1.0, 0.82, 0.3) * tint
			ci.draw_rect(Rect2(c + Vector2(-s * 0.7, s * 0.55), Vector2(s * 1.4, s * 0.2)), gold)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.6, -s * 0.75), Vector2(s * 1.2, s * 0.18)), gold)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.7, -s * 0.75), c + Vector2(0, -s * 1.0),
				c + Vector2(s * 0.7, -s * 0.75)]), gold)
			var font := ThemeDB.fallback_font
			ci.draw_string(font, Vector2(r.position.x, c.y + s * 0.3), roman, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(s * 0.9),
				Color(1.0, 0.95, 0.8) * tint)
			return
		if name.begins_with("@missile:"):  # missile types: rocket with a coloured warhead and a type mark
			var mk := name.get_slice(":", 1)
			var col: Color = {"tactical": Color(1.0, 0.3, 0.25), "cluster": Color(1.0, 0.8, 0.25),
				"napalm": Color(1.0, 0.5, 0.1), "heavy": Color(0.45, 0.85, 1.0)}.get(mk, Color.WHITE) * tint
			var k := 1.15 if mk == "heavy" else 0.9
			var body := PackedVector2Array([c + Vector2(0, -s * 0.85) * k, c + Vector2(s * 0.2, -s * 0.45) * k,
				c + Vector2(s * 0.2, s * 0.5) * k, c + Vector2(-s * 0.2, s * 0.5) * k, c + Vector2(-s * 0.2, -s * 0.45) * k])
			ci.draw_colored_polygon(body, w)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.85) * k, c + Vector2(s * 0.2, -s * 0.45) * k,
				c + Vector2(-s * 0.2, -s * 0.45) * k]), col)
			match mk:
				"cluster":
					for i in 4:
						ci.draw_circle(c + Vector2(s * 0.55, -s * 0.5 + i * s * 0.3), s * 0.09, col)
				"napalm":
					ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.35, s * 0.7), c + Vector2(s * 0.75, s * 0.7),
						c + Vector2(s * 0.55, s * 0.05)]), col)
				"heavy":
					ci.draw_rect(Rect2(c + Vector2(-s * 0.2, s * 0.05) * k, Vector2(s * 0.4, s * 0.12) * k), col)
			return
		match name:
			"@attack":  # crossed swords
				ci.draw_line(c + Vector2(-s * 0.75, s * 0.75), c + Vector2(s * 0.7, -s * 0.7), w, 4.0)
				ci.draw_line(c + Vector2(s * 0.75, s * 0.75), c + Vector2(-s * 0.7, -s * 0.7), w, 4.0)
				ci.draw_line(c + Vector2(-s * 0.75, s * 0.35), c + Vector2(-s * 0.35, s * 0.75), red, 4.0)
				ci.draw_line(c + Vector2(s * 0.75, s * 0.35), c + Vector2(s * 0.35, s * 0.75), red, 4.0)
			"@stop":  # octagon sign
				var pts := PackedVector2Array()
				for i in 8:
					pts.append(c + Vector2.from_angle(PI / 8.0 + i * TAU / 8.0) * s * 0.8)
				ci.draw_colored_polygon(pts, red)
				ci.draw_rect(Rect2(c - Vector2(s * 0.45, s * 0.12), Vector2(s * 0.9, s * 0.24)), w)
			"@hold":  # shield
				var pts := PackedVector2Array([c + Vector2(-s * 0.65, -s * 0.7), c + Vector2(s * 0.65, -s * 0.7),
					c + Vector2(s * 0.6, s * 0.1), c + Vector2(0, s * 0.8), c + Vector2(-s * 0.6, s * 0.1)])
				ci.draw_colored_polygon(pts, cyan * Color(1, 1, 1, 0.6))
				ci.draw_polyline(_closed(pts), w, 2.5)
			"@cancel":
				ci.draw_line(c + Vector2(-s * 0.6, -s * 0.6), c + Vector2(s * 0.6, s * 0.6), red, 6.0)
				ci.draw_line(c + Vector2(s * 0.6, -s * 0.6), c + Vector2(-s * 0.6, s * 0.6), red, 6.0)
			"@missile", "@launch":  # rocket pointing up
				var body := PackedVector2Array([c + Vector2(0, -s * 0.85), c + Vector2(s * 0.22, -s * 0.45), c + Vector2(s * 0.22, s * 0.45),
					c + Vector2(-s * 0.22, s * 0.45), c + Vector2(-s * 0.22, -s * 0.45)])
				ci.draw_colored_polygon(body, w)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.85), c + Vector2(s * 0.22, -s * 0.45),
					c + Vector2(-s * 0.22, -s * 0.45)]), red)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.22, s * 0.1), c + Vector2(-s * 0.5, s * 0.55),
					c + Vector2(-s * 0.22, s * 0.45)]), cyan)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.22, s * 0.1), c + Vector2(s * 0.5, s * 0.55),
					c + Vector2(s * 0.22, s * 0.45)]), cyan)
				if name == "@launch":
					ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.18, s * 0.5), c + Vector2(s * 0.18, s * 0.5),
						c + Vector2(0, s * 0.95)]), Color(1.0, 0.6, 0.15) * tint)
					ci.draw_arc(c, s * 0.95, 0.0, TAU, 32, red, 2.0)
			"@repair":  # wrench
				ci.draw_line(c + Vector2(-s * 0.6, s * 0.6), c + Vector2(s * 0.25, -s * 0.25), w, 6.0)
				ci.draw_arc(c + Vector2(s * 0.38, -s * 0.38), s * 0.3, PI * 0.75, PI * 2.25, 16, w, 5.0)
				ci.draw_circle(c + Vector2(-s * 0.6, s * 0.6), s * 0.12, green)
			"@weapons":  # bullet with a plus
				ci.draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.2), Vector2(s * 0.4, s * 0.8)), Color(0.9, 0.7, 0.3) * tint)
				ci.draw_circle(c + Vector2(0, -s * 0.2), s * 0.2, Color(0.9, 0.7, 0.3) * tint)
				ci.draw_line(c + Vector2(s * 0.45, -s * 0.75), c + Vector2(s * 0.45, -s * 0.25), green, 3.0)
				ci.draw_line(c + Vector2(s * 0.2, -s * 0.5), c + Vector2(s * 0.7, -s * 0.5), green, 3.0)
			"@armor":  # plated shield with a plus
				var pts := PackedVector2Array([c + Vector2(-s * 0.6, -s * 0.6), c + Vector2(s * 0.6, -s * 0.6),
					c + Vector2(s * 0.55, s * 0.15), c + Vector2(0, s * 0.8), c + Vector2(-s * 0.55, s * 0.15)])
				ci.draw_colored_polygon(pts, Color(0.55, 0.6, 0.68) * tint)
				ci.draw_polyline(_closed(pts), w, 2.0)
				ci.draw_line(c + Vector2(0, -s * 0.35), c + Vector2(0, s * 0.35), green, 3.0)
				ci.draw_line(c + Vector2(-s * 0.3, 0), c + Vector2(s * 0.3, 0), green, 3.0)
