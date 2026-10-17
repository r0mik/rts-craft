extends RefCounted
## Player settings: kept in static vars, saved to user://settings.cfg and applied at startup
## (menu.gd / main.gd) and whenever they change in the settings window (hud.gd, SettingsMenu).

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Низкое", "Среднее", "Высокое"]
const SPEEDS := [0.75, 1.0, 1.25, 1.5]

static var loaded := false
const WINDOW_MODES := ["Окно", "Полный экран", "Окно без рамки на весь экран"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160)]

static var window_mode := 0      # 0 window, 1 exclusive fullscreen, 2 borderless window over the whole screen
static var resolution := 2       # index in RESOLUTIONS, used in window mode
static var vsync := true
static var quality := 2          # 0 low, 1 medium, 2 high
static var show_fps := false
static var camera_speed := 1.0   # multiplier for keyboard / edge scrolling
static var edge_scroll := true
static var game_speed := 1.0
static var fog := true           # fog of war (takes effect in the next game)
static var always_hp := false    # health bars over every unit, not only damaged / selected
static var lang := "ru" if OS.get_locale_language() == "ru" else "en"  # "ru" or "en"


static func load_settings() -> void:
	if loaded:
		return
	loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	window_mode = clampi(cf.get_value("display", "window_mode", 1 if cf.get_value("display", "fullscreen", false) else 0), 0, 2)
	resolution = clampi(cf.get_value("display", "resolution", resolution), 0, RESOLUTIONS.size() - 1)
	vsync = cf.get_value("display", "vsync", vsync)
	quality = clampi(cf.get_value("display", "quality", quality), 0, 2)
	show_fps = cf.get_value("display", "show_fps", show_fps)
	camera_speed = clampf(cf.get_value("controls", "camera_speed", camera_speed), 0.4, 2.5)
	edge_scroll = cf.get_value("controls", "edge_scroll", edge_scroll)
	game_speed = cf.get_value("game", "speed", game_speed)
	fog = cf.get_value("game", "fog", fog)
	always_hp = cf.get_value("game", "always_hp", always_hp)
	lang = cf.get_value("game", "language", lang)


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("display", "window_mode", window_mode)
	cf.set_value("display", "resolution", resolution)
	cf.set_value("display", "vsync", vsync)
	cf.set_value("display", "quality", quality)
	cf.set_value("display", "show_fps", show_fps)
	cf.set_value("controls", "camera_speed", camera_speed)
	cf.set_value("controls", "edge_scroll", edge_scroll)
	cf.set_value("game", "speed", game_speed)
	cf.set_value("game", "fog", fog)
	cf.set_value("game", "always_hp", always_hp)
	cf.set_value("game", "language", lang)
	cf.save(PATH)


## Window mode, resolution (window mode only) and v-sync (not in headless runs).
static func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var modes := [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_FULLSCREEN]
	var want: int = modes[window_mode]
	var was: int = DisplayServer.window_get_mode()
	if was != want:
		DisplayServer.window_set_mode(want)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if window_mode == 0:
		_apply_size()
		if was != DisplayServer.WINDOW_MODE_WINDOWED:  # leaving fullscreen is animated on some systems: size again
			(Engine.get_main_loop() as SceneTree).create_timer(0.8, true).timeout.connect(func(): _apply_size())


static func _apply_size() -> void:
	if window_mode != 0:
		return
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size: Vector2i = RESOLUTIONS[resolution]
	size = Vector2i(mini(size.x, screen.size.x), mini(size.y, screen.size.y))
	if DisplayServer.window_get_size() != size:
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


## Anti-aliasing and render scale of the main viewport; the 3D world part is in view3d.apply_quality().
static func apply_viewport(vp: Viewport) -> void:
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	vp.scaling_3d_scale = [0.75, 1.0, 1.0][quality]
