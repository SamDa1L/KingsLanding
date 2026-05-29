class_name NoiseBasedMapGenerator
extends RefCounted


const GeneratedMapDataScript := preload("res://scripts/mapgen/GeneratedMapData.gd")
const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd")
const ResourcePatchGeneratorScript := preload("res://scripts/mapgen/ResourcePatchGenerator.gd")

const DEFAULT_WIDTH := 128
const DEFAULT_HEIGHT := 128
const DEFAULT_CHUNK_SIZE := 32

const WATER_HEIGHT_THRESHOLD := -0.42
const SHALLOW_WATER_HEIGHT_THRESHOLD := -0.26
const SAND_HEIGHT_THRESHOLD := -0.18

var height_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var temperature_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var resource_patch_generator: RefCounted


func _init() -> void:
	_setup_noise_objects()
	resource_patch_generator = ResourcePatchGeneratorScript.new()


func generate_map(map_seed: int, map_width: int = DEFAULT_WIDTH, map_height: int = DEFAULT_HEIGHT, map_chunk_size: int = DEFAULT_CHUNK_SIZE):
	setup_noise(map_seed)

	var generated_map = GeneratedMapDataScript.new()
	generated_map.setup(map_seed, map_width, map_height, map_chunk_size)

	for y in range(generated_map.height):
		for x in range(generated_map.width):
			var cell := Vector2i(x, y)
			var tile = generate_tile(map_seed, cell)
			generated_map.set_tile(cell, tile)

	if resource_patch_generator != null:
		resource_patch_generator.apply_resource_patches(generated_map, map_seed)

	return generated_map


func generate_chunk_map(map_seed: int, chunk_coords_list: Array[Vector2i], map_chunk_size: int = DEFAULT_CHUNK_SIZE, include_resources: bool = false):
	setup_noise(map_seed)

	var generated_map = GeneratedMapDataScript.new()
	var bounds := _get_chunk_bounds(chunk_coords_list, map_chunk_size)
	generated_map.setup(map_seed, int(bounds.size.x), int(bounds.size.y), map_chunk_size, bounds.origin)

	for chunk_coords in chunk_coords_list:
		_generate_chunk_into_map(generated_map, map_seed, chunk_coords, bounds.origin)

	if include_resources and resource_patch_generator != null:
		resource_patch_generator.apply_resource_patches(generated_map, map_seed)

	return generated_map


func generate_tile(map_seed: int, cell: Vector2i):
	if height_noise == null:
		setup_noise(map_seed)

	var world_pos := _cell_to_world_position(cell)
	var tile = GeneratedTileDataScript.new()
	tile.setup(cell, GeneratedTileDataScript.TERRAIN_PLAIN)

	var height_value := _sample_height(world_pos)
	var moisture_value := _sample_moisture(world_pos)
	var temperature_value := _sample_temperature(world_pos)

	tile.set_noise_values(height_value, moisture_value, temperature_value)
	_apply_base_terrain(tile, height_value)
	return tile


func apply_runtime_resource_to_tile(tile, map_seed: int) -> void:
	if resource_patch_generator == null or tile == null:
		return
	resource_patch_generator.apply_runtime_resource_to_tile(tile, map_seed)


func setup_noise(map_seed: int) -> void:
	height_noise.seed = map_seed + 100
	height_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	height_noise.frequency = 0.010
	height_noise.fractal_octaves = 4
	height_noise.fractal_gain = 0.5
	height_noise.fractal_lacunarity = 2.0

	moisture_noise.seed = map_seed + 200
	moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	moisture_noise.frequency = 0.018
	moisture_noise.fractal_octaves = 3
	moisture_noise.fractal_gain = 0.5
	moisture_noise.fractal_lacunarity = 2.0

	temperature_noise.seed = map_seed + 300
	temperature_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	temperature_noise.frequency = 0.012
	temperature_noise.fractal_octaves = 3
	temperature_noise.fractal_gain = 0.5
	temperature_noise.fractal_lacunarity = 2.0

	detail_noise.seed = map_seed + 400
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.frequency = 0.045
	detail_noise.fractal_octaves = 2
	detail_noise.fractal_gain = 0.5
	detail_noise.fractal_lacunarity = 2.0


func _setup_noise_objects() -> void:
	height_noise = FastNoiseLite.new()
	moisture_noise = FastNoiseLite.new()
	temperature_noise = FastNoiseLite.new()
	detail_noise = FastNoiseLite.new()


func _cell_to_world_position(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x), float(cell.y))


func _sample_height(world_pos: Vector2) -> float:
	var large := height_noise.get_noise_2d(world_pos.x, world_pos.y)
	var detail := detail_noise.get_noise_2d(world_pos.x * 1.8, world_pos.y * 1.8) * 0.18
	return clamp(large + detail, -1.0, 1.0)


func _sample_moisture(world_pos: Vector2) -> float:
	return clamp(moisture_noise.get_noise_2d(world_pos.x, world_pos.y), -1.0, 1.0)


func _sample_temperature(world_pos: Vector2) -> float:
	return clamp(temperature_noise.get_noise_2d(world_pos.x, world_pos.y), -1.0, 1.0)


func _apply_base_terrain(tile, height_value: float) -> void:
	if tile == null:
		return

	if height_value <= WATER_HEIGHT_THRESHOLD:
		tile.set_base_terrain(GeneratedTileDataScript.TERRAIN_WATER, false, false)
		return

	if height_value <= SHALLOW_WATER_HEIGHT_THRESHOLD:
		tile.set_base_terrain(GeneratedTileDataScript.TERRAIN_SHALLOW_WATER, false, false)
		return

	if height_value <= SAND_HEIGHT_THRESHOLD:
		tile.set_base_terrain(GeneratedTileDataScript.TERRAIN_SAND, true, true)
		return

	tile.set_base_terrain(GeneratedTileDataScript.TERRAIN_PLAIN, true, true)


func _generate_chunk_into_map(generated_map, map_seed: int, chunk_coords: Vector2i, origin_offset: Vector2i = Vector2i.ZERO) -> void:
	if generated_map == null:
		return

	var world_origin: Vector2i = chunk_coords * generated_map.chunk_size
	for local_y in range(generated_map.chunk_size):
		for local_x in range(generated_map.chunk_size):
			var world_cell := world_origin + Vector2i(local_x, local_y)
			var map_cell := world_cell - origin_offset
			if not generated_map.is_inside(map_cell):
				continue

			var tile = generate_tile(map_seed, world_cell)
			tile.cell = map_cell
			generated_map.set_tile(map_cell, tile)


func _get_chunk_bounds(chunk_coords_list: Array[Vector2i], map_chunk_size: int) -> Dictionary:
	if chunk_coords_list.is_empty():
		return {
			"origin": Vector2i.ZERO,
			"size": Vector2i.ZERO,
		}

	var min_chunk := chunk_coords_list[0]
	var max_chunk := chunk_coords_list[0]

	for chunk_coords in chunk_coords_list:
		min_chunk.x = min(min_chunk.x, chunk_coords.x)
		min_chunk.y = min(min_chunk.y, chunk_coords.y)
		max_chunk.x = max(max_chunk.x, chunk_coords.x)
		max_chunk.y = max(max_chunk.y, chunk_coords.y)

	var origin := min_chunk * map_chunk_size
	var chunk_count := (max_chunk - min_chunk) + Vector2i.ONE
	var size := chunk_count * map_chunk_size

	return {
		"origin": origin,
		"size": size,
	}
