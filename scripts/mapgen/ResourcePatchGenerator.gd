class_name ResourcePatchGenerator
extends RefCounted


const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd")

const PATCH_NOISE_SCALE := 0.072
const WOOD_PATCH_THRESHOLD := 0.28
const STONE_PATCH_THRESHOLD := 0.34
const MIN_WOOD_PATCH_SIZE := 10
const MIN_STONE_PATCH_SIZE := 8
const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]

var _wood_noise: FastNoiseLite
var _stone_noise: FastNoiseLite
var _configured_seed: int = 0
var _is_configured: bool = false


func _init() -> void:
	_setup_noise()


func apply_resource_patches(map_data, map_seed: int) -> Dictionary:
	if map_data == null:
		return _empty_summary()

	_ensure_configured(map_seed)
	_clear_existing_resources(map_data)

	var summary := {
		GeneratedTileDataScript.RESOURCE_WOOD: {
			"patch_count": 0,
			"tile_count": 0,
		},
		GeneratedTileDataScript.RESOURCE_STONE: {
			"patch_count": 0,
			"tile_count": 0,
		},
	}

	var visited: Dictionary = {}
	var next_patch_id := 0

	for cell in map_data.get_all_cells():
		if visited.has(cell):
			continue

		var tile = map_data.get_tile(cell)
		if not _can_host_resource(tile):
			visited[cell] = true
			continue

		var resource_type := _sample_resource_type(cell, map_seed)
		if resource_type == GeneratedTileDataScript.RESOURCE_NONE:
			visited[cell] = true
			continue

		var patch_cells := _collect_patch_cells(map_data, cell, resource_type, visited, map_seed)
		if patch_cells.is_empty():
			continue

		var min_size := _get_min_patch_size(resource_type)
		if patch_cells.size() < min_size:
			_clear_patch(map_data, patch_cells)
			continue

		for patch_cell in patch_cells:
			var patch_tile = map_data.get_tile(patch_cell)
			if patch_tile == null:
				continue
			patch_tile.set_resource(resource_type, next_patch_id, 1.0)

		var resource_summary: Dictionary = summary[resource_type]
		resource_summary["patch_count"] = int(resource_summary["patch_count"]) + 1
		resource_summary["tile_count"] = int(resource_summary["tile_count"]) + patch_cells.size()
		next_patch_id += 1

	return summary


func sample_resource_for_cell(cell: Vector2i, map_seed: int, base_terrain: StringName) -> StringName:
	_ensure_configured(map_seed)
	if base_terrain != GeneratedTileDataScript.TERRAIN_PLAIN and base_terrain != GeneratedTileDataScript.TERRAIN_SAND:
		return GeneratedTileDataScript.RESOURCE_NONE
	return _sample_resource_type(cell, map_seed)


func apply_runtime_resource_to_tile(tile, map_seed: int) -> void:
	if tile == null:
		return
	if not _can_host_resource(tile):
		tile.clear_resource()
		return

	var resource_type := sample_resource_for_cell(tile.cell, map_seed, tile.base_terrain)
	if resource_type == GeneratedTileDataScript.RESOURCE_NONE:
		tile.clear_resource()
		return

	tile.set_resource(resource_type, -1, 1.0)


func _empty_summary() -> Dictionary:
	return {
		GeneratedTileDataScript.RESOURCE_WOOD: {
			"patch_count": 0,
			"tile_count": 0,
		},
		GeneratedTileDataScript.RESOURCE_STONE: {
			"patch_count": 0,
			"tile_count": 0,
		},
	}


func _setup_noise() -> void:
	_wood_noise = FastNoiseLite.new()
	_wood_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_wood_noise.frequency = PATCH_NOISE_SCALE
	_wood_noise.fractal_octaves = 3
	_wood_noise.fractal_gain = 0.55
	_wood_noise.fractal_lacunarity = 2.0

	_stone_noise = FastNoiseLite.new()
	_stone_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_stone_noise.frequency = PATCH_NOISE_SCALE * 0.82
	_stone_noise.fractal_octaves = 3
	_stone_noise.fractal_gain = 0.5
	_stone_noise.fractal_lacunarity = 2.2


func _configure_noise(map_seed: int) -> void:
	_wood_noise.seed = map_seed + 1000
	_stone_noise.seed = map_seed + 2000
	_configured_seed = map_seed
	_is_configured = true


func _ensure_configured(map_seed: int) -> void:
	if _is_configured and _configured_seed == map_seed:
		return
	_configure_noise(map_seed)


func _clear_existing_resources(map_data) -> void:
	for cell in map_data.get_all_cells():
		var tile = map_data.get_tile(cell)
		if tile == null:
			continue
		tile.clear_resource()


func _can_host_resource(tile) -> bool:
	if tile == null:
		return false
	return tile.base_terrain == GeneratedTileDataScript.TERRAIN_PLAIN or tile.base_terrain == GeneratedTileDataScript.TERRAIN_SAND


func _sample_resource_type(cell: Vector2i, map_seed: int) -> StringName:
	var world_pos := Vector2(float(cell.x), float(cell.y))
	var wood_value := _wood_noise.get_noise_2d(world_pos.x, world_pos.y)
	var stone_value := _stone_noise.get_noise_2d(world_pos.x + 137.0, world_pos.y - 91.0)
	var selector := _hash01(cell, map_seed, 17)

	if wood_value >= WOOD_PATCH_THRESHOLD and wood_value >= stone_value + 0.06 and selector >= 0.18:
		return GeneratedTileDataScript.RESOURCE_WOOD

	if stone_value >= STONE_PATCH_THRESHOLD and stone_value >= wood_value + 0.03 and selector >= 0.24:
		return GeneratedTileDataScript.RESOURCE_STONE

	return GeneratedTileDataScript.RESOURCE_NONE


func _collect_patch_cells(map_data, start_cell: Vector2i, resource_type: StringName, visited: Dictionary, map_seed: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var stack: Array[Vector2i] = [start_cell]

	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		if visited.has(cell):
			continue
		visited[cell] = true

		var tile = map_data.get_tile(cell)
		if not _can_host_resource(tile):
			continue
		if _sample_resource_type(cell, map_seed) != resource_type:
			continue

		result.append(cell)

		for offset in CARDINAL_DIRECTIONS:
			var neighbor: Vector2i = cell + offset
			if not map_data.is_inside(neighbor):
				continue
			if visited.has(neighbor):
				continue
			stack.append(neighbor)

	return result


func _clear_patch(map_data, patch_cells: Array[Vector2i]) -> void:
	for cell in patch_cells:
		var tile = map_data.get_tile(cell)
		if tile == null:
			continue
		tile.clear_resource()


func _get_min_patch_size(resource_type: StringName) -> int:
	if resource_type == GeneratedTileDataScript.RESOURCE_WOOD:
		return MIN_WOOD_PATCH_SIZE
	if resource_type == GeneratedTileDataScript.RESOURCE_STONE:
		return MIN_STONE_PATCH_SIZE
	return 1


func _hash01(cell: Vector2i, map_seed: int, salt: int) -> float:
	var value := int(cell.x) * 92821
	value += int(cell.y) * 68917
	value += map_seed * 31
	value += salt * 131
	value = abs(value)
	return float(value % 1000) / 999.0
