class_name Portraits

## Procedural 16x16 pixel portraits for staff cards (the user's Team mockup
## shows a face per applicant/crew member). Seeded from the person's name,
## so the same person always looks the same, across sessions and saves -
## nothing is stored. Role shows in the outfit: technicians wear coveralls
## and often a hard hat, engineers a white coat and often goggles or glasses.
## Drawn at runtime like UiIcons; real portrait art can replace this later.

enum Style { TECHNICIAN, ENGINEER, SPECIALIST }

const SIZE := 16

const SKIN: Array[Color] = [
	Color(0.98, 0.84, 0.70), Color(0.93, 0.74, 0.58), Color(0.84, 0.62, 0.44),
	Color(0.70, 0.48, 0.32), Color(0.55, 0.36, 0.24), Color(0.40, 0.26, 0.17),
]
const HAIR: Array[Color] = [
	Color(0.10, 0.08, 0.07), Color(0.30, 0.18, 0.10), Color(0.50, 0.32, 0.16),
	Color(0.85, 0.68, 0.35), Color(0.70, 0.30, 0.14), Color(0.62, 0.62, 0.64),
]
const HARD_HAT: Array[Color] = [Color(0.98, 0.78, 0.15), Color(0.95, 0.50, 0.12), Color(0.92, 0.92, 0.88)]
const COVERALL: Array[Color] = [Color(0.24, 0.36, 0.60), Color(0.30, 0.42, 0.30), Color(0.55, 0.32, 0.18)]
const SHIRT: Array[Color] = [Color(0.30, 0.45, 0.75), Color(0.70, 0.25, 0.25), Color(0.30, 0.55, 0.45), Color(0.45, 0.35, 0.60)]
const BG := {
	Style.TECHNICIAN: Color(0.42, 0.28, 0.16),
	Style.ENGINEER: Color(0.18, 0.28, 0.44),
	Style.SPECIALIST: Color(0.30, 0.30, 0.34),
}
const OUTLINE := Color(0.06, 0.05, 0.05)

static var _cache: Dictionary = {}


static func for_staff(tech: Technician) -> Texture2D:
	return make(tech.technician_name, Style.ENGINEER if tech.is_engineer else Style.TECHNICIAN)


static func make(person: String, style: Style) -> Texture2D:
	var key := "%s|%d" % [person, style]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(person)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(BG[style])
	_frame(img, BG[style].darkened(0.45))

	var skin: Color = SKIN[rng.randi() % SKIN.size()]
	var hair: Color = HAIR[rng.randi() % HAIR.size()]
	if style == Style.SPECIALIST:
		hair = HAIR[5] if rng.randf() < 0.6 else hair # veterans skew grey
	var hair_style := rng.randi() % 4 # 0 short, 1 long, 2 bun, 3 cropped/bald
	var beard := rng.randf() < 0.25
	var headwear := ""
	match style:
		Style.TECHNICIAN:
			headwear = "hat" if rng.randf() < 0.6 else ""
		Style.ENGINEER:
			var r := rng.randf()
			headwear = "goggles" if r < 0.45 else ("glasses" if r < 0.75 else "")
		Style.SPECIALIST:
			headwear = "glasses" if rng.randf() < 0.6 else ""

	# Body: technician coveralls with a hi-vis stripe; engineer and
	# specialist a white coat over a colored shirt.
	if style == Style.TECHNICIAN:
		var coverall: Color = COVERALL[rng.randi() % COVERALL.size()]
		_rect(img, 3, 13, 10, 3, coverall)
		_rect(img, 4, 12, 8, 1, coverall)
		_rect(img, 3, 14, 10, 1, Color(0.98, 0.72, 0.18))
		_rect(img, 5, 12, 1, 4, coverall.darkened(0.35)) # straps
		_rect(img, 10, 12, 1, 4, coverall.darkened(0.35))
	else:
		var coat := Color(0.90, 0.90, 0.88)
		_rect(img, 3, 13, 10, 3, coat)
		_rect(img, 4, 12, 8, 1, coat)
		_rect(img, 7, 12, 2, 4, SHIRT[rng.randi() % SHIRT.size()])
		_px(img, 6, 12, coat.darkened(0.25))
		_px(img, 9, 12, coat.darkened(0.25))

	# Neck, head (6x8 with rounded corners), ears.
	_rect(img, 7, 11, 2, 2, skin.darkened(0.12))
	_rect(img, 5, 4, 6, 8, skin)
	for corner in [Vector2i(5, 4), Vector2i(10, 4), Vector2i(5, 11), Vector2i(10, 11)]:
		_px(img, corner.x, corner.y, BG[style])
	_px(img, 4, 7, skin.darkened(0.1))
	_px(img, 11, 7, skin.darkened(0.1))

	# Hair.
	if hair_style != 3:
		_rect(img, 6, 3, 4, 1, hair)
		_rect(img, 5, 4, 6, 1, hair)
		_px(img, 5, 5, hair)
		_px(img, 10, 5, hair)
	else:
		_rect(img, 6, 4, 4, 1, hair.lerp(skin, 0.4))
	if hair_style == 1:
		_rect(img, 4, 5, 1, 7, hair)
		_rect(img, 11, 5, 1, 7, hair)
		_rect(img, 5, 6, 1, 3, hair)
		_rect(img, 10, 6, 1, 3, hair)
	elif hair_style == 2:
		_rect(img, 7, 1, 2, 2, hair)
	if beard:
		_rect(img, 5, 9, 6, 2, hair)
		_rect(img, 6, 11, 4, 1, hair)

	# Face.
	_px(img, 6, 7, OUTLINE)
	_px(img, 9, 7, OUTLINE)
	_rect(img, 7, 9, 2, 1, skin.darkened(0.35) if not beard else skin.darkened(0.15))

	match headwear:
		"hat":
			var hat: Color = HARD_HAT[rng.randi() % HARD_HAT.size()]
			_rect(img, 5, 2, 6, 2, hat)
			_rect(img, 4, 4, 8, 1, hat.darkened(0.2))
			_px(img, 6, 2, hat.lightened(0.4))
			_rect(img, 7, 1, 2, 1, hat)
		"goggles":
			_rect(img, 4, 5, 8, 1, Color(0.22, 0.22, 0.25))
			_px(img, 6, 5, Color(0.45, 0.80, 0.95))
			_px(img, 9, 5, Color(0.45, 0.80, 0.95))
		"glasses":
			var frame := Color(0.78, 0.80, 0.84) # silver, so the eyes still show
			_px(img, 5, 7, frame)
			_px(img, 7, 7, frame)
			_px(img, 8, 7, frame)
			_px(img, 10, 7, frame)

	var texture := ImageTexture.create_from_image(img)
	_cache[key] = texture
	return texture


## A TextureRect showing a portrait at a whole-number scale (nearest
## filtering - it's pixel art).
static func view(texture: Texture2D, box: int = 32) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture
	t.custom_minimum_size = Vector2(box, box)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


static func _px(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
		img.set_pixel(x, y, color)


static func _rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, color)


static func _frame(img: Image, color: Color) -> void:
	for i in SIZE:
		img.set_pixel(i, 0, color)
		img.set_pixel(i, SIZE - 1, color)
		img.set_pixel(0, i, color)
		img.set_pixel(SIZE - 1, i, color)
