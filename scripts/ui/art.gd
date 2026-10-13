class_name Art
extends RefCounted
## The Higgsfield pictures in assets/art/ (fetched by tools/fetch_assets.sh). Every getter returns null
## when a file is missing, and callers then draw the plain shapes instead.

static var _cache := {}


static func texture(file: String) -> Texture2D:
	if not _cache.has(file):
		var path := "res://assets/art/" + file
		_cache[file] = load(path) if ResourceLoader.exists(path) else null
	return _cache[file]


## A full-screen picture with a dark veil so text stays readable; null without the picture.
static func backdrop(file: String, veil: float = 0.55) -> Control:
	var tex := texture(file)
	if tex == null:
		return null
	var root := Control.new()
	root.name = "Backdrop"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(pic)
	var dim := ColorRect.new()
	dim.color = Color(UI.BG, veil)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	return root


## A picture strip for the top of a card; null without the picture.
static func banner(file: String, height: float) -> TextureRect:
	var tex := texture(file)
	if tex == null:
		return null
	var pic := TextureRect.new()
	pic.name = "Banner"
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size.y = height
	pic.clip_contents = true
	return pic


static func clear_cache() -> void:
	_cache.clear()
