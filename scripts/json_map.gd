extends Node2D
## Deliberately small Tiled contract: finite orthogonal, one embedded atlas,
## flat numeric tile data, and point markers. Unsupported formats fail clearly.

var last_error := ""
var spawn := Vector2.ZERO
var map_size := Vector2.ZERO
var cell_count := 0

func fail(message: String) -> bool:
	last_error = message
	return false

func load_map(path: String) -> bool:
	last_error = ""
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return fail("Invalid JSON: " + parser.get_error_message())
	var m = parser.data
	if not m is Dictionary:
		return fail("Map root must be an object")
	if m.get("orientation") != "orthogonal" or m.get("infinite", false):
		return fail("Only finite orthogonal maps are supported")
	var w := int(m.get("width", 0))
	var h := int(m.get("height", 0))
	var tw := int(m.get("tilewidth", 0))
	var th := int(m.get("tileheight", 0))
	if w <= 0 or h <= 0 or tw <= 0 or th <= 0:
		return fail("Map dimensions must be positive")
	var definitions = m.get("tilesets", [])
	if not definitions is Array or definitions.size() != 1:
		return fail("Expected one embedded atlas tileset")
	var atlas = definitions[0]
	if atlas.has("source") or not atlas.has("image"):
		return fail("External TSX/TSJ and image collections are unsupported")
	if int(atlas.get("tilewidth", 0)) != tw or int(atlas.get("tileheight", 0)) != th:
		return fail("Atlas tile size must match map tile size")
	var image_path: String = path.get_base_dir().path_join(str(atlas.image)).simplify_path()
	var texture = load(image_path) as Texture2D
	if texture == null:
		return fail("Cannot load atlas: " + image_path)
	var first := int(atlas.get("firstgid", 1))
	var columns := int(atlas.get("columns", 0))
	var total := int(atlas.get("tilecount", 0))
	var spacing := int(atlas.get("spacing", 0))
	var margin := int(atlas.get("margin", 0))
	if first < 1 or columns < 1 or total < 1 or spacing < 0 or margin < 0:
		return fail("Atlas needs positive firstgid, columns and tilecount")
	if margin * 2 + columns * tw + (columns - 1) * spacing > texture.get_width():
		return fail("Atlas columns exceed texture width")
	var rows := ceili(float(total) / columns)
	if margin * 2 + rows * th + (rows - 1) * spacing > texture.get_height():
		return fail("Atlas rows exceed texture height")
	var layers = m.get("layers", [])
	if not layers is Array:
		return fail("layers must be an array")
	var new_spawn := Vector2(tw * 2, th * 2)
	# Validate the entire document before replacing the previous map.
	for layer in layers:
		if layer.get("type") == "objectgroup":
			for obj in layer.get("objects", []):
				if obj.get("name") == "spawn":
					new_spawn = Vector2(float(obj.x), float(obj.y))
			continue
		if layer.get("type") != "tilelayer":
			return fail("Unsupported layer type")
		if int(layer.get("x", 0)) != 0 or int(layer.get("y", 0)) != 0:
			return fail("Use pixel offsetx/offsety instead of layer x/y")
		if layer.has("chunks") or layer.has("encoding") or layer.has("compression"):
			return fail("Use uncompressed numeric data arrays")
		if int(layer.get("width", 0)) != w or int(layer.get("height", 0)) != h:
			return fail("Layer dimensions must match map")
		var data = layer.get("data", [])
		if not data is Array or data.size() != w * h:
			return fail("Layer data length must equal width * height")
		for value in data:
			if not (value is float or value is int):
				return fail("GIDs must be integers")
			var gid := int(value)
			if float(gid) != float(value) or gid < 0 or gid >= 0x10000000:
				return fail("Flipped/rotated GIDs and non-integer GIDs are unsupported")
			if gid != 0 and (gid < first or gid >= first + total):
				return fail("GID outside atlas range")
	for child in get_children():
		remove_child(child)
		child.queue_free()
	cell_count = 0
	spawn = new_spawn
	map_size = Vector2(w * tw, h * th)
	for layer in layers:
		if layer.type != "tilelayer":
			continue
		var solid := false
		for property in layer.get("properties", []):
			if property.name == "solid":
				solid = bool(property.value)
		var tiles := TileSet.new()
		tiles.tile_size = Vector2i(tw, th)
		if solid:
			tiles.add_physics_layer()
			tiles.set_physics_layer_collision_layer(0, 1)
		var source := TileSetAtlasSource.new()
		source.texture = texture
		source.texture_region_size = Vector2i(tw, th)
		source.separation = Vector2i(spacing, spacing)
		source.margins = Vector2i(margin, margin)
		for local_id in range(total):
			var coords := Vector2i(local_id % columns, local_id / columns)
			source.create_tile(coords)
		tiles.add_source(source, 0)
		if solid:
			for local_id in range(total):
				var tile := source.get_tile_data(Vector2i(local_id % columns, local_id / columns), 0)
				tile.set_collision_polygons_count(0, 1)
				tile.set_collision_polygon_points(0, 0, PackedVector2Array([
					Vector2(-tw, -th) / 2, Vector2(tw, -th) / 2,
					Vector2(tw, th) / 2, Vector2(-tw, th) / 2]))
		var node := TileMapLayer.new()
		node.name = str(layer.get("name", "Tiles"))
		node.tile_set = tiles
		node.visible = bool(layer.get("visible", true))
		node.modulate.a = float(layer.get("opacity", 1.0))
		node.position = Vector2(float(layer.get("offsetx", 0)), float(layer.get("offsety", 0)))
		add_child(node)
		for i in range(layer.data.size()):
			var gid := int(layer.data[i])
			if gid == 0:
				continue
			var local_id := gid - first
			node.set_cell(Vector2i(i % w, i / w), 0, Vector2i(local_id % columns, local_id / columns))
			cell_count += 1
		node.update_internals()
	return true
