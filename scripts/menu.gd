extends Node
## Main menu: a live AI-vs-AI battle flies by in the background (main.gd in demo mode) behind
## the title, difficulty choice, "how to play" and quit.

const MainScene = preload("res://main.tscn")
const MainScript = preload("res://scripts/main.gd")
const HUD = preload("res://scripts/hud.gd")

const DIFFICULTIES := [
	["easy", "Лёгкий", "Противник только обороняет базу: войсками не нападает и не строит Титана.\nЕго ракетная шахта всё же бьёт по тем, кто подойдёт близко."],
	["normal", "Нормальный", "Противник развивается в полную силу: строит технику, авиацию и Титана\nи атакует растущими волнами."],
]

var ui: CanvasLayer
var diff_index := 0
var diff_button: Button
var diff_label: Label
var help_panel: Control


func _ready() -> void:
	if "--autotest" in OS.get_cmdline_user_args():  # the autotest skips the menu
		get_tree().change_scene_to_file.call_deferred("res://main.tscn")
		return
	diff_index = 0
	for i in DIFFICULTIES.size():
		if DIFFICULTIES[i][0] == MainScript.difficulty:
			diff_index = i
	var battle = MainScene.instantiate()
	battle.demo = true
	add_child(battle)
	_build_ui()


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	# darken the left side so the menu reads over the battle
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.01, 0.03, 0.92))
	g.set_color(1, Color(0.0, 0.01, 0.03, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.15, 0)
	gt.fill_to = Vector2(0.75, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 110)
	root.add_theme_constant_override("margin_top", 90)
	root.add_theme_constant_override("margin_bottom", 60)
	ui.add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	root.add_child(col)
	var title := _label("MINI CRAFT", 88, HUD.ACCENT)
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.1, 0.2))
	col.add_child(title)
	col.add_child(_label("стратегия в реальном времени в духе StarCraft", 22, Color(0.75, 0.88, 1.0, 0.85)))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	col.add_child(gap)
	col.add_child(_button("Новая игра", _new_game))
	diff_button = _button("", _next_difficulty)
	col.add_child(diff_button)
	diff_label = _label("", 15, Color(0.75, 0.85, 0.95, 0.8))
	diff_label.custom_minimum_size = Vector2(560, 0)
	col.add_child(diff_label)
	col.add_child(_button("Как играть", _show_help))
	col.add_child(_button("Выход", func(): get_tree().quit()))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	col.add_child(_label("Enter — начать игру   ·   Godot 4   ·   github.com/r0mik/rts-craft", 14, Color(0.7, 0.8, 0.9, 0.5)))
	_update_difficulty()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _button(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 58)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", HUD.TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _style(Color(0.04, 0.08, 0.12, 0.85), HUD.FRAME_DIM))
	b.add_theme_stylebox_override("hover", _style(Color(0.07, 0.16, 0.24, 0.95), HUD.ACCENT))
	b.add_theme_stylebox_override("pressed", _style(Color(0.12, 0.25, 0.34, 1.0), Color.WHITE))
	b.pressed.connect(fn)
	return b


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = HUD.panel_style(bg, border, 2, 4)
	s.border_width_left = 5  # StarCraft-like accent bar on the left edge
	s.content_margin_left = 22
	return s


func _update_difficulty() -> void:
	var d: Array = DIFFICULTIES[diff_index]
	diff_button.text = "Сложность: %s  ▸" % d[1]
	diff_label.text = d[2]
	MainScript.difficulty = d[0]


func _next_difficulty() -> void:
	diff_index = (diff_index + 1) % DIFFICULTIES.size()
	_update_difficulty()


func _new_game() -> void:
	MainScript.difficulty = DIFFICULTIES[diff_index][0]
	get_tree().change_scene_to_file("res://main.tscn")


func _show_help() -> void:
	if help_panel != null:
		return
	var dim := ColorRect.new()  # dims the menu behind the help window
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	help_panel = dim
	ui.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HUD.panel_style(Color(0.03, 0.05, 0.08, 0.97), HUD.FRAME, 2, 6))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	dim.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_label("Как играть", 32, HUD.ACCENT))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.custom_minimum_size = Vector2(980, 540)
	text.add_theme_font_size_override("normal_font_size", 17)
	text.add_theme_font_size_override("bold_font_size", 17)
	text.text = """[b]Цель:[/b] добывайте минералы, стройте армию и уничтожьте все здания красного противника.

[b]Начало:[/b] рабочие сами добывают минералы. Выделите рабочего и постройте Supply Depot ([b]V[/b]) и Barracks ([b]B[/b]), затем нанимайте пехоту ([b]Q[/b]) и медиков ([b]E[/b]). Дальше — Factory ([b]F[/b]) с танками и Starport ([b]P[/b]) с авиацией.

[b]Управление:[/b] ЛКМ / рамка — выбор, ПКМ — идти, атаковать, добывать. [b]G[/b] + клик — атака с продвижением, [b]X[/b] — стоп, [b]H[/b] — держать позицию, [b]Ctrl+1..9[/b] — группы. Камера — [b]WASD[/b], колесо, [b]Space[/b] — к базе. Все команды есть на кнопках внизу справа, подсказки — при наведении.

[b]Советы:[/b]
• Пехота слабо бьёт по технике и зданиям (броня), танки — наоборот. Авиацию сбивают только ПВО, турели и истребители.
• Объединяйте войска: 5 пехотинцев + 2 медика → батальон ([b]Z[/b]), 4 танка → супертанк ([b]C[/b]), 3 истребителя → фантом ([b]V[/b]).
• Командный центр, [b]E[/b] — новая эпоха: здания вдвое прочнее, потом появляются щиты.
• Разведчик ([b]R[/b] в командном центре) и его маяки ([b]F[/b]) рассеивают туман войны.
• Ракетная шахта ([b]M[/b]) бьёт далеко, но взрыв задевает и своих.

[b]Esc[/b] в игре — пауза и выход в меню."""
	box.add_child(text)
	var back := _button("Назад", func():
		help_panel.queue_free()
		help_panel = null)
	box.add_child(back)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_new_game()
	elif event.keycode == KEY_ESCAPE and help_panel != null:
		help_panel.queue_free()
		help_panel = null
