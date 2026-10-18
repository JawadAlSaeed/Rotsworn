class_name AssetLoader
extends RefCounted
## Loads art from paths stored in data files. A missing file gives a visible checkerboard
## placeholder and one warning, never a crash. Replace art by dropping a file with the same name
## into assets/ (run_game.bat or opening the editor imports it). A dropped-in file that has not
## been imported yet is read straight from disk, so it still shows up in a run from the editor.

static var _fallbacks: Dictionary = {}
static var _raw: Dictionary = {}
static var _meshes: Dictionary = {}
static var _warned: Dictionary = {}


## The texture at `path`, or a magenta/black checkerboard of `fallback_size` if it is missing.
static func texture(path: String, fallback_size: Vector2i = Vector2i(32, 32)) -> Texture2D:
	if not path.is_empty():
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				return tex
		var raw := _raw_texture(path)
		if raw != null:
			return raw
	_warn_once(path, "AssetLoader: missing texture '%s', using placeholder" % path)
	return fallback_texture(fallback_size)


## The mesh of the 3D model at `path` (a .glb holding one mesh at the origin, DESIGN.md 5.6), or
## null with one warning if it is missing, so the caller can fall back to its plain shape.
static func mesh(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path]
	var found: Mesh = null
	if not path.is_empty() and ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			var root := scene.instantiate()
			var holder := root as MeshInstance3D
			if holder == null:
				var all := root.find_children("*", "MeshInstance3D", true, false)
				holder = all[0] as MeshInstance3D if not all.is_empty() else null
			if holder != null:
				found = holder.mesh
			root.free()
	if found == null:
		_warn_once(path, "AssetLoader: missing model '%s', using the plain shape" % path)
	_meshes[path] = found
	return found


## Is there art at `path` (imported, or a raw file waiting for its import)? Unlike `texture` this
## never warns, so a caller can pick its own fallback.
static func has_art(path: String) -> bool:
	return not path.is_empty() and (ResourceLoader.exists(path) or FileAccess.file_exists(path))


## A magenta/black checkerboard (4 px squares), cached per size.
@warning_ignore("integer_division")
static func fallback_texture(size: Vector2i) -> Texture2D:
	if _fallbacks.has(size):
		return _fallbacks[size]
	var img := Image.create(maxi(1, size.x), maxi(1, size.y), false, Image.FORMAT_RGBA8)
	for y: int in img.get_height():
		for x: int in img.get_width():
			var magenta := ((x / 4) + (y / 4)) % 2 == 0
			img.set_pixel(x, y, Color(1, 0, 1) if magenta else Color(0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	_fallbacks[size] = tex
	return tex


## Reads an image file that exists on disk but has no import yet (null if there is none).
static func _raw_texture(path: String) -> Texture2D:
	if _raw.has(path):
		return _raw[path]
	var tex: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
			_warn_once(path, "AssetLoader: '%s' is not imported yet; read the raw file" % path)
	_raw[path] = tex
	return tex


static func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)
