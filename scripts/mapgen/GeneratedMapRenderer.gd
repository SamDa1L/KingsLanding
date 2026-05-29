class_name GeneratedMapRenderer
extends RefCounted


const TileRenderDefinitionScript := preload("res://scripts/mapgen/TileRenderDefinition.gd")

var last_rendered_cell_count: int = 0
var last_terrain_counts: Dictionary = {}
var last_resource_rendered_cell_count: int = 0
var last_resource_counts: Dictionary = {}
var last_resource_patch_ids: Dictionary = {}
var last_transition_rendered_cell_count: int = 0


func render_base_layer(base_layer: TileMapLayer, map_data) -> void:
	if base_layer == null:
		push_error("GeneratedMapRenderer requires a BaseLayer.")
		return
	if map_data == null:
		push_error("GeneratedMapRenderer requires GeneratedMapData.")
		return

	base_layer.clear()
	last_rendered_cell_count = 0
	last_terrain_counts.clear()

	for cell in map_data.get_all_cells():
		var tile = map_data.get_tile(cell)
		if tile == null:
			continue

		var atlas_coords := TileRenderDefinitionScript.get_base_tile(tile.base_terrain)
		if atlas_coords == TileRenderDefinitionScript.INVALID_ATLAS:
			continue

		base_layer.set_cell(cell, TileRenderDefinitionScript.TILE_SOURCE_ID, atlas_coords, 0)
		last_rendered_cell_count += 1
		last_terrain_counts[tile.base_terrain] = int(last_terrain_counts.get(tile.base_terrain, 0)) + 1


func render_base_cells(base_layer: TileMapLayer, map_data, cells: Array[Vector2i]) -> int:
	if base_layer == null:
		push_error("GeneratedMapRenderer requires a BaseLayer.")
		return 0
	if map_data == null:
		push_error("GeneratedMapRenderer requires GeneratedMapData.")
		return 0

	var rendered_count := 0
	for cell in cells:
		base_layer.set_cell(cell, -1)

		var tile = map_data.get_tile(cell)
		if tile == null:
			continue

		var atlas_coords := TileRenderDefinitionScript.get_base_tile(tile.base_terrain)
		if atlas_coords == TileRenderDefinitionScript.INVALID_ATLAS:
			continue

		base_layer.set_cell(cell, TileRenderDefinitionScript.TILE_SOURCE_ID, atlas_coords, 0)
		rendered_count += 1

	return rendered_count


func render_resource_layer(resource_layer: TileMapLayer, map_data) -> void:
	if resource_layer == null:
		push_error("GeneratedMapRenderer requires a ResourceLayer.")
		return
	if map_data == null:
		push_error("GeneratedMapRenderer requires GeneratedMapData.")
		return

	resource_layer.clear()
	last_resource_rendered_cell_count = 0
	last_resource_counts.clear()
	last_resource_patch_ids.clear()

	for cell in map_data.get_all_cells():
		var tile = map_data.get_tile(cell)
		if tile == null:
			continue
		if tile.resource_type == &"none":
			continue

		var atlas_coords := TileRenderDefinitionScript.get_resource_tile(tile.resource_type)
		if atlas_coords == TileRenderDefinitionScript.INVALID_ATLAS:
			continue

		resource_layer.set_cell(cell, TileRenderDefinitionScript.TILE_SOURCE_ID, atlas_coords, 0)
		last_resource_rendered_cell_count += 1
		last_resource_counts[tile.resource_type] = int(last_resource_counts.get(tile.resource_type, 0)) + 1
		if tile.resource_patch_id >= 0:
			last_resource_patch_ids[tile.resource_patch_id] = tile.resource_type


func render_resource_cells(resource_layer: TileMapLayer, map_data, cells: Array[Vector2i]) -> int:
	if resource_layer == null:
		push_error("GeneratedMapRenderer requires a ResourceLayer.")
		return 0
	if map_data == null:
		push_error("GeneratedMapRenderer requires GeneratedMapData.")
		return 0

	var rendered_count := 0
	for cell in cells:
		resource_layer.set_cell(cell, -1)

		var tile = map_data.get_tile(cell)
		if tile == null:
			continue
		if tile.resource_type == &"none":
			continue

		var atlas_coords := TileRenderDefinitionScript.get_resource_tile(tile.resource_type)
		if atlas_coords == TileRenderDefinitionScript.INVALID_ATLAS:
			continue

		resource_layer.set_cell(cell, TileRenderDefinitionScript.TILE_SOURCE_ID, atlas_coords, 0)
		rendered_count += 1

	return rendered_count


func render_transition_layer(transition_layer: TileMapLayer, map_data) -> void:
	if transition_layer == null:
		push_error("GeneratedMapRenderer requires a TransitionLayer.")
		return
	if map_data == null:
		push_error("GeneratedMapRenderer requires GeneratedMapData.")
		return

	transition_layer.clear()
	last_transition_rendered_cell_count = 0

	for cell in map_data.get_all_cells():
		if _render_transition_cell(transition_layer, map_data, cell):
			last_transition_rendered_cell_count += 1


func render_transition_cells(transition_layer: TileMapLayer, map_data, cells: Array[Vector2i]) -> int:
	if transition_layer == null:
		push_error("GeneratedMapRenderer requires a TransitionLayer.")
		return 0
	if map_data == null:
		push_error("GeneratedMapRenderer requires GeneratedMapData.")
		return 0

	var rendered_count := 0
	for cell in cells:
		if _render_transition_cell(transition_layer, map_data, cell):
			rendered_count += 1

	return rendered_count


func refresh_chunk_transition_edges(transition_layer: TileMapLayer, map_data, chunk_coords: Vector2i) -> int:
	if map_data == null:
		push_error("GeneratedMapRenderer requires GeneratedMapData.")
		return 0
	if not map_data.has_method("get_adjacent_chunk_edge_refresh_cells"):
		return 0

	var refresh_cells: Array[Vector2i] = map_data.get_adjacent_chunk_edge_refresh_cells(chunk_coords)
	return render_transition_cells(transition_layer, map_data, refresh_cells)


func get_terrain_count(base_terrain: StringName) -> int:
	return int(last_terrain_counts.get(base_terrain, 0))


func get_resource_count(resource_type: StringName) -> int:
	return int(last_resource_counts.get(resource_type, 0))


func get_resource_patch_count(resource_type: StringName = &"") -> int:
	if resource_type == &"":
		return last_resource_patch_ids.size()

	var count := 0
	for patch_id in last_resource_patch_ids.keys():
		if last_resource_patch_ids[patch_id] != resource_type:
			continue
		count += 1
	return count


func _get_land_mask_for_water_cell(map_data, cell: Vector2i) -> int:
	var mask := 0

	var top: Variant = map_data.get_tile(cell + Vector2i.UP)
	var right: Variant = map_data.get_tile(cell + Vector2i.RIGHT)
	var bottom: Variant = map_data.get_tile(cell + Vector2i.DOWN)
	var left: Variant = map_data.get_tile(cell + Vector2i.LEFT)

	if top != null and _is_land_terrain(top.base_terrain):
		mask |= TileRenderDefinitionScript.DIR_N
	if right != null and _is_land_terrain(right.base_terrain):
		mask |= TileRenderDefinitionScript.DIR_E
	if bottom != null and _is_land_terrain(bottom.base_terrain):
		mask |= TileRenderDefinitionScript.DIR_S
	if left != null and _is_land_terrain(left.base_terrain):
		mask |= TileRenderDefinitionScript.DIR_W

	return mask


func _render_transition_cell(transition_layer: TileMapLayer, map_data, cell: Vector2i) -> bool:
	transition_layer.set_cell(cell, -1)

	var tile = map_data.get_tile(cell)
	if tile == null:
		return false
	if not _is_water_terrain(tile.base_terrain):
		return false

	var mask := _get_land_mask_for_water_cell(map_data, cell)
	if mask == 0:
		return false

	var atlas_coords := TileRenderDefinitionScript.get_transition_tile(&"water_to_land", mask)
	if atlas_coords == TileRenderDefinitionScript.INVALID_ATLAS:
		return false

	transition_layer.set_cell(cell, TileRenderDefinitionScript.TILE_SOURCE_ID, atlas_coords, 0)
	return true


func _is_land_terrain(base_terrain: StringName) -> bool:
	return not _is_water_terrain(base_terrain)


func _is_water_terrain(base_terrain: StringName) -> bool:
	return base_terrain == &"water" or base_terrain == &"shallow_water"


func _get_transition_atlas(mask: int) -> Vector2i:
	return TileRenderDefinitionScript.get_transition_tile(&"water_to_land", mask)
