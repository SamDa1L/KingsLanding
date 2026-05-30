class_name RandomGovernancePlaytest
extends "res://scripts/demo/GovernanceDemo.gd"


const NoiseBasedMapGeneratorScript := preload("res://scripts/mapgen/NoiseBasedMapGenerator.gd")
const GeneratedMapRendererScript := preload("res://scripts/mapgen/GeneratedMapRenderer.gd")
const GeneratedMapCompatibilityAdapterScript := preload("res://scripts/mapgen/GeneratedMapCompatibilityAdapter.gd")
const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd")
const MapTypes := preload("res://scripts/map/MapTypes.gd")

@export var random_map_seed: int = 20260530
@export var random_map_size: Vector2i = Vector2i(160, 160)
@export var random_map_chunk_size: int = 32
@export var clear_decor_layer_before_generate: bool = true
@export var enable_random_map_regenerate_shortcuts: bool = false
@export var enable_chunk_runtime_view: bool = true
@export var chunk_runtime_preload_radius: int = 1
@export var chunk_runtime_directional_preload_extra: int = 3
@export var chunk_runtime_keep_radius: int = 5
@export var chunk_runtime_initial_flush_iterations: int = 32

var _random_map_generator: NoiseBasedMapGenerator = NoiseBasedMapGeneratorScript.new()
var _random_map_renderer: GeneratedMapRenderer = GeneratedMapRendererScript.new()
var _compatibility_adapter = GeneratedMapCompatibilityAdapterScript.new()
var _generated_map_data

@onready var transition_layer: TileMapLayer = get_node_or_null("MapRoot/TransitionLayer") as TileMapLayer
@onready var chunk_streaming_manager: ChunkStreamingManager = get_node_or_null("ChunkStreamingManager") as ChunkStreamingManager


func _read_demo_map() -> void:
	_generate_random_governance_map()
	if _generated_map_data == null:
		push_error("RandomGovernancePlaytest failed to generate map data.")
		return

	var legacy_context: Dictionary = _compatibility_adapter.build_legacy_context(_generated_map_data)
	grid = legacy_context.get("grid", null)
	resource_regions = legacy_context.get("resource_regions", {})
	farmable_regions = legacy_context.get("farmable_regions", [])

	map_read_result = {
		"grid": grid,
		"used_rect": Rect2i(Vector2i.ZERO, random_map_size),
		"cell_offset": Vector2i.ZERO,
		"ground_cells_read": _count_base_cells(),
		"resource_cells_read": _count_resource_cells(),
		"terrain_counts": _build_terrain_counts_from_grid(grid),
	}

	var scanner := ResourceRegionScannerScript.new()
	_print_map_summary(map_read_result, resource_regions, scanner)
	_spawn_initial_buildings()
	_setup_placement_controller()
	_focus_camera_on_castle()
	_setup_chunk_runtime_view(true)


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if not enable_random_map_regenerate_shortcuts:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_R:
				_regenerate_random_map()
			KEY_N:
				random_map_seed += 1
				_regenerate_random_map()


func _regenerate_random_map() -> void:
	_generate_random_governance_map()
	if _generated_map_data == null:
		return

	var legacy_context: Dictionary = _compatibility_adapter.build_legacy_context(_generated_map_data)
	grid = legacy_context.get("grid", null)
	resource_regions = legacy_context.get("resource_regions", {})
	farmable_regions = legacy_context.get("farmable_regions", [])
	map_read_result = {
		"grid": grid,
		"used_rect": Rect2i(Vector2i.ZERO, random_map_size),
		"cell_offset": Vector2i.ZERO,
		"ground_cells_read": _count_base_cells(),
		"resource_cells_read": _count_resource_cells(),
		"terrain_counts": _build_terrain_counts_from_grid(grid),
	}

	var scanner := ResourceRegionScannerScript.new()
	_print_map_summary(map_read_result, resource_regions, scanner)
	_spawn_initial_buildings()
	_setup_placement_controller()
	_focus_camera_on_castle()
	_setup_chunk_runtime_view(true)
	_update_placement_overlay()
	_update_economy_ui()
	_update_stage14_hud()


func _generate_random_governance_map() -> void:
	if ground_layer == null or resource_layer == null:
		push_error("RandomGovernancePlaytest requires ground/resource layers.")
		return

	_generated_map_data = _random_map_generator.generate_map(
		random_map_seed,
		random_map_size.x,
		random_map_size.y,
		random_map_chunk_size
	)

	_clear_map_visual_layers()
	if not enable_chunk_runtime_view:
		_random_map_renderer.render_base_layer(ground_layer, _generated_map_data)
		_random_map_renderer.render_resource_layer(resource_layer, _generated_map_data)
	if clear_decor_layer_before_generate and decor_layer != null:
		decor_layer.clear()


func _count_base_cells() -> int:
	if _generated_map_data == null:
		return 0
	return _generated_map_data.tiles.size()


func _count_resource_cells() -> int:
	if _generated_map_data == null:
		return 0
	var count := 0
	for cell in _generated_map_data.tiles.keys():
		var tile = _generated_map_data.get_tile(cell)
		if tile == null:
			continue
		if tile.resource_type == GeneratedTileDataScript.RESOURCE_NONE:
			continue
		count += 1
	return count


func _build_terrain_counts_from_grid(next_grid) -> Dictionary:
	var counts: Dictionary = {
		MapTypes.TerrainType.TOWN_CENTER: 0,
		MapTypes.TerrainType.FOREST: 0,
		MapTypes.TerrainType.STONE: 0,
		MapTypes.TerrainType.PLAIN: 0,
		MapTypes.TerrainType.ROAD: 0,
		MapTypes.TerrainType.EMPTY: 0,
		MapTypes.TerrainType.WATER: 0,
		MapTypes.TerrainType.MOUNTAIN: 0,
	}
	if next_grid == null:
		return counts

	for cell in next_grid.get_all_cells():
		var terrain_type: int = next_grid.get_terrain(cell)
		counts[terrain_type] = int(counts.get(terrain_type, 0)) + 1
	return counts


func _setup_chunk_runtime_view(force_flush: bool = false) -> void:
	if not enable_chunk_runtime_view:
		return
	if chunk_streaming_manager == null or _generated_map_data == null:
		return

	chunk_streaming_manager.chunk_size = random_map_chunk_size
	chunk_streaming_manager.preload_radius = max(chunk_runtime_preload_radius, 0)
	chunk_streaming_manager.directional_preload_extra = max(chunk_runtime_directional_preload_extra, 0)
	chunk_streaming_manager.keep_radius = max(chunk_runtime_keep_radius, 0)
	chunk_streaming_manager.include_resources_runtime = true
	chunk_streaming_manager.include_transitions_runtime = transition_layer != null
	chunk_streaming_manager.setup_runtime(
		random_map_seed,
		_random_map_generator,
		_random_map_renderer,
		ground_layer,
		resource_layer,
		transition_layer,
		main_camera,
		_generated_map_data
	)
	if force_flush:
		chunk_streaming_manager.flush_until_visible_base_ready(chunk_runtime_initial_flush_iterations)


func _clear_map_visual_layers() -> void:
	if ground_layer != null:
		ground_layer.clear()
	if resource_layer != null:
		resource_layer.clear()
	if transition_layer != null:
		transition_layer.clear()


func _focus_camera_on_castle() -> void:
	if main_camera == null or ground_layer == null:
		return

	var castle_cell := _get_castle_cell()
	if castle_cell.x < 0 or castle_cell.y < 0:
		return

	main_camera.global_position = ground_layer.to_global(ground_layer.map_to_local(castle_cell))
