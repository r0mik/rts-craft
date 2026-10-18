extends CanvasLayer
## On-screen interface in the style of StarCraft: resources top-right, and a bottom console with
## the minimap (left), the selection panel with a live 3D portrait or unit wireframes (centre) and
## a 5x3 command card of square icon buttons with hotkeys and costs (right).
## Unit and building icons are rendered from the 3D models at startup (skipped when headless).

const I18N = preload("res://scripts/i18n.gd")
const Defs = preload("res://scripts/defs.gd")
const MinimapScript = preload("res://scripts/minimap.gd")
const OverlayScript = preload("res://scripts/overlay.gd")
const Settings = preload("res://scripts/settings.gd")
const UiStyle = preload("res://scripts/ui_style.gd")

const FRAME := Color(0.3, 0.62, 0.85)
const FRAME_DIM := Color(0.16, 0.32, 0.45)
const BG := Color(0.035, 0.05, 0.075, 0.97)
const TEXT := Color(0.82, 0.92, 1.0)
const ACCENT := Color(0.45, 0.85, 1.0)
const GOLD := Color(1.0, 0.85, 0.35)
const CONSOLE_H := 214.0
const HOLO_SHADER := preload("res://scripts/holo.gdshader")
const CARD_COLS := 5
const CARD_ROWS := 3
const BTN := 62.0

var game
var res_minerals: Label
var res_supply: Label
var res_time: Label
var res_age: Label
var fps_label: Label
var help_label: Label
var _lang_shown := ""
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
var touch_bar: VBoxContainer     # on-screen buttons for touch screens, shown in touch mode
var _touch_cancel: Button
var _touch_add: Button
var _touch_restart: Button
var _help_touch := false


func setup(g) -> void:
	game = g
	var overlay = OverlayScript.new()  # first child, so panels draw on top of it
	overlay.game = game
	add_child(overlay)
	_build_top()
	_build_console()
	_build_touch_bar()
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
	fps_label = _label("", 14, Color(0.6, 1.0, 0.6))
	fps_label.position = Vector2(12, 46)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fps_label)
	_render_icons()


# --- Layout -------------------------------------------------------------------

## Metal plate with cut corners (scripts/ui_style.gd); radius sets how big the cut corners are.
static func panel_style(bg: Color, border: Color, width := 2, radius := 4) -> StyleBox:
	return UiStyle.plate(bg, border, width, clampi(radius * 2, 4, 12))


func _label(text: String, size: int, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	return l


func _build_top() -> void:
	help_label = _label("", 13, Color(0.8, 0.9, 1.0, 0.55))
	var help := help_label
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
	res_age.tooltip_text = I18N.t("Текущая эпоха")
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
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.025, 0.035, 0.05, 0.98)
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 8
	st.content_margin_bottom = 6
	console.add_theme_stylebox_override("panel", st)
	console.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(console)
	var trim := ConsoleTrim.new()  # StarCraft-like raised armour wings along the top of the console
	trim.anchor_top = 1.0
	trim.anchor_bottom = 1.0
	trim.anchor_right = 1.0
	trim.offset_top = -CONSOLE_H - 26.0
	trim.offset_bottom = -CONSOLE_H + 8.0
	trim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(trim)
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


## Esc in game: pauses the battle and shows Continue / Main menu / Quit.
func open_pause_menu() -> void:
	if get_node_or_null("PauseMenu") != null:
		return
	var pm := PauseMenu.new()
	pm.name = "PauseMenu"
	pm.hud = self
	add_child(pm)
	get_tree().paused = true


func show_message(text: String) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_time = 3.0


func show_big(text: String, color: Color) -> void:
	big_label.text = text + _game_over_hint()
	big_label.add_theme_color_override("font_color", color)


func _game_over_hint() -> String:
	if game.touch_mode:
		return I18N.t("\nКнопки справа: «Заново» или «Меню»")
	return I18N.t("\n[R] — заново    [Esc] — меню")


## A column of big buttons at the right edge for what the keyboard does: menu, cancel, army,
## base, add to selection (Shift) and control groups (tap: select, hold: assign).
func _build_touch_bar() -> void:
	touch_bar = VBoxContainer.new()
	touch_bar.anchor_left = 1.0
	touch_bar.anchor_right = 1.0
	touch_bar.offset_left = -132.0
	touch_bar.offset_right = -8.0
	touch_bar.offset_top = 56.0
	touch_bar.add_theme_constant_override("separation", 6)
	touch_bar.visible = false
	add_child(touch_bar)
	touch_bar.add_child(_touch_button(I18N.t("Меню"), func(): game.cancel_or_pause()))
	_touch_cancel = _touch_button(I18N.t("Отмена"), func(): game.cancel_or_pause())
	touch_bar.add_child(_touch_cancel)
	_touch_restart = _touch_button(I18N.t("Заново"), func(): get_tree().reload_current_scene())
	touch_bar.add_child(_touch_restart)
	touch_bar.add_child(_touch_button(I18N.t("Армия"), func(): game.select_army()))
	touch_bar.add_child(_touch_button(I18N.t("База"), func(): game.view.focus = game.start_positions[game.PLAYER]))
	_touch_add = _touch_button(I18N.t("+ Выбор"), func(): game.touch_add = _touch_add.button_pressed)
	_touch_add.toggle_mode = true
	_touch_add.tooltip_text = I18N.t("Касания и рамка добавляют к выделению")
	touch_bar.add_child(_touch_add)
	var groups := GridContainer.new()
	groups.columns = 2
	groups.add_theme_constant_override("h_separation", 6)
	groups.add_theme_constant_override("v_separation", 6)
	touch_bar.add_child(groups)
	for n in range(1, 5):
		var b := _touch_button(str(n), Callable())
		b.custom_minimum_size = Vector2(59, 52)
		var down_at := [0.0]
		b.button_down.connect(func(): down_at[0] = Time.get_ticks_msec() / 1000.0)
		b.button_up.connect(func(): game.control_group(n, Time.get_ticks_msec() / 1000.0 - down_at[0] >= 0.5))
		groups.add_child(b)
	var hint := _label(I18N.t("Удержать — назначить"), 12, Color(0.8, 0.9, 1.0, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_bar.add_child(hint)


func _touch_button(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(124, 52)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_stylebox_override("normal", panel_style(Color(0.05, 0.09, 0.12, 0.92), FRAME_DIM, 2, 4))
	b.add_theme_stylebox_override("hover", panel_style(Color(0.05, 0.09, 0.12, 0.92), FRAME_DIM, 2, 4))
	b.add_theme_stylebox_override("pressed", panel_style(Color(0.14, 0.24, 0.3, 0.95), GOLD, 2, 4))
	if fn.is_valid():
		b.pressed.connect(fn)
	return b


func _update_touch_bar() -> void:
	touch_bar.visible = game.touch_mode
	if not game.touch_mode:
		return
	_touch_cancel.visible = game.placing != "" or game.attack_mode or game.missile_mode
	_touch_restart.visible = game.game_over
	if _touch_add.button_pressed != game.touch_add:
		_touch_add.set_pressed_no_signal(game.touch_add)


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
	res_age.text = I18N.t("Эпоха %s") % age.short
	res_age.tooltip_text = I18N.t(age.name)
	msg_time -= delta
	msg_label.modulate.a = clampf(msg_time, 0.0, 1.0)
	if _lang_shown != Settings.lang or _help_touch != game.touch_mode:  # (re)write the help line
		_lang_shown = Settings.lang
		_help_touch = game.touch_mode
		if game.touch_mode:
			help_label.text = I18N.t("Касание — выбор или приказ   Удержание — приказ   Рамка — провести пальцем\n") + \
				I18N.t("Два пальца — сдвиг и зум камеры   Двойное касание — все такие юниты на экране")
		else:
			help_label.text = I18N.t("ЛКМ — выбор   ПКМ — приказ   WASD — камера   G — атака   Ctrl+1..9 — группы   Space — база\n") + \
				I18N.t("Отряды: выделите командира с солдатами и нажмите Z — до 6 пехотинцев, 4 машин или 4 самолётов")
		if game.game_over and big_label.text != "":
			big_label.text = big_label.text.get_slice("\n", 0) + _game_over_hint()
	_update_touch_bar()
	fps_label.visible = Settings.show_fps
	if Settings.show_fps:
		fps_label.text = "FPS %d" % Engine.get_frames_per_second()
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
		var hint := _label(I18N.t("Ничего не выбрано.\n\nВыдели рабочих и строй здания,\nвыдели Штаб или Казарму и нанимай юнитов."), 15,
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
	var holo := ColorRect.new()  # hologram look over the portrait: scanlines, sweep and vignette
	holo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hm := ShaderMaterial.new()
	hm.shader = HOLO_SHADER
	holo.material = hm
	pf.add_child(holo)
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
	_name_label.text = "%s%s" % [I18N.t(e.stats.name), "" if mine else I18N.t("  — противник")]
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


## Squad hints for a group selection: how many of the selected units each selected commander can take.
func combo_hint(sel: Array) -> String:
	var lines := []
	var mine := sel.filter(func(u): return game.valid(u) and u.team == 0 and u.is_in_group("units"))
	for c in mine.filter(func(u): return u.stats.has("commands")):
		var rule: Dictionary = Defs.SQUADS[c.stats.commands]
		var free := mine.filter(func(u): return game.can_join(c, u)).size()
		var room: int = rule.max - c.squad.size()
		if free > 0 and room > 0:
			lines.append(I18N.t("[color=#7dff8a]%s: можно взять в отряд %d — нажмите Z (отряд %d/%d)[/color]") % [
				I18N.t(c.stats.name), mini(free, room), c.squad.size(), rule.max])
		else:
			lines.append(I18N.t("[color=#9cc8e8]%s: отряд %d/%d. Выделите его вместе с юнитами рода «%s» и нажмите Z[/color]") % [
				I18N.t(c.stats.name), c.squad.size(), rule.max, I18N.t(Defs.CLASS_NAMES[c.stats.commands])])
	return "\n".join(lines)


func _stats_text(e) -> String:
	var lines := []
	var up: Dictionary = game.upgrades[maxi(e.team, 0)]
	if e.is_in_group("units"):
		if e.kind == "mechanic":
			lines.append(I18N.t("Ремонт %d HP/с, радиус %d: техника, авиация, здания") % [e.stats.heal_rate, e.stats.range])
		elif e.stats.get("healer", false):
			lines.append(I18N.t("Лечение %d HP/с, радиус %d: пехота") % [e.stats.heal_rate, e.stats.range])
		elif e.stats.get("unarmed", false):
			lines.append(I18N.t("Без оружия   обзор %d") % e.stats.sight)
			if e.kind == "scout":
				lines.append(I18N.t("Маяк: ") + (I18N.t("готов (F)") if e.ability_cd <= 0.0 else I18N.t("через %d с") % ceili(e.ability_cd)))
			if e.kind == "beacon":
				lines.append(I18N.t("Погаснет через %d с") % ceili(e.life_left))
		else:
			var dmg_up: float = game.upgrade_bonus(e.stats.damage, up.weapons) if up.weapons > 0 else 0.0
			var arm_up: float = game.upgrade_bonus(e.stats.get("armor", 0), up.armor) if up.armor > 0 else 0.0
			lines.append(I18N.t("Урон %d (+%s)   Броня %d (+%s)   Дальность %d") % [e.stats.damage, str(snappedf(dmg_up, 0.1)),
				e.stats.get("armor", 0), str(snappedf(arm_up, 0.1)), e.stats.range])
			var vs: Dictionary = Defs.DAMAGE_VS.get(e.kind, {})
			if not vs.is_empty():
				var parts := []
				for c in vs:
					parts.append("%s ×%s" % [I18N.t(Defs.CLASS_NAMES[c]), str(vs[c])])
				lines.append(I18N.t("Против: ") + ", ".join(parts))
			lines.append(I18N.t("Тип: %s") % I18N.t(Defs.CLASS_NAMES[game.armor_class(e)]))
			lines.append(I18N.t("Скорость %d") % e.stats.speed)
		if e.carrying > 0:
			lines.append(I18N.t("Несёт минералы: %d") % e.carrying)
		if game.faction(e.team) == "fog":
			lines.append(I18N.t("Туман: регенерация %s HP/с") % str(Defs.FOG_REGEN))
		if e.stats.has("commands"):  # commander: squad size and bonuses
			var rule: Dictionary = Defs.SQUADS[e.stats.commands]
			lines.append(I18N.t("Отряд: %d/%d (%s). Рядом с командиром: урон +%d%%, броня +%d") % [e.squad.size(), rule.max,
				I18N.t(Defs.CLASS_NAMES[e.stats.commands]), roundi((rule.damage - 1.0) * 100.0), rule.armor] +
				(I18N.t(", лечение %s HP/с") % str(rule.regen) if rule.regen > 0.0 else ""))
		elif e.commander != null and game.valid(e.commander):
			lines.append(I18N.t("В отряде: %s — бонус %s") % [I18N.t(e.commander.stats.name),
				I18N.t("действует") if game.squad_bonus(e) else I18N.t("нет (далеко от командира)")])
	else:
		if e.constructing:
			lines.append(I18N.t("Строится: %d%%") % int(e.build_progress * 100.0))
		lines.append(I18N.t("Броня %d") % e.stats.get("armor", 0))
		if e.max_shield > 0.0:
			lines.append(I18N.t("Щит: %d / %d (восстанавливается)") % [int(e.shield), int(e.max_shield)])
		if e.kind == "cc" and e.team == 0:
			lines.append(I18N.t("Эпоха: %s") % I18N.t(Defs.AGES[game.ages[0]].name))
		if e.stats.has("damage"):
			lines.append(I18N.t("Оборона: урон %d, дальность %d") % [e.stats.damage, e.stats.range])
		if e.kind == "silo":
			lines.append(I18N.t("Ракета: ") + (I18N.t("%s — готова к пуску (L)") % I18N.t(Defs.MISSILES[e.missile_type].name) if e.missile_ready
				else I18N.t("нет (M, J, N, K — собрать)")))
		if e.stats.has("research"):
			lines.append(I18N.t("Улучшения: Оружие ур. %d, Броня ур. %d (из 3)") % [up.weapons, up.armor])
		if e.team == 0 and not e.stats.trains.is_empty() and not e.constructing:
			lines.append(I18N.t("ПКМ — точка сбора"))
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
		b.tooltip_text = I18N.t(e.stats.name)
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

## Top edge of the bottom console: armour plates raised over the minimap and the command card,
## a lower bevel in the middle, glowing cyan seams and rivets — the StarCraft console silhouette.
class ConsoleTrim extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var base := h - 8.0  # where the console body starts
		var metal := Color(0.08, 0.1, 0.13)
		var metal_hi := Color(0.16, 0.2, 0.25)
		var glow := Color(0.35, 0.8, 1.0)
		var left_w := 300.0
		var right_w := 380.0
		# full-width strip along the console top
		draw_rect(Rect2(0, base - 4.0, w, 12.0), metal)
		# raised wing over the minimap (left) and the command card (right)
		var lw := PackedVector2Array([Vector2(0, base), Vector2(0, 2), Vector2(left_w - 30.0, 2), Vector2(left_w, base)])
		var rw := PackedVector2Array([Vector2(w, base), Vector2(w, 2), Vector2(w - right_w + 30.0, 2), Vector2(w - right_w, base)])
		for poly in [lw, rw]:
			draw_colored_polygon(poly, metal)
			# lighter top bevel
			draw_polyline(PackedVector2Array([poly[1], poly[2]]), metal_hi, 3.0)
			draw_line(poly[2], poly[3], glow * Color(1, 1, 1, 0.9), 2.0)
		# glowing seam along the console edge between the wings
		draw_line(Vector2(left_w, base - 1.0), Vector2(w - right_w, base - 1.0), glow * Color(1, 1, 1, 0.85), 2.0)
		draw_line(Vector2(left_w, base + 2.0), Vector2(w - right_w, base + 2.0), glow * Color(1, 1, 1, 0.2), 4.0)
		# hazard-style notches and rivets on the wings
		for i in 6:
			var x := 18.0 + i * 40.0
			draw_circle(Vector2(x, 9.0), 2.2, Color(0.45, 0.55, 0.62))
			draw_circle(Vector2(w - x, 9.0), 2.2, Color(0.45, 0.55, 0.62))
		for i in 3:
			var x0 := left_w - 70.0 + i * 12.0
			draw_colored_polygon(PackedVector2Array([Vector2(x0, base - 3.0), Vector2(x0 + 6.0, base - 3.0),
				Vector2(x0 + 12.0, 6.0), Vector2(x0 + 6.0, 6.0)]), Color(0.9, 0.7, 0.2, 0.55))


## Pause overlay. Runs while the tree is paused; Esc or "Продолжить" resumes.
class PauseMenu extends Control:
	var hud

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.55)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", hud.panel_style(Color(0.03, 0.05, 0.08, 0.97), FRAME, 2, 6))
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		panel.add_child(box)
		var title: Label = hud._label(I18N.t("ПАУЗА"), 32, ACCENT)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(title)
		for item in [[I18N.t("Продолжить"), _resume], [I18N.t("Сохранить игру"), _save], [I18N.t("Загрузить игру"), _load],
				[I18N.t("Настройки"), _settings], [I18N.t("Главное меню"), _to_menu], [I18N.t("Выйти из игры"), _quit]]:
			var b := Button.new()
			b.text = item[0]
			b.custom_minimum_size = Vector2(300, 52)
			b.add_theme_font_size_override("font_size", 20)
			b.add_theme_stylebox_override("normal", hud.panel_style(Color(0.05, 0.09, 0.12), FRAME_DIM, 2, 4))
			b.add_theme_stylebox_override("hover", hud.panel_style(Color(0.08, 0.15, 0.2), ACCENT, 2, 4))
			b.add_theme_stylebox_override("pressed", hud.panel_style(Color(0.14, 0.24, 0.3), Color.WHITE, 2, 4))
			b.pressed.connect(item[1])
			box.add_child(b)

	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			var sm: Node = get_node_or_null("SlotMenu")
			if sm == null:
				sm = get_node_or_null("SettingsMenu")
			if sm != null:
				sm.queue_free()
			else:
				_resume()

	func _settings() -> void:
		add_child(SettingsMenu.make(hud, hud.game))

	func _save() -> void:
		add_child(SlotMenu.make(hud, hud.game.get_script(), "save", hud.game))

	func _load() -> void:
		add_child(SlotMenu.make(hud, hud.game.get_script(), "load", null))

	func _resume() -> void:
		get_tree().paused = false
		queue_free()

	func _to_menu() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://menu.tscn")

	func _quit() -> void:
		get_tree().quit()


## Settings window (main menu and pause menu). Every change is applied at once and saved.
class SettingsMenu extends Control:
	var style_src
	var game  # running game or the menu's demo battle (for graphics quality and game speed)
	var _speed_label: Label

	static func make(style_src_, game_) -> SettingsMenu:
		var m := SettingsMenu.new()
		m.name = "SettingsMenu"
		m.style_src = style_src_
		m.game = game_
		return m

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.5)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", style_src.panel_style(Color(0.03, 0.05, 0.08, 0.98), FRAME, 2, 6))
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		panel.add_child(box)
		box.add_child(_title(I18N.t("Настройки")))
		var langs := ["ru", "en"]
		box.add_child(_choice("Язык / Language", langs.map(func(l): return I18N.NAMES[l]), langs.find(Settings.lang),
			func(i): _set_language(langs[i])))
		box.add_child(_section(I18N.t("Экран и графика")))
		box.add_child(_choice(I18N.t("Режим экрана"), Settings.WINDOW_MODES.map(func(m): return I18N.t(m)), Settings.window_mode,
			func(i): Settings.window_mode = i))
		box.add_child(_choice(I18N.t("Разрешение (в окне)"), Settings.RESOLUTIONS.map(func(r): return "%d × %d" % [r.x, r.y]),
			Settings.resolution, func(i): Settings.resolution = i))
		box.add_child(_toggle(I18N.t("Вертикальная синхронизация"), Settings.vsync, func(v): Settings.vsync = v))
		box.add_child(_choice(I18N.t("Качество графики"), Settings.QUALITY_NAMES.map(func(q): return I18N.t(q)), Settings.quality, func(i): Settings.quality = i))
		box.add_child(_toggle(I18N.t("Показывать FPS"), Settings.show_fps, func(v): Settings.show_fps = v))
		box.add_child(_section(I18N.t("Камера")))
		box.add_child(_slider(I18N.t("Скорость камеры"), Settings.camera_speed, 0.4, 2.5, func(v): Settings.camera_speed = v))
		box.add_child(_toggle(I18N.t("Прокрутка у края экрана"), Settings.edge_scroll, func(v): Settings.edge_scroll = v))
		box.add_child(_section(I18N.t("Игра")))
		var speeds := Settings.SPEEDS.map(func(s): return "×%s" % str(s))
		box.add_child(_choice(I18N.t("Скорость игры"), speeds, maxi(0, Settings.SPEEDS.find(Settings.game_speed)),
			func(i): Settings.game_speed = Settings.SPEEDS[i]))
		box.add_child(_toggle(I18N.t("Туман войны (со следующей игры)"), Settings.fog, func(v): Settings.fog = v))
		box.add_child(_toggle(I18N.t("Полоски HP над всеми юнитами"), Settings.always_hp, func(v): Settings.always_hp = v))
		var back := Button.new()
		back.text = I18N.t("Готово")
		back.custom_minimum_size = Vector2(0, 46)
		back.focus_mode = Control.FOCUS_NONE
		back.add_theme_font_size_override("font_size", 18)
		back.add_theme_stylebox_override("normal", style_src.panel_style(Color(0.05, 0.09, 0.12), FRAME_DIM, 2, 4))
		back.add_theme_stylebox_override("hover", style_src.panel_style(Color(0.08, 0.15, 0.2), ACCENT, 2, 4))
		back.pressed.connect(queue_free)
		box.add_child(back)

	## A new language: rebuild this window (and the main menu, if we are in it) in that language.
	func _set_language(l: String) -> void:
		if l == Settings.lang:
			return
		Settings.lang = l
		Settings.save_settings()
		if game == null or game.demo:
			get_tree().reload_current_scene.call_deferred()
		else:
			var again := SettingsMenu.make(style_src, game)
			get_parent().add_child(again)
			queue_free()

	func _apply() -> void:
		Settings.save_settings()
		Settings.apply_window()
		Settings.apply_viewport(get_viewport())
		if game != null and is_instance_valid(game):
			game.view.apply_quality(Settings.quality)
			if not game.demo:
				Engine.time_scale = Settings.game_speed

	func _title(t: String) -> Label:
		var l := Label.new()
		l.text = t
		l.add_theme_font_size_override("font_size", 28)
		l.add_theme_color_override("font_color", ACCENT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return l

	func _section(t: String) -> Label:
		var l := Label.new()
		l.text = t
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", GOLD)
		return l

	func _row(t: String) -> HBoxContainer:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(560, 36)
		var l := Label.new()
		l.text = t
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", TEXT)
		row.add_child(l)
		return row

	func _toggle(t: String, value: bool, setter: Callable) -> Control:
		var row := _row(t)
		var c := CheckButton.new()
		c.button_pressed = value
		c.focus_mode = Control.FOCUS_NONE
		c.toggled.connect(func(v):
			setter.call(v)
			_apply())
		row.add_child(c)
		return row

	func _choice(t: String, names: Array, index: int, setter: Callable) -> Control:
		var row := _row(t)
		var o := OptionButton.new()
		for n in names:
			o.add_item(n)
		o.selected = index
		o.custom_minimum_size = Vector2(170, 0)
		o.focus_mode = Control.FOCUS_NONE
		o.item_selected.connect(func(i):
			setter.call(i)
			_apply())
		row.add_child(o)
		return row

	func _slider(t: String, value: float, lo: float, hi: float, setter: Callable) -> Control:
		var row := _row(t)
		var s := HSlider.new()
		s.min_value = lo
		s.max_value = hi
		s.step = 0.1
		s.value = value
		s.custom_minimum_size = Vector2(170, 0)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.focus_mode = Control.FOCUS_NONE
		var v := Label.new()
		v.text = "×%.1f" % value
		v.custom_minimum_size = Vector2(46, 0)
		v.add_theme_color_override("font_color", TEXT)
		s.value_changed.connect(func(x):
			v.text = "×%.1f" % x
			setter.call(x)
			_apply())
		row.add_child(s)
		row.add_child(v)
		return row


## Save / load slot picker, used by the pause menu and the main menu.
class SlotMenu extends Control:
	var main_script  # scripts/main.gd (static save helpers)
	var mode := "load"
	var game          # running game, for saving
	var style_src     # anything with panel_style()

	static func make(style_src_, main_script_, mode_: String, game_) -> SlotMenu:
		var m := SlotMenu.new()
		m.name = "SlotMenu"
		m.style_src = style_src_
		m.main_script = main_script_
		m.mode = mode_
		m.game = game_
		return m

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.5)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", style_src.panel_style(Color(0.03, 0.05, 0.08, 0.98), FRAME, 2, 6))
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		panel.add_child(box)
		var title := Label.new()
		title.text = I18N.t("Сохранить игру") if mode == "save" else I18N.t("Загрузить игру")
		title.add_theme_font_size_override("font_size", 28)
		title.add_theme_color_override("font_color", ACCENT)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(title)
		for slot in main_script.SAVE_SLOTS:
			if mode == "save" and slot == "quick":
				continue  # quick save is F5
			var b := _button(main_script.slot_summary(slot))
			b.disabled = mode == "load" and main_script.read_slot(slot).is_empty()
			b.pressed.connect(func(): _pick(slot))
			box.add_child(b)
		var back := _button(I18N.t("Назад"))
		back.pressed.connect(queue_free)
		box.add_child(back)

	func _button(text: String) -> Button:
		var b := Button.new()
		b.text = text
		b.custom_minimum_size = Vector2(640, 48)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_stylebox_override("normal", style_src.panel_style(Color(0.05, 0.09, 0.12), FRAME_DIM, 2, 4))
		b.add_theme_stylebox_override("hover", style_src.panel_style(Color(0.08, 0.15, 0.2), ACCENT, 2, 4))
		b.add_theme_stylebox_override("pressed", style_src.panel_style(Color(0.14, 0.24, 0.3), Color.WHITE, 2, 4))
		b.add_theme_stylebox_override("disabled", style_src.panel_style(Color(0.03, 0.04, 0.05), Color(0.1, 0.14, 0.18), 1, 4))
		return b

	func _pick(slot: String) -> void:
		if mode == "save":
			game.save_game(slot)
			queue_free()
		else:
			main_script.load_slot(get_tree(), slot)


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
			draw_string(get_theme_default_font(), Vector2(0, size.y * 0.55), String(I18N.t(entity.stats.name)).substr(0, 3),
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
		if name == "@squad":  # squad: a gold chevron over three soldiers
			var gold := Color(1.0, 0.82, 0.3) * tint
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.5, -s * 0.35), c + Vector2(0, -s * 0.75),
				c + Vector2(s * 0.5, -s * 0.35)]), gold, 4.0)
			for i in 3:
				var p := c + Vector2((i - 1) * s * 0.5, s * 0.25)
				ci.draw_circle(p + Vector2(0, -s * 0.12), s * 0.13, w)
				ci.draw_rect(Rect2(p + Vector2(-s * 0.13, 0), Vector2(s * 0.26, s * 0.4)), w)
			return
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
