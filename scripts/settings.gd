extends RefCounted
## Player settings: kept in static vars, saved to user://settings.cfg and applied at startup
## (menu.gd / main.gd) and whenever they change in the settings window (hud.gd, SettingsMenu).

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Низкое", "Среднее", "Высокое"]
const SPEEDS := [0.75, 1.0, 1.25, 1.5]

static var loaded := false
static var fullscreen := false
static var vsync := true
static var quality := 2          # 0 low, 1 medium, 2 high
static var show_fps := false
static var camera_speed := 1.0   # multiplier for keyboard / edge scrolling
static var edge_scroll := true
static var game_speed := 1.0
static var fog := true           # fog of war (takes effect in the next game)
static var always_hp := false    # health bars over every unit, not only damaged / selected


static func load_settings() -> void:
	if loaded:
		return
	loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	fullscreen = cf.get_value("display", "fullscreen", fullscreen)
	vsync = cf.get_value("display", "vsync", vsync)
	quality = clampi(cf.get_value("display", "quality", quality), 0, 2)
	show_fps = cf.get_value("display", "show_fps", show_fps)
	camera_speed = clampf(cf.get_value("controls", "camera_speed", camera_speed), 0.4, 2.5)
	edge_scroll = cf.get_value("controls", "edge_scroll", edge_scroll)
	game_speed = cf.get_value("game", "speed", game_speed)
	fog = cf.get_value("game", "fog", fog)
	always_hp = cf.get_value("game", "always_hp", always_hp)


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("display", "vsync", vsync)
	cf.set_value("display", "quality", quality)
	cf.set_value("display", "show_fps", show_fps)
	cf.set_value("controls", "camera_speed", camera_speed)
	cf.set_value("controls", "edge_scroll", edge_scroll)
	cf.set_value("game", "speed", game_speed)
	cf.set_value("game", "fog", fog)
	cf.set_value("game", "always_hp", always_hp)
	cf.save(PATH)


## Window mode and v-sync (not in headless runs).
static func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## Anti-aliasing and render scale of the main viewport; the 3D world part is in view3d.apply_quality().
static func apply_viewport(vp: Viewport) -> void:
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	vp.scaling_3d_scale = [0.75, 1.0, 1.0][quality]
