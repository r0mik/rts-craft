extends RefCounted
## StarCraft-style interface plates: dark brushed metal with chamfered (cut) corners, a bevelled
## frame, a thin inner glow line and bright corner brackets. Textures are generated once per
## colour / size combination and used as 9-slice StyleBoxTextures by every panel and button.

const SIZE := 48

static var _cache := {}


## A plate style. width = frame thickness, chamfer = size of the cut corners,
## left_bar = an extra thick accent bar on the left edge (main menu buttons).
static func plate(bg: Color, border: Color, width := 2, chamfer := 7, left_bar := 0) -> StyleBoxTexture:
	var key := "%s|%s|%d|%d|%d" % [bg.to_html(), border.to_html(), width, chamfer, left_bar]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(_make(bg, border, width, chamfer, left_bar))
	var s := StyleBoxTexture.new()
	s.texture = _cache[key]
	var m := float(chamfer + width + 3)
	s.texture_margin_left = maxf(m, left_bar + 4.0)
	s.texture_margin_right = m
	s.texture_margin_top = m
	s.texture_margin_bottom = m
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT  # keep the metal grain fine on big panels
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.content_margin_left = 6.0 + left_bar
	s.content_margin_right = 6.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s


static func _make(bg: Color, border: Color, width: int, c: int, left_bar: int) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var w := SIZE - 1
	var light := border.lightened(0.35)
	var dark := border.darkened(0.35)
	for y in SIZE:
		for x in SIZE:
			# distance to the plate outline, with the four corners cut at 45 degrees
			var d := minf(minf(x, y), minf(w - x, w - y))
			var dg := minf(minf(x + y, (w - x) + y), minf(x + (w - y), (w - x) + (w - y)))
			var diag := (dg - c) / sqrt(2.0)
			if diag < 0.0:
				continue  # cut-off corner: transparent
			d = minf(d, diag)
			var col: Color
			if d < width or x < left_bar:
				# bevelled frame: lit on the top-left, shaded on the bottom-right
				col = light if (x + y) < w * 0.9 else (dark if (x + y) > w * 1.1 else border)
				if diag < width + 0.5 and (x < c + 4 or w - x < c + 4):
					col = border.lightened(0.6)  # bright corner brackets on the cut corners
			else:
				var n := rng.randf_range(-0.035, 0.035)  # brushed-metal grain
				var sheen := 0.06 * (1.0 - float(y) / SIZE)  # slightly lighter towards the top
				col = Color(bg.r + n + sheen, bg.g + n + sheen, bg.b + n + sheen * 1.3, bg.a)
				if d < width + 2.0:
					col = col.lerp(border, 0.28)  # thin inner glow line
			img.set_pixel(x, y, col)
	return img
