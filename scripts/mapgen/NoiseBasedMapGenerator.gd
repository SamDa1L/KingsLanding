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
			var world_pos := _cell_to_world_position(cell, generated_map.width, generated_map.height)
			var tile = GeneratedTileDataScript.new()
			tile.setup(cell, GeneratedTileDataScript.TERRAIN_PLAIN)

			var height_value := _sample_height(world_pos)
			var moisture_value := _sample_moisture(world_pos)
			var temperature_value := _sample_temperature(world_pos)

			tile.set_noise_values(height_value, moisture_value, temperature_value)
			_apply_base_terrain(tile, height_value)
			generated_map.set_tile(cell, tile)

	if resource_patch_generator != null:
		resource_patch_generator.apply_resource_patches(generated_map, map_seed)

	return generated_map


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


func _cell_to_world_position(cell: Vector2i, map_width: int, map_height: int) -> Vector2:
	var centered_x := float(cell.x) - float(map_width) * 0.5
	var centered_y := float(cell.y) - float(map_height) * 0.5
	return Vector2(centered_x, centered_y)


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
