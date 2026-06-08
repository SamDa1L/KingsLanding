class_name RandomGovernancePlaytest
extends "res://scripts/demo/GovernanceDemo.gd"


const NoiseBasedMapGeneratorScript := preload("res://scripts/mapgen/NoiseBasedMapGenerator.gd")
const GeneratedMapRendererScript := preload("res://scripts/mapgen/GeneratedMapRenderer.gd")
const GeneratedMapCompatibilityAdapterScript := preload("res://scripts/mapgen/GeneratedMapCompatibilityAdapter.gd")
const BuildingDataScript := preload("res://scripts/buildings/BuildingData.gd")
const MapTypes := preload("res://scripts/map/MapTypes.gd")
const WorldGenerationIdentityScript := preload("res://scripts/mapgen/world/WorldGenerationIdentity.gd")
const WorldSemanticMapSaveScript := preload("res://scripts/mapgen/world/WorldSemanticMapSave.gd")
const WorldSemanticGovernanceAdapterScript := preload("res://scripts/mapgen/world/WorldSemanticGovernanceAdapter.gd")
const WorldSemanticGameplayQueryBridgeScript := preload("res://scripts/mapgen/world/WorldSemanticGameplayQueryBridge.gd")
const WorldSemanticRuntimeViewScript := preload("res://scripts/mapgen/world/WorldSemanticRuntimeView.gd")
const WorldSessionScript := preload("res://scripts/mapgen/world/WorldSession.gd")
const DEFAULT_SEMANTIC_LOADING_SCENE_PATH := "res://scenes/loading/RandomGovernanceWorldLoading.tscn"
const DEFAULT_SEMANTIC_WORLD_SAVE_PATH := "user://random_governance_playtest_semantic_world.save"
const SELF_SCENE_PATH := "res://scenes/testScenes/RandomGovernancePlaytest.tscn"
const LOAD_BASELINE_SOURCE_UNKNOWN := "unknown"
const LOAD_BASELINE_SOURCE_LEGACY_RANDOM := "legacy_random"
const LOAD_BASELINE_SOURCE_SESSION_READY_STORE := "session_ready_store"
const LOAD_BASELINE_SOURCE_RESTORED_SAVED_WORLD := "restored_saved_world"
const LOAD_BASELINE_SOURCE_LOADING_TRANSITION_REQUESTED := "loading_transition_requested"
const BOOTSTRAP_RESTORE_MODE_NONE := "none"
const BOOTSTRAP_RESTORE_MODE_CACHE := "cache"
const BOOTSTRAP_RESTORE_MODE_REBUILD := "rebuild"

enum MapBootstrapMode {
	LEGACY_RANDOM_ONLY,
	SEMANTIC_PREWARM_FIRST,
	SEMANTIC_PREWARM_REQUIRED,
}

enum BootstrapWorldSourceResult {
	LEGACY_RANDOM,
	SEMANTIC_READY,
	TRANSITIONED_TO_LOADING,
	FAILED,
}

@export var random_map_seed: int = 20260530
@export_file("*.save") var semantic_world_save_path: String = DEFAULT_SEMANTIC_WORLD_SAVE_PATH
@export var random_map_size: Vector2i = Vector2i(160, 160)
@export var random_map_chunk_size: int = 32
@export var map_bootstrap_mode: int = MapBootstrapMode.SEMANTIC_PREWARM_FIRST
@export_file("*.tscn") var semantic_loading_scene_path: String = DEFAULT_SEMANTIC_LOADING_SCENE_PATH
@export var enable_semantic_world_restore: bool = false
@export var semantic_governance_bootstrap_tile_rect: Rect2i = Rect2i(Vector2i(-256, -256), Vector2i(512, 512))
@export var enable_compact_governance_bootstrap: bool = false
@export var semantic_governance_compact_bootstrap_tile_rect: Rect2i = Rect2i(Vector2i(-192, -192), Vector2i(384, 384))
@export var enable_semantic_runtime_view: bool = true
@export var semantic_runtime_render_padding_cells: int = 6
@export var semantic_runtime_preload_margin: int = 2
@export var semantic_runtime_keep_margin: int = 3
@export var semantic_runtime_visual_chunks_per_frame: int = 6
@export var semantic_runtime_camera_coverage_safety_margin: int = 1
@export var semantic_runtime_unload_idle_delay_seconds: float = 0.25
@export var auto_build_full_visuals_on_ready: bool = true
@export var visual_build_mode: int = 0
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
var _semantic_governance_adapter = WorldSemanticGovernanceAdapterScript.new()
var _generated_map_data
var _bootstrapped_semantic_store = null
var _bootstrapped_semantic_identity = null
var _last_bootstrap_error: String = ""
var _semantic_runtime_view = null
var _semantic_gameplay_query_bridge = null
var _visual_build_prepared: bool = false
var _visual_build_complete: bool = false
var _visual_build_done_units: int = 0
var _visual_build_total_units: int = 0
var _visual_build_stage_name: String = "Preparing gameplay scene"
var _entry_visuals_finalized: bool = false
var _pending_restored_runtime_chunks: Dictionary = {}
var _pending_restored_governance_bootstrap_cache: Dictionary = {}
var _pending_restored_gameplay_state: Dictionary = {}
var _pending_restored_camera_cell: Vector2i = Vector2i.ZERO
var _pending_restored_camera_zoom: float = 1.0
var _has_pending_restored_camera_state: bool = false
var _last_bootstrap_restore_mode: String = BOOTSTRAP_RESTORE_MODE_NONE
var _semantic_bootstrap_build_count: int = 0
var _warned_invalid_compact_bootstrap_rect: bool = false
var _scene_constructed_at_usec: int = 0
var _ready_started_at_usec: int = 0
var _read_demo_map_started_at_usec: int = 0
var _load_baseline_metrics: Dictionary = {}
var _load_baseline_metrics_complete: bool = false
var _load_baseline_playable_recorded: bool = false
var _load_baseline_visual_queue_drained_recorded: bool = false
var _load_baseline_completion_logged: bool = false

@onready var transition_layer: TileMapLayer = get_node_or_null("MapRoot/TransitionLayer") as TileMapLayer
@onready var chunk_streaming_manager: ChunkStreamingManager = get_node_or_null("ChunkStreamingManager") as ChunkStreamingManager
@onready var return_castle_button: Button = get_node_or_null("UIRoot/TopResourceBar/HBoxContainer/ReturnCastleButton") as Button
@onready var save_map_button: Button = get_node_or_null("UIRoot/TopResourceBar/HBoxContainer/SaveMapButton") as Button
@onready var reset_map_button: Button = get_node_or_null("UIRoot/TopResourceBar/HBoxContainer/ResetMapButton") as Button


func _init() -> void:
	_scene_constructed_at_usec = Time.get_ticks_usec()
	_reset_load_baseline_metrics()


func _ready() -> void:
	_ready_started_at_usec = Time.get_ticks_usec()
	_set_load_baseline_metric("scene_open_ms", _elapsed_ms_between(_scene_constructed_at_usec, _ready_started_at_usec))
	super._ready()
	if is_queued_for_deletion():
		return
	_set_load_baseline_metric("ready_total_ms", _elapsed_ms_since(_ready_started_at_usec))
	_setup_semantic_save_controls()
	_update_semantic_save_controls()
	_update_load_baseline_runtime_metrics()


func _process(delta: float) -> void:
	super._process(delta)
	if _visual_build_prepared and not _visual_build_complete:
		_update_visual_build_readiness_state()
	_update_load_baseline_runtime_metrics()


func _read_demo_map() -> void:
	_read_demo_map_started_at_usec = Time.get_ticks_usec()
	var bootstrap_result: int = _bootstrap_world_source()
	match bootstrap_result:
		BootstrapWorldSourceResult.LEGACY_RANDOM:
			match map_bootstrap_mode:
				MapBootstrapMode.LEGACY_RANDOM_ONLY:
					_read_demo_map_from_legacy_random()
				MapBootstrapMode.SEMANTIC_PREWARM_FIRST:
					_read_demo_map_from_semantic_prewarm_first()
				MapBootstrapMode.SEMANTIC_PREWARM_REQUIRED:
					_read_demo_map_from_semantic_prewarm_required()
				_:
					push_warning("RandomGovernancePlaytest received unknown map_bootstrap_mode=%d, fallback to legacy random path." % map_bootstrap_mode)
					_read_demo_map_from_legacy_random()
		BootstrapWorldSourceResult.SEMANTIC_READY:
			_read_demo_map_from_semantic_ready_store()
		BootstrapWorldSourceResult.TRANSITIONED_TO_LOADING:
			return
		BootstrapWorldSourceResult.FAILED:
			push_error(_last_bootstrap_error)
			return
		_:
			push_error("RandomGovernancePlaytest received unknown bootstrap world source result=%d" % bootstrap_result)
			return


func _read_demo_map_from_legacy_random() -> void:
	_set_load_baseline_metric("bootstrap_source", LOAD_BASELINE_SOURCE_LEGACY_RANDOM)
	_teardown_semantic_runtime_view()
	_generate_random_governance_map()
	if _generated_map_data == null:
		push_error("RandomGovernancePlaytest failed to generate map data.")
		return

	var legacy_context: Dictionary = _compatibility_adapter.build_legacy_context(_generated_map_data)
	_apply_legacy_context(legacy_context, true)
	_set_load_baseline_metric("read_demo_map_ms", _elapsed_ms_since(_read_demo_map_started_at_usec))
	_mark_load_baseline_immediately_ready()


func _read_demo_map_from_semantic_prewarm_first() -> void:
	push_warning("RandomGovernancePlaytest semantic prewarm bootstrap requested a legacy fallback after phase 2 bootstrap checks.")
	_read_demo_map_from_legacy_random()


func _read_demo_map_from_semantic_prewarm_required() -> void:
	push_warning("RandomGovernancePlaytest semantic prewarm required mode reached a temporary legacy fallback because phase 3 semantic gameplay bootstrap is not implemented yet.")
	_read_demo_map_from_legacy_random()


func _read_demo_map_from_semantic_ready_store() -> void:
	_sync_random_map_seed_from_semantic_identity()
	var runtime_chunks: Dictionary = _pending_restored_runtime_chunks.duplicate(true)
	var build_context_started_usec: int = Time.get_ticks_usec()
	var semantic_context: Dictionary = _resolve_semantic_governance_context(runtime_chunks)
	_set_load_baseline_metric("build_bootstrap_context_ms", _elapsed_ms_since(build_context_started_usec))
	if semantic_context.is_empty():
		_handle_semantic_bootstrap_failure("RandomGovernancePlaytest failed to build semantic governance context.")
		return
	var apply_context_started_usec: int = Time.get_ticks_usec()
	if not _apply_governance_bootstrap_context(semantic_context, false, true, runtime_chunks):
		_set_load_baseline_metric("apply_bootstrap_context_ms", _elapsed_ms_since(apply_context_started_usec))
		_handle_semantic_bootstrap_failure("RandomGovernancePlaytest failed to apply semantic governance context.")
		return
	_set_load_baseline_metric("apply_bootstrap_context_ms", _elapsed_ms_since(apply_context_started_usec))
	var restore_camera_started_usec: int = Time.get_ticks_usec()
	_apply_pending_saved_camera_state()
	_set_load_baseline_metric("restore_camera_ms", _elapsed_ms_since(restore_camera_started_usec))
	_apply_pending_restored_gameplay_state()
	_set_load_baseline_metric("read_demo_map_ms", _elapsed_ms_since(_read_demo_map_started_at_usec))
	_update_load_baseline_runtime_metrics()
	_update_semantic_save_controls()


func _resolve_semantic_governance_context(runtime_chunks: Dictionary = {}) -> Dictionary:
	var restored_cache_context: Dictionary = _try_restore_governance_bootstrap_context_from_cache()
	var restored_from_saved_world: bool = String(_load_baseline_metrics.get("bootstrap_source", LOAD_BASELINE_SOURCE_UNKNOWN)) == LOAD_BASELINE_SOURCE_RESTORED_SAVED_WORLD
	if not restored_cache_context.is_empty():
		_last_bootstrap_restore_mode = BOOTSTRAP_RESTORE_MODE_CACHE
		_set_load_baseline_metric("bootstrap_restore_mode", _last_bootstrap_restore_mode)
		_set_load_baseline_metric("bootstrap_context_build_count", _semantic_bootstrap_build_count)
		if restored_from_saved_world:
			_append_event_log("restore from semantic + bootstrap cache")
			print("restore from semantic + bootstrap cache")
		return restored_cache_context

	_last_bootstrap_restore_mode = BOOTSTRAP_RESTORE_MODE_REBUILD
	_set_load_baseline_metric("bootstrap_restore_mode", _last_bootstrap_restore_mode)
	if restored_from_saved_world:
		_append_event_log("restore from semantic only, rebuild bootstrap")
		print("restore from semantic only, rebuild bootstrap")
	var rebuilt_context: Dictionary = _build_semantic_governance_context(runtime_chunks)
	_set_load_baseline_metric("bootstrap_context_build_count", _semantic_bootstrap_build_count)
	return rebuilt_context


func _try_restore_governance_bootstrap_context_from_cache() -> Dictionary:
	if _pending_restored_governance_bootstrap_cache.is_empty():
		return {}
	if _bootstrapped_semantic_identity == null:
		return {}
	return WorldSemanticMapSaveScript.bootstrap_cache_dto_to_context(
		_pending_restored_governance_bootstrap_cache,
		_bootstrapped_semantic_identity,
		_get_active_governance_bootstrap_tile_rect()
	)


func _build_semantic_governance_context(runtime_chunks: Dictionary = {}) -> Dictionary:
	if _bootstrapped_semantic_identity == null:
		push_error("RandomGovernancePlaytest semantic governance context requires bootstrapped identity")
		return {}
	if _bootstrapped_semantic_store == null:
		push_error("RandomGovernancePlaytest semantic governance context requires bootstrapped semantic store")
		return {}

	_semantic_bootstrap_build_count += 1
	var bootstrap_context: Dictionary = _semantic_governance_adapter.build_governance_bootstrap_context(
		_bootstrapped_semantic_identity,
		_bootstrapped_semantic_store,
		_get_active_governance_bootstrap_tile_rect(),
		runtime_chunks
	)
	if bootstrap_context.is_empty():
		push_error("RandomGovernancePlaytest semantic governance adapter failed: %s" % _semantic_governance_adapter.last_error)
	return bootstrap_context


func get_semantic_runtime_view():
	return _semantic_runtime_view


func get_load_baseline_metrics_snapshot() -> Dictionary:
	var snapshot: Dictionary = _load_baseline_metrics.duplicate(true)
	snapshot["current_elapsed_ms"] = _elapsed_ms_since(_scene_constructed_at_usec)
	snapshot["metrics_complete"] = _load_baseline_metrics_complete
	snapshot["first_playable_view_recorded"] = _load_baseline_playable_recorded
	snapshot["visual_queue_drained_recorded"] = _load_baseline_visual_queue_drained_recorded

	if _semantic_runtime_view != null:
		var runtime_snapshot: Dictionary = _semantic_runtime_view.get_debug_snapshot()
		snapshot["runtime_view_queue_size"] = int(runtime_snapshot.get("queue_size", -1))
		snapshot["runtime_view_rendered_chunk_count"] = int(runtime_snapshot.get("rendered_chunk_count", 0))
	else:
		snapshot["runtime_view_queue_size"] = -1
		snapshot["runtime_view_rendered_chunk_count"] = 0

	return snapshot


func is_load_baseline_metrics_complete() -> bool:
	return _load_baseline_metrics_complete


func get_last_bootstrap_restore_mode() -> String:
	return _last_bootstrap_restore_mode


func get_semantic_bootstrap_build_count() -> int:
	return _semantic_bootstrap_build_count


func get_active_governance_bootstrap_tile_rect() -> Rect2i:
	return _get_active_governance_bootstrap_tile_rect()


func prepare_full_visual_build() -> void:
	_visual_build_prepared = true
	_visual_build_complete = false
	_visual_build_stage_name = "Preparing gameplay scene"
	_visual_build_done_units = 0
	_visual_build_total_units = 1
	_entry_visuals_finalized = false

	if _semantic_runtime_view == null:
		_finalize_minimum_entry_visual_build()
		_visual_build_complete = true
		_visual_build_done_units = 1
		_visual_build_stage_name = "Gameplay visuals ready"
		return

	_semantic_runtime_view.request_visual_coverage_for_camera_position(main_camera.global_position)
	_semantic_runtime_view.refresh_now()
	_update_visual_build_readiness_state()


func process_full_visual_build_budget(max_units: int) -> bool:
	if not _visual_build_prepared:
		prepare_full_visual_build()
	if _visual_build_complete:
		return false
	if _semantic_runtime_view == null:
		_visual_build_complete = true
		_visual_build_done_units = _visual_build_total_units
		_visual_build_stage_name = "Gameplay visuals ready"
		return false

	_visual_build_stage_name = "Building initial semantic view"
	_semantic_runtime_view.request_visual_coverage_for_camera_position(main_camera.global_position)
	var chunk_budget: int = max(max_units, 1)
	_semantic_runtime_view.flush_runtime_visual_queue(chunk_budget)
	_update_visual_build_readiness_state()
	return not _visual_build_complete


func finalize_full_visual_build() -> void:
	if not _visual_build_prepared:
		prepare_full_visual_build()
	if _semantic_runtime_view != null:
		_semantic_runtime_view.refresh_now()
	_finalize_minimum_entry_visual_build()
	_update_visual_build_metrics()
	_visual_build_complete = true
	_visual_build_done_units = _visual_build_total_units
	_visual_build_stage_name = "Gameplay visuals ready"


func is_full_visual_build_complete() -> bool:
	return _visual_build_complete


func is_minimum_entry_visual_ready() -> bool:
	if _semantic_runtime_view == null:
		return true
	if main_camera == null:
		return false
	return _semantic_runtime_view.is_minimum_entry_visual_ready(main_camera.global_position)


func is_background_visual_build_complete() -> bool:
	if _semantic_runtime_view == null:
		return true
	return _semantic_runtime_view.is_background_visual_build_complete()


func finalize_minimum_entry_visual_build() -> void:
	_finalize_minimum_entry_visual_build()


func get_visual_build_stage_name() -> String:
	return _visual_build_stage_name


func get_visual_build_done_units() -> int:
	return _visual_build_done_units


func get_visual_build_total_units() -> int:
	return _visual_build_total_units


func _update_visual_build_metrics() -> void:
	if _semantic_runtime_view == null:
		_visual_build_total_units = 1
		_visual_build_done_units = 1 if _visual_build_complete else 0
		return

	var snapshot: Dictionary = _semantic_runtime_view.get_debug_snapshot()
	var rendered_chunk_count: int = int(snapshot.get("rendered_chunk_count", 0))
	var queue_size: int = int(snapshot.get("queue_size", 0))
	var total_units: int = max(rendered_chunk_count + queue_size, 1)
	var done_units: int = max(total_units - queue_size, 0)
	_visual_build_total_units = total_units
	_visual_build_done_units = done_units


func _update_visual_build_readiness_state() -> void:
	_update_visual_build_metrics()
	if is_minimum_entry_visual_ready():
		_finalize_minimum_entry_visual_build()

	if is_background_visual_build_complete():
		_visual_build_complete = true
		_visual_build_done_units = _visual_build_total_units
		_visual_build_stage_name = "Gameplay visuals ready"
		return

	_visual_build_complete = false
	if is_minimum_entry_visual_ready():
		_visual_build_stage_name = "Entry view ready, background fill"
	else:
		_visual_build_stage_name = "Building initial semantic view"


func _finalize_minimum_entry_visual_build() -> void:
	if _entry_visuals_finalized:
		return
	_update_placement_overlay()
	_update_economy_ui()
	_update_stage14_hud()
	_entry_visuals_finalized = true


func _teardown_semantic_runtime_view() -> void:
	_semantic_gameplay_query_bridge = null
	if _semantic_runtime_view == null:
		return
	_semantic_runtime_view.teardown(true, false)
	_semantic_runtime_view.queue_free()
	_semantic_runtime_view = null


func _build_semantic_runtime_view(runtime_chunks: Dictionary = {}):
	_teardown_semantic_runtime_view()
	if not enable_semantic_runtime_view:
		return null
	if _bootstrapped_semantic_identity == null or _bootstrapped_semantic_store == null:
		push_error("RandomGovernancePlaytest semantic runtime view requires a bootstrapped identity and store")
		return null
	if ground_layer == null or resource_layer == null or transition_layer == null or main_camera == null:
		push_error("RandomGovernancePlaytest semantic runtime view requires map layers and camera")
		return null

	var runtime_view := WorldSemanticRuntimeViewScript.new()
	add_child(runtime_view)
	runtime_view.render_padding_cells = semantic_runtime_render_padding_cells
	runtime_view.runtime_chunk_preload_margin = semantic_runtime_preload_margin
	runtime_view.runtime_chunk_keep_margin = semantic_runtime_keep_margin
	runtime_view.runtime_visual_chunks_per_frame = semantic_runtime_visual_chunks_per_frame
	runtime_view.camera_coverage_safety_margin = semantic_runtime_camera_coverage_safety_margin
	runtime_view.unload_idle_delay_seconds = semantic_runtime_unload_idle_delay_seconds

	if not runtime_view.setup(
		_bootstrapped_semantic_identity,
		_bootstrapped_semantic_store,
		ground_layer,
		resource_layer,
		transition_layer,
		main_camera,
		runtime_chunks
	):
		push_error("RandomGovernancePlaytest semantic runtime view setup failed: %s" % runtime_view.last_error)
		runtime_view.queue_free()
		return null

	_semantic_runtime_view = runtime_view
	return _semantic_runtime_view


func _handle_semantic_bootstrap_failure(reason: String) -> void:
	if map_bootstrap_mode == MapBootstrapMode.SEMANTIC_PREWARM_FIRST:
		push_warning(reason + " Fallback to legacy random path.")
		_read_demo_map_from_legacy_random()
		return
	push_error(reason)


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
	_teardown_semantic_runtime_view()
	_generate_random_governance_map()
	if _generated_map_data == null:
		return

	var legacy_context: Dictionary = _compatibility_adapter.build_legacy_context(_generated_map_data)
	_apply_legacy_context(legacy_context, true)
	_update_placement_overlay()
	_update_economy_ui()
	_update_stage14_hud()


func _apply_legacy_context(legacy_context: Dictionary, force_flush_chunk_runtime_view: bool) -> void:
	var legacy_bootstrap_context: Dictionary = legacy_context.duplicate(true)
	legacy_bootstrap_context["used_rect"] = Rect2i(Vector2i.ZERO, random_map_size)
	legacy_bootstrap_context["cell_offset"] = Vector2i.ZERO
	legacy_bootstrap_context["ground_cells_read"] = _count_base_cells()
	legacy_bootstrap_context["resource_cells_read"] = _count_resource_cells()
	legacy_bootstrap_context["terrain_counts"] = _build_terrain_counts_from_grid(legacy_bootstrap_context.get("grid", null))
	_apply_governance_bootstrap_context(legacy_bootstrap_context, force_flush_chunk_runtime_view, false)


func _apply_governance_bootstrap_context(
	bootstrap_context: Dictionary,
	force_flush_chunk_runtime_view: bool,
	use_semantic_runtime_view: bool,
	runtime_chunks: Dictionary = {}
) -> bool:
	if bootstrap_context.is_empty():
		push_error("RandomGovernancePlaytest bootstrap context is empty")
		return false

	grid = bootstrap_context.get("grid", null)
	if grid == null:
		push_error("RandomGovernancePlaytest bootstrap context is missing grid")
		return false

	resource_regions = bootstrap_context.get("resource_regions", {})
	farmable_regions = bootstrap_context.get("farmable_regions", [])
	var used_rect: Rect2i = bootstrap_context.get("used_rect", Rect2i(Vector2i.ZERO, random_map_size))
	var cell_offset: Vector2i = bootstrap_context.get("cell_offset", used_rect.position)
	var ground_cells_read: int = int(bootstrap_context.get("ground_cells_read", used_rect.size.x * used_rect.size.y))
	var resource_cells_read: int = int(bootstrap_context.get("resource_cells_read", 0))
	var terrain_counts: Dictionary = bootstrap_context.get("terrain_counts", _build_terrain_counts_from_grid(grid))
	map_read_result = {
		"grid": grid,
		"used_rect": used_rect,
		"cell_offset": cell_offset,
		"ground_cells_read": ground_cells_read,
		"resource_cells_read": resource_cells_read,
		"terrain_counts": terrain_counts,
	}

	if use_semantic_runtime_view:
		_clear_map_visual_layers()
	if clear_decor_layer_before_generate and decor_layer != null:
		decor_layer.clear()

	var scanner := ResourceRegionScannerScript.new()
	_print_map_summary(map_read_result, resource_regions, scanner)
	_spawn_initial_buildings()
	if use_semantic_runtime_view:
		if enable_semantic_runtime_view and _build_semantic_runtime_view(runtime_chunks) == null:
			return false
	else:
		_setup_chunk_runtime_view(force_flush_chunk_runtime_view)
	_refresh_semantic_gameplay_query_bridge()
	_setup_placement_controller()
	_focus_camera_on_castle()
	return true


func _refresh_semantic_gameplay_query_bridge() -> void:
	_semantic_gameplay_query_bridge = null
	if _bootstrapped_semantic_identity == null or _bootstrapped_semantic_store == null:
		return
	var cell_offset: Vector2i = map_read_result.get("cell_offset", Vector2i.ZERO)
	var query_bridge = WorldSemanticGameplayQueryBridgeScript.new()
	if not query_bridge.setup(_bootstrapped_semantic_identity, _bootstrapped_semantic_store, cell_offset):
		push_error("RandomGovernancePlaytest semantic gameplay query bridge setup failed: %s" % query_bridge.last_error)
		return
	_semantic_gameplay_query_bridge = query_bridge


func _setup_placement_controller() -> void:
	placement_controller = BuildingPlacementControllerScript.new()
	placement_controller.setup(
		grid,
		resource_regions,
		farmable_regions,
		occupied_cells,
		_get_castle_cell(),
		resource_inventory,
		_semantic_gameplay_query_bridge
	)


func _get_regions_by_id() -> Dictionary:
	var base_regions_by_id: Dictionary = super._get_regions_by_id()
	if _semantic_gameplay_query_bridge == null:
		return base_regions_by_id
	return _semantic_gameplay_query_bridge.build_regions_by_id_for_buildings(base_regions_by_id, initial_buildings)


func _bootstrap_world_source() -> int:
	_bootstrapped_semantic_store = null
	_bootstrapped_semantic_identity = null
	_last_bootstrap_error = ""
	_last_bootstrap_restore_mode = BOOTSTRAP_RESTORE_MODE_NONE
	_semantic_bootstrap_build_count = 0
	_warned_invalid_compact_bootstrap_rect = false
	_clear_pending_saved_world_state()

	if map_bootstrap_mode == MapBootstrapMode.LEGACY_RANDOM_ONLY:
		return BootstrapWorldSourceResult.LEGACY_RANDOM

	if not has_node("/root/WorldSession"):
		_last_bootstrap_error = "WorldSession autoload is missing"
		if map_bootstrap_mode == MapBootstrapMode.SEMANTIC_PREWARM_FIRST:
			push_warning(_last_bootstrap_error + "; fallback to legacy random path.")
			return BootstrapWorldSourceResult.LEGACY_RANDOM
		return BootstrapWorldSourceResult.FAILED

	var session = get_node("/root/WorldSession")
	var ready_store = session.get_ready_semantic_store()
	if ready_store != null:
		_set_load_baseline_metric("bootstrap_source", LOAD_BASELINE_SOURCE_SESSION_READY_STORE)
		_bootstrapped_semantic_store = ready_store
		_bootstrapped_semantic_identity = session.identity
		return BootstrapWorldSourceResult.SEMANTIC_READY
	if _try_restore_saved_world(session):
		return BootstrapWorldSourceResult.SEMANTIC_READY

	if _bootstrap_via_loading_scene():
		_set_load_baseline_metric("bootstrap_source", LOAD_BASELINE_SOURCE_LOADING_TRANSITION_REQUESTED)
		_set_load_baseline_metric("read_demo_map_ms", _elapsed_ms_since(_read_demo_map_started_at_usec))
		return BootstrapWorldSourceResult.TRANSITIONED_TO_LOADING

	_last_bootstrap_error = "Could not start semantic loading scene: %s" % semantic_loading_scene_path
	if map_bootstrap_mode == MapBootstrapMode.SEMANTIC_PREWARM_FIRST:
		push_warning(_last_bootstrap_error + "; fallback to legacy random path.")
		return BootstrapWorldSourceResult.LEGACY_RANDOM
	return BootstrapWorldSourceResult.FAILED


func _bootstrap_via_loading_scene() -> bool:
	if semantic_loading_scene_path.is_empty():
		return false

	var loading_scene_resource: Variant = load(semantic_loading_scene_path)
	if loading_scene_resource == null or not (loading_scene_resource is PackedScene):
		return false

	var gameplay_scene_resource: Variant = load(SELF_SCENE_PATH)
	if gameplay_scene_resource == null or not (gameplay_scene_resource is PackedScene):
		return false

	var loading_instance: Node = (loading_scene_resource as PackedScene).instantiate()
	if loading_instance == null:
		return false

	loading_instance.set("world_seed", random_map_seed)
	loading_instance.set("auto_start", true)
	loading_instance.set("auto_transition_to_gameplay", true)
	loading_instance.set("auto_free_on_transition", true)
	loading_instance.set("gameplay_scene", gameplay_scene_resource)
	loading_instance.set("next_gameplay_semantic_world_save_path", semantic_world_save_path)

	if get_parent() != null:
		get_parent().call_deferred("add_child", loading_instance)
	else:
		get_tree().root.call_deferred("add_child", loading_instance)

	call_deferred("queue_free")
	return true


func _setup_semantic_save_controls() -> void:
	if return_castle_button != null and not return_castle_button.pressed.is_connected(_on_return_castle_pressed):
		return_castle_button.pressed.connect(_on_return_castle_pressed)
	if save_map_button != null and not save_map_button.pressed.is_connected(_on_save_map_pressed):
		save_map_button.pressed.connect(_on_save_map_pressed)
	if reset_map_button != null and not reset_map_button.pressed.is_connected(_on_reset_map_pressed):
		reset_map_button.pressed.connect(_on_reset_map_pressed)


func _update_semantic_save_controls() -> void:
	var controls_visible: bool = _should_show_semantic_save_controls()
	if return_castle_button != null:
		return_castle_button.visible = controls_visible
		return_castle_button.disabled = not controls_visible
	if save_map_button != null:
		save_map_button.visible = controls_visible
		save_map_button.disabled = not controls_visible
	if reset_map_button != null:
		reset_map_button.visible = controls_visible
		reset_map_button.disabled = not controls_visible


func _should_show_semantic_save_controls() -> bool:
	if map_bootstrap_mode == MapBootstrapMode.LEGACY_RANDOM_ONLY:
		return false
	return _bootstrapped_semantic_identity != null and _bootstrapped_semantic_store != null


func _clear_pending_saved_world_state() -> void:
	_pending_restored_runtime_chunks.clear()
	_pending_restored_governance_bootstrap_cache.clear()
	_pending_restored_gameplay_state.clear()
	_pending_restored_camera_cell = Vector2i.ZERO
	_pending_restored_camera_zoom = 1.0
	_has_pending_restored_camera_state = false


func _try_restore_saved_world(session) -> bool:
	if not enable_semantic_world_restore:
		return false
	if session == null or session.state != WorldSessionScript.WorldSessionState.EMPTY:
		return false
	if not WorldSemanticMapSaveScript.has_save(semantic_world_save_path):
		return false

	_set_load_baseline_metric("save_file_bytes", _get_file_size_bytes(semantic_world_save_path))
	var load_world_started_usec: int = Time.get_ticks_usec()
	var loaded_world: Dictionary = WorldSemanticMapSaveScript.load_world(semantic_world_save_path)
	_set_load_baseline_metric("load_world_ms", _elapsed_ms_since(load_world_started_usec))
	if loaded_world.is_empty():
		return false

	var restored_identity: Variant = loaded_world.get("identity", null)
	var restored_store: Variant = loaded_world.get("semantic_store", null)
	var restore_ready_started_usec: int = Time.get_ticks_usec()
	var restore_ok: bool = session.restore_ready_world(restored_identity, restored_store)
	_set_load_baseline_metric("restore_ready_world_ms", _elapsed_ms_since(restore_ready_started_usec))
	if not restore_ok:
		return false

	_set_load_baseline_metric("bootstrap_source", LOAD_BASELINE_SOURCE_RESTORED_SAVED_WORLD)
	_bootstrapped_semantic_identity = loaded_world["identity"]
	_bootstrapped_semantic_store = loaded_world["semantic_store"]
	_pending_restored_runtime_chunks = (loaded_world.get("runtime_chunks", {}) as Dictionary).duplicate(true)
	_pending_restored_governance_bootstrap_cache = (loaded_world.get("governance_bootstrap_cache", {}) as Dictionary).duplicate(true)
	_pending_restored_gameplay_state = (loaded_world.get("gameplay_state", {}) as Dictionary).duplicate(true)
	_pending_restored_camera_cell = loaded_world.get("camera_cell", Vector2i.ZERO)
	_pending_restored_camera_zoom = float(loaded_world.get("camera_zoom", 1.0))
	_has_pending_restored_camera_state = true
	return true


func _apply_pending_saved_camera_state() -> void:
	if not _has_pending_restored_camera_state:
		return
	if main_camera == null or ground_layer == null:
		return

	var restored_zoom: float = clampf(_pending_restored_camera_zoom, CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)
	main_camera.zoom = Vector2(restored_zoom, restored_zoom)
	main_camera.global_position = ground_layer.to_global(ground_layer.map_to_local(_pending_restored_camera_cell))
	if _semantic_runtime_view != null:
		_semantic_runtime_view.request_visual_coverage_for_camera_position(main_camera.global_position)
		_semantic_runtime_view.refresh_now()
		_semantic_runtime_view.flush_runtime_visual_queue(maxi(semantic_runtime_visual_chunks_per_frame, 32))
	_has_pending_restored_camera_state = false
	_append_event_log("已恢复保存的语义地图。")


func _apply_pending_restored_gameplay_state() -> void:
	if _pending_restored_gameplay_state.is_empty():
		return
	var restored: bool = _apply_restored_gameplay_state(_pending_restored_gameplay_state)
	_pending_restored_gameplay_state.clear()
	if restored:
		_append_event_log("已恢复保存的游戏进度。")
	else:
		push_warning("保存的完整玩法状态无效，已保留当前默认玩法状态。")


func _apply_restored_gameplay_state(gameplay_state: Dictionary) -> bool:
	if gameplay_state.is_empty():
		return false
	if int(gameplay_state.get("gameplay_state_version", 0)) != WorldSemanticMapSaveScript.GAMEPLAY_STATE_VERSION:
		return false

	var restored_buildings: Array = _build_restored_buildings_from_gameplay_state(gameplay_state)
	var restored_castle_migration_message: String = _migrate_restored_castle_footprint_if_needed(restored_buildings)
	_clear_initial_building_nodes()
	_clear_villager_nodes()
	occupied_cells.clear()
	initial_buildings = restored_buildings
	for building in initial_buildings:
		if building == null:
			continue
		_register_occupied_cells_for_building(building)
		_instantiate_building_visual(building)
		_clear_building_footprint_resource_visuals(building)

	_restore_resource_inventory_from_gameplay_state(gameplay_state)
	_restore_governance_state_from_gameplay_state(gameplay_state)
	_restore_game_clock_from_gameplay_state(gameplay_state)
	_restore_runtime_reports_from_gameplay_state(gameplay_state)
	_restore_event_log_from_gameplay_state(gameplay_state)
	if not restored_castle_migration_message.is_empty():
		_append_event_log(restored_castle_migration_message)
	_restore_auxiliary_systems_from_gameplay_state(gameplay_state)
	_restore_resource_depletion_state_from_gameplay_state(gameplay_state)
	_refresh_semantic_gameplay_query_bridge()
	_rebind_restored_resource_buildings()
	_setup_placement_controller()
	_restore_worker_assignments_from_gameplay_state(gameplay_state)
	_restore_worker_resource_tasks_from_gameplay_state(gameplay_state)
	_refresh_building_hover_visuals()
	_update_placement_overlay()
	_update_economy_ui()
	_update_stage14_hud()
	_update_worker_control_ui()
	return true


func _build_restored_buildings_from_gameplay_state(gameplay_state: Dictionary) -> Array:
	var restored_buildings: Array = []
	var buildings_variant: Variant = gameplay_state.get("buildings", [])
	if typeof(buildings_variant) != TYPE_ARRAY:
		return restored_buildings
	var building_save_data_array: Array = buildings_variant
	for building_save_data_variant in building_save_data_array:
		if typeof(building_save_data_variant) != TYPE_DICTIONARY:
			continue
		var building_save_data: Dictionary = building_save_data_variant
		var restored_building: BuildingData = BuildingDataScript.from_save_data(building_save_data)
		if restored_building == null:
			continue
		restored_buildings.append(restored_building)
	return restored_buildings


func _migrate_restored_castle_footprint_if_needed(restored_buildings: Array) -> String:
	if grid == null:
		return ""
	var blocked_cells: Dictionary = _build_restored_non_castle_occupied_cells(restored_buildings)
	for building_variant in restored_buildings:
		if not (building_variant is RefCounted):
			continue
		var building: RefCounted = building_variant
		if int(building.building_type) != MapTypes.BuildingType.TOWN_CENTER:
			continue
		if BuildingFootprintRulesScript.is_castle_footprint_valid_and_unblocked(grid, building.position, blocked_cells):
			return ""
		var migrated_cell: Vector2i = BuildingFootprintRulesScript.find_nearest_valid_castle_cell_avoiding(grid, blocked_cells, building.position)
		if migrated_cell.x < 0 or migrated_cell.y < 0:
			push_warning("旧存档中的城堡位置不满足 9x9 占地规则，且当前地图没有找到可迁移位置。")
			return ""
		var previous_cell: Vector2i = building.position
		building.position = migrated_cell
		var message: String = "旧存档中的城堡位置不满足 9x9 占地规则，已从 %s 自动迁移到 %s。" % [str(previous_cell), str(migrated_cell)]
		push_warning(message)
		return message
	return ""


func _build_restored_non_castle_occupied_cells(restored_buildings: Array) -> Dictionary:
	var blocked_cells: Dictionary = {}
	for building_variant in restored_buildings:
		if not (building_variant is RefCounted):
			continue
		var building: RefCounted = building_variant
		if int(building.building_type) == MapTypes.BuildingType.TOWN_CENTER:
			continue
		BuildingFootprintRulesScript.register_building_footprint(blocked_cells, int(building.building_type), building.position)
	return blocked_cells


func _rebind_restored_resource_buildings() -> void:
	if _semantic_gameplay_query_bridge == null:
		return
	var base_regions_by_id: Dictionary = super._get_regions_by_id()
	for building_variant in initial_buildings:
		if not (building_variant is RefCounted):
			continue
		var building: RefCounted = building_variant
		var required_terrain: int = _get_required_resource_terrain_for_building(int(building.building_type))
		if required_terrain < 0:
			continue
		if _get_resource_region_for_building(building, base_regions_by_id) != null:
			continue
		var rebound_region: RefCounted = _semantic_gameplay_query_bridge.find_resource_region_for_building_cell(building.position, required_terrain)
		if rebound_region == null:
			continue
		building.linked_region_id = int(rebound_region.get("region_id"))
		_sync_building_node_linked_region_meta(building)


func _sync_building_node_linked_region_meta(building: RefCounted) -> void:
	var building_node: Node2D = _find_building_node(building)
	if building_node == null or not is_instance_valid(building_node):
		return
	building_node.set_meta("linked_region_id", building.linked_region_id)


func _restore_resource_inventory_from_gameplay_state(gameplay_state: Dictionary) -> void:
	if resource_inventory == null or not resource_inventory.has_method("restore_from_save_data"):
		return
	var save_data: Dictionary = _get_gameplay_state_dictionary(gameplay_state, "resource_inventory")
	if save_data.is_empty():
		return
	resource_inventory.call("restore_from_save_data", save_data)


func _restore_governance_state_from_gameplay_state(gameplay_state: Dictionary) -> void:
	if governance_state == null or not governance_state.has_method("restore_from_save_data"):
		return
	var save_data: Dictionary = _get_gameplay_state_dictionary(gameplay_state, "governance_state")
	if save_data.is_empty():
		return
	governance_state.call("restore_from_save_data", save_data)


func _restore_game_clock_from_gameplay_state(gameplay_state: Dictionary) -> void:
	if game_clock == null or not game_clock.has_method("restore_from_save_data"):
		return
	var save_data: Dictionary = _get_gameplay_state_dictionary(gameplay_state, "game_clock")
	if save_data.is_empty():
		return
	game_clock.call("restore_from_save_data", save_data)


func _restore_resource_depletion_state_from_gameplay_state(gameplay_state: Dictionary) -> void:
	if resource_depletion_state == null:
		resource_depletion_state = ResourceDepletionStateScript.new()
	if resource_depletion_state == null or not resource_depletion_state.has_method("load_save_data"):
		return

	var save_data: Dictionary = _get_gameplay_state_dictionary(gameplay_state, "resource_depletion_state")
	resource_depletion_state.call("load_save_data", save_data)
	_apply_restored_resource_depletion_to_world()


func _restore_runtime_reports_from_gameplay_state(gameplay_state: Dictionary) -> void:
	last_minute_delta = _get_gameplay_state_dictionary(gameplay_state, "last_minute_delta")
	last_tax_message = str(gameplay_state.get("last_tax_message", ""))
	last_happiness_message = str(gameplay_state.get("last_happiness_message", ""))
	last_happiness_report = _get_gameplay_state_dictionary(gameplay_state, "last_happiness_report")
	last_riot_message = str(gameplay_state.get("last_riot_message", ""))
	last_riot_report = _get_gameplay_state_dictionary(gameplay_state, "last_riot_report")
	last_victory_defeat_report = _get_gameplay_state_dictionary(gameplay_state, "last_victory_defeat_report")
	last_daily_happiness_delta = float(gameplay_state.get("last_daily_happiness_delta", 0.0))
	last_tax_day_index = int(gameplay_state.get("last_tax_day_index", -1))


func _restore_event_log_from_gameplay_state(gameplay_state: Dictionary) -> void:
	event_log_messages.clear()
	var messages_variant: Variant = gameplay_state.get("event_log_messages", [])
	if typeof(messages_variant) != TYPE_ARRAY:
		return
	var messages: Array = messages_variant
	for message_variant in messages:
		var message: String = str(message_variant)
		if message.is_empty():
			continue
		event_log_messages.append(message)
		if event_log_messages.size() >= 3:
			break


func _restore_auxiliary_systems_from_gameplay_state(gameplay_state: Dictionary) -> void:
	if happiness_system != null and happiness_system.has_method("set_stable_day_count"):
		happiness_system.call("set_stable_day_count", int(gameplay_state.get("happiness_stable_day_count", 0)))
	if victory_defeat_system == null:
		return
	victory_defeat_system.set("consecutive_riot_days", max(int(gameplay_state.get("victory_consecutive_riot_days", 0)), 0))
	victory_defeat_system.set("completed_day_index", max(int(gameplay_state.get("victory_completed_day_index", 0)), 0))
	victory_defeat_system.set("final_report", last_victory_defeat_report.duplicate(true))
	if last_victory_defeat_report.is_empty():
		victory_defeat_system.set("result_type", &"none")
		victory_defeat_system.set("reason_id", &"none")
		victory_defeat_system.set("reason_text", "尚未结算")
		return
	victory_defeat_system.set("result_type", StringName(str(last_victory_defeat_report.get("result_type", &"none"))))
	victory_defeat_system.set("reason_id", StringName(str(last_victory_defeat_report.get("reason_id", &"none"))))
	victory_defeat_system.set("reason_text", str(last_victory_defeat_report.get("reason_text", "")))


func _restore_worker_assignments_from_gameplay_state(gameplay_state: Dictionary) -> void:
	_reconcile_worker_assignments_to_population()
	_rebuild_villager_population_from_gameplay_state(gameplay_state)


func _rebuild_villager_population_from_gameplay_state(gameplay_state: Dictionary) -> void:
	_clear_villager_nodes()

	var home_building := _find_home_building()
	if home_building == null:
		push_warning("No castle or house available for villager population rebuild.")
		return

	var home_position := _get_building_route_point_for_root(home_building, characters_root, HOME_EXIT_OFFSET)
	var fallback_wander_bounds := _get_idle_villager_wander_bounds()

	var worker_index := 0
	for building in _get_production_buildings():
		if building == null:
			continue
		var worker_count := int(building.call("get_worker_count")) if building.has_method("get_worker_count") else 0
		if worker_count <= 0:
			continue
		var work_position := _get_building_route_point_for_root(building, characters_root, WORK_ENTRY_OFFSET)
		for local_index in range(worker_count):
			_spawn_villager_route(worker_index, home_position, work_position, building)
			worker_index += 1

	var assigned_workers := _get_assigned_worker_total()
	var idle_population: int = max(int(governance_state.population) - assigned_workers, 0) if governance_state != null else 0
	var restored_idle_origins: Array = _get_idle_villager_origin_save_data_from_gameplay_state(gameplay_state)
	if restored_idle_origins.is_empty() and idle_population > 0:
		restored_idle_origins = _infer_idle_villager_origins_for_legacy_gameplay_state(idle_population)
	for idle_index in range(idle_population):
		var villager_index: int = worker_index + idle_index
		var origin_data: Dictionary = restored_idle_origins[idle_index] if idle_index < restored_idle_origins.size() else {}
		_spawn_idle_villager_from_origin_data(villager_index, origin_data, fallback_wander_bounds)

	_rebalance_villager_assignments()


func _get_idle_villager_origin_save_data_from_gameplay_state(gameplay_state: Dictionary) -> Array:
	var origins_variant: Variant = gameplay_state.get("idle_villager_origins", [])
	if typeof(origins_variant) != TYPE_ARRAY:
		return []
	var origins: Array = []
	for origin_variant in origins_variant:
		if typeof(origin_variant) != TYPE_DICTIONARY:
			continue
		var origin_data: Dictionary = origin_variant
		origins.append(origin_data.duplicate(true))
	return origins


func _infer_idle_villager_origins_for_legacy_gameplay_state(idle_population: int) -> Array:
	var origins: Array = []
	if idle_population <= 0:
		return origins
	var castle_building: RefCounted = _find_castle_building()
	var castle_slots: int = mini(CASTLE_POPULATION_CAPACITY, idle_population)
	if castle_building != null:
		for _castle_index in range(castle_slots):
			origins.append({
				"origin_type": "castle",
				"castle_cell": castle_building.position,
			})
	var remaining_idle_population: int = idle_population - origins.size()
	if remaining_idle_population <= 0:
		return origins
	for building in initial_buildings:
		if building == null or int(building.building_type) != MapTypes.BuildingType.HOUSE:
			continue
		for _house_index in range(HOUSE_POPULATION_CAPACITY):
			if origins.size() >= idle_population:
				return origins
			origins.append({
				"origin_type": "house",
				"home_building_cell": building.position,
			})
	while origins.size() < idle_population:
		origins.append({"origin_type": "fallback"})
	return origins


func _spawn_idle_villager_from_origin_data(villager_index: int, origin_data: Dictionary, fallback_wander_bounds: Rect2) -> void:
	var origin_type: String = str(origin_data.get("origin_type", ""))
	match origin_type:
		"house":
			var home_cell: Vector2i = _get_vector2i_from_dictionary(origin_data, "home_building_cell", Vector2i(-1, -1))
			var house_building: RefCounted = _find_building_at_cell(MapTypes.BuildingType.HOUSE, home_cell)
			if house_building != null:
				_spawn_idle_villager_for_house(villager_index, house_building, fallback_wander_bounds)
				return
		"castle":
			var castle_cell: Vector2i = _get_vector2i_from_dictionary(origin_data, "castle_cell", Vector2i(-1, -1))
			var castle_building: RefCounted = _find_building_at_cell(MapTypes.BuildingType.TOWN_CENTER, castle_cell)
			if castle_building != null:
				var castle_spawn_context: Dictionary = _get_initial_castle_villager_spawn_context()
				_spawn_initial_castle_idle_villager(villager_index, castle_spawn_context, fallback_wander_bounds.get_center(), fallback_wander_bounds)
				return
	_spawn_fallback_idle_villager(villager_index, fallback_wander_bounds)


func _get_gameplay_state_dictionary(gameplay_state: Dictionary, key: String) -> Dictionary:
	var dictionary_variant: Variant = gameplay_state.get(key, {})
	if typeof(dictionary_variant) != TYPE_DICTIONARY:
		return {}
	var dictionary_value: Dictionary = dictionary_variant
	return dictionary_value.duplicate(true)


func _collect_runtime_chunks_for_save() -> Dictionary:
	if _semantic_runtime_view != null:
		return _semantic_runtime_view.get_runtime_chunks()
	return _pending_restored_runtime_chunks.duplicate(true)


func _get_semantic_camera_cell_for_save() -> Vector2i:
	if _semantic_runtime_view != null:
		var snapshot: Dictionary = _semantic_runtime_view.get_debug_snapshot()
		return snapshot.get("camera_cell", Vector2i.ZERO)
	if main_camera == null or ground_layer == null:
		return Vector2i.ZERO
	return ground_layer.local_to_map(ground_layer.to_local(main_camera.global_position))


func _build_governance_bootstrap_context_for_save() -> Dictionary:
	if grid == null:
		return {}

	var active_bootstrap_tile_rect: Rect2i = map_read_result.get("used_rect", _get_active_governance_bootstrap_tile_rect())

	return {
		"bootstrap_tile_rect": active_bootstrap_tile_rect,
		"grid": grid,
		"resource_regions": resource_regions,
		"farmable_regions": farmable_regions,
		"used_rect": map_read_result.get("used_rect", active_bootstrap_tile_rect),
		"cell_offset": map_read_result.get("cell_offset", active_bootstrap_tile_rect.position),
		"ground_cells_read": int(map_read_result.get("ground_cells_read", 0)),
		"resource_cells_read": int(map_read_result.get("resource_cells_read", 0)),
		"terrain_counts": map_read_result.get("terrain_counts", {}),
	}


func _build_gameplay_state_for_save() -> Dictionary:
	return {
		"gameplay_state_version": WorldSemanticMapSaveScript.GAMEPLAY_STATE_VERSION,
		"buildings": _build_building_save_data_for_gameplay_state(),
		"resource_inventory": _build_resource_inventory_save_data_for_gameplay_state(),
		"resource_depletion_state": _build_resource_depletion_save_data_for_gameplay_state(),
		"idle_villager_origins": _build_idle_villager_origin_save_data_for_gameplay_state(),
		"worker_resource_tasks": _build_worker_resource_task_save_data_for_gameplay_state(),
		"governance_state": _build_governance_state_save_data_for_gameplay_state(),
		"game_clock": _build_game_clock_save_data_for_gameplay_state(),
		"event_log_messages": event_log_messages.duplicate(),
		"last_minute_delta": last_minute_delta.duplicate(true),
		"last_tax_message": last_tax_message,
		"last_happiness_message": last_happiness_message,
		"last_happiness_report": last_happiness_report.duplicate(true),
		"last_riot_message": last_riot_message,
		"last_riot_report": last_riot_report.duplicate(true),
		"last_victory_defeat_report": last_victory_defeat_report.duplicate(true),
		"last_daily_happiness_delta": last_daily_happiness_delta,
		"last_tax_day_index": last_tax_day_index,
		"happiness_stable_day_count": _get_happiness_stable_day_count_for_save(),
		"victory_consecutive_riot_days": _get_victory_consecutive_riot_days_for_save(),
		"victory_completed_day_index": _get_victory_completed_day_index_for_save(),
	}


func _build_building_save_data_for_gameplay_state() -> Array:
	var buildings_save_data: Array = []
	for building in initial_buildings:
		if building == null or not building.has_method("to_save_data"):
			continue
		buildings_save_data.append(building.call("to_save_data"))
	return buildings_save_data


func _build_resource_inventory_save_data_for_gameplay_state() -> Dictionary:
	if resource_inventory == null or not resource_inventory.has_method("to_save_data"):
		return {}
	return resource_inventory.call("to_save_data")


func _build_resource_depletion_save_data_for_gameplay_state() -> Dictionary:
	if resource_depletion_state == null or not resource_depletion_state.has_method("to_save_data"):
		return {}
	var save_data_variant: Variant = resource_depletion_state.call("to_save_data")
	if typeof(save_data_variant) != TYPE_DICTIONARY:
		return {}
	var save_data: Dictionary = save_data_variant
	return save_data.duplicate(true)


func _build_idle_villager_origin_save_data_for_gameplay_state() -> Array:
	var origin_save_data: Array = []
	if characters_root == null:
		return origin_save_data
	for villager_variant in _get_idle_villagers():
		if not (villager_variant is Node2D):
			continue
		var villager := villager_variant as Node2D
		var origin_data: Dictionary = _build_idle_villager_origin_save_data(villager)
		if origin_data.is_empty():
			continue
		origin_save_data.append(origin_data)
	return origin_save_data


func _build_idle_villager_origin_save_data(villager: Node2D) -> Dictionary:
	if villager == null or not is_instance_valid(villager):
		return {}
	var home_cell_variant: Variant = villager.get_meta("home_building_cell", Vector2i(-1, -1))
	if typeof(home_cell_variant) == TYPE_VECTOR2I:
		var home_cell: Vector2i = home_cell_variant
		if home_cell.x >= 0 and home_cell.y >= 0:
			return {
				"origin_type": "house",
				"home_building_cell": home_cell,
			}
	if str(villager.get_meta("wander_rule", "")) == "castle_initial_grid":
		var castle_cell_variant: Variant = villager.get_meta("castle_cell", Vector2i(-1, -1))
		if typeof(castle_cell_variant) == TYPE_VECTOR2I:
			var castle_cell: Vector2i = castle_cell_variant
			if castle_cell.x >= 0 and castle_cell.y >= 0:
				return {
					"origin_type": "castle",
					"castle_cell": castle_cell,
				}
	return {"origin_type": "fallback"}


func _build_worker_resource_task_save_data_for_gameplay_state() -> Array:
	var task_save_data_array: Array = []
	for villager_variant in worker_resource_tasks.keys():
		var task_variant: Variant = worker_resource_tasks.get(villager_variant, {})
		if typeof(task_variant) != TYPE_DICTIONARY:
			continue
		var task: Dictionary = task_variant
		var building_variant: Variant = task.get("building", null)
		var building_index: int = initial_buildings.find(building_variant)
		if building_index < 0:
			continue
		var resource_type: StringName = StringName(str(task.get("resource_type", &"")))
		if resource_type == &"":
			continue
		var task_state: StringName = StringName(str(task.get("state", &"idle")))
		if task_state == &"idle":
			continue
		task_save_data_array.append({
			"building_index": building_index,
			"resource_type": str(resource_type),
			"target_resource_cell": task.get("target_resource_cell", Vector2i(-1, -1)),
			"target_work_cell": task.get("target_work_cell", Vector2i(-1, -1)),
			"state": str(task_state),
			"collect_elapsed_minutes": float(task.get("collect_elapsed_minutes", task.get("collect_elapsed_seconds", 0.0))),
			"collect_required_minutes": float(task.get("collect_required_minutes", task.get("collect_required_seconds", 0.0))),
			"carried_amount": max(float(task.get("carried_amount", 0.0)), 0.0),
			"carry_amount_per_trip": max(float(task.get("carry_amount_per_trip", 1.0)), 0.0),
			"delivered_amount": max(float(task.get("delivered_amount", 0.0)), 0.0),
			"shift_elapsed_minutes": max(float(task.get("shift_elapsed_minutes", 0.0)), 0.0),
			"shift_required_minutes": max(float(task.get("shift_required_minutes", 90.0)), 0.0),
			"pending_rest_after_delivery": bool(task.get("pending_rest_after_delivery", false)),
			"shift_resting": bool(task.get("shift_resting", false)),
			"failure_reason": str(task.get("failure_reason", "")),
		})
	return task_save_data_array


func _restore_worker_resource_tasks_from_gameplay_state(gameplay_state: Dictionary) -> void:
	var worker_task_save_data_variant: Variant = gameplay_state.get("worker_resource_tasks", [])
	if typeof(worker_task_save_data_variant) != TYPE_ARRAY:
		return
	var task_save_data_array: Array = worker_task_save_data_variant
	var task_entries_by_building_index: Dictionary = _group_worker_resource_task_save_data_by_building(task_save_data_array)
	var restored_task_count: int = 0
	for building_index_variant in task_entries_by_building_index.keys():
		var building_index: int = int(building_index_variant)
		if building_index < 0 or building_index >= initial_buildings.size():
			continue
		var building_variant: Variant = initial_buildings[building_index]
		if not (building_variant is RefCounted):
			continue
		var building: RefCounted = building_variant
		var assigned_villagers: Array = _get_villagers_for_building(building)
		var task_entries: Array = task_entries_by_building_index.get(building_index, [])
		if assigned_villagers.is_empty():
			_restore_unbound_worker_resource_task_entries_to_building_storage(building, task_entries)
			continue
		var restore_count: int = mini(task_entries.size(), assigned_villagers.size())
		for task_index in range(restore_count):
			var villager_variant: Variant = assigned_villagers[task_index]
			if not (villager_variant is Node2D):
				continue
			var villager := villager_variant as Node2D
			var task_save_data: Dictionary = task_entries[task_index]
			if _restore_worker_resource_task_to_villager(villager, building, task_save_data):
				restored_task_count += 1
			else:
				_restore_unbound_worker_resource_task_entry_to_building_storage(building, task_save_data)
		for task_index in range(restore_count, task_entries.size()):
			var task_save_data: Dictionary = task_entries[task_index]
			_restore_unbound_worker_resource_task_entry_to_building_storage(building, task_save_data)
	if restored_task_count > 0:
		_append_event_log("已恢复工人未交付资源任务。")
		_update_economy_ui()
		_update_worker_control_ui()


func _group_worker_resource_task_save_data_by_building(task_save_data_array: Array) -> Dictionary:
	var entries_by_building_index: Dictionary = {}
	for task_entry_variant in task_save_data_array:
		if typeof(task_entry_variant) != TYPE_DICTIONARY:
			continue
		var task_save_data: Dictionary = task_entry_variant
		var building_index: int = int(task_save_data.get("building_index", -1))
		if building_index < 0:
			continue
		var entries: Array = entries_by_building_index.get(building_index, [])
		entries.append(task_save_data)
		entries_by_building_index[building_index] = entries
	return entries_by_building_index


func _restore_unbound_worker_resource_task_entries_to_building_storage(building: RefCounted, task_entries: Array) -> void:
	for task_entry_variant in task_entries:
		if typeof(task_entry_variant) != TYPE_DICTIONARY:
			continue
		var task_save_data: Dictionary = task_entry_variant
		_restore_unbound_worker_resource_task_entry_to_building_storage(building, task_save_data)


func _restore_unbound_worker_resource_task_entry_to_building_storage(building: RefCounted, task_save_data: Dictionary) -> void:
	if building == null or not building.has_method("add_to_storage"):
		return
	var carried_amount: float = max(float(task_save_data.get("carried_amount", 0.0)), 0.0)
	if carried_amount <= 0.0:
		return
	var resource_type: StringName = StringName(str(task_save_data.get("resource_type", &"")))
	if resource_type == &"":
		resource_type = MapTypes.get_resource_name_for_building(int(building.building_type))
	if resource_type == &"":
		return
	var accepted_amount: float = float(building.call("add_to_storage", resource_type, carried_amount))
	_restore_worker_resource_overflow_to_inventory(resource_type, max(carried_amount - accepted_amount, 0.0))


func _restore_worker_resource_task_to_villager(villager: Node2D, building: RefCounted, task_save_data: Dictionary) -> bool:
	if villager == null or not is_instance_valid(villager) or building == null:
		return false
	var resource_type: StringName = StringName(str(task_save_data.get("resource_type", &"")))
	if resource_type == &"":
		resource_type = MapTypes.get_resource_name_for_building(int(building.building_type))
	if resource_type == &"":
		return false
	var target: Dictionary = _build_restored_worker_resource_task_target(villager, building, task_save_data, resource_type)
	if not bool(target.get("ok", false)):
		return false
	var task: Dictionary = _build_worker_resource_task(villager, building, target)
	_apply_worker_resource_task_save_data(task, task_save_data, resource_type)
	worker_resource_tasks[villager] = task
	_restore_villager_cycle_for_worker_resource_task(villager, task)
	_update_worker_resource_task_visual_status(villager, task)
	return true


func _build_restored_worker_resource_task_target(villager: Node2D, building: RefCounted, task_save_data: Dictionary, resource_type: StringName) -> Dictionary:
	var resource_cell: Vector2i = _get_vector2i_from_dictionary(task_save_data, "target_resource_cell", Vector2i(-1, -1))
	var work_cell: Vector2i = _get_vector2i_from_dictionary(task_save_data, "target_work_cell", Vector2i(-1, -1))
	var reserved_resource_cells: Dictionary = _get_reserved_resource_cells_for_building(building, villager)
	if resource_cell.x >= 0 and work_cell.x >= 0 and not _is_resource_cell_reserved(resource_cell, reserved_resource_cells):
		return {
			"ok": true,
			"reason": "",
			"building": building,
			"region": null,
			"resource_type": resource_type,
			"resource_cell": resource_cell,
			"work_cell": work_cell,
		}
	return _find_resource_collection_target_for_building(building, villager)


func _get_vector2i_from_dictionary(dictionary: Dictionary, key: String, default_value: Vector2i) -> Vector2i:
	var value: Variant = dictionary.get(key, default_value)
	if typeof(value) == TYPE_VECTOR2I:
		return value
	return default_value


func _apply_worker_resource_task_save_data(task: Dictionary, task_save_data: Dictionary, resource_type: StringName) -> void:
	var task_state: StringName = StringName(str(task_save_data.get("state", RESOURCE_TASK_GOING_TO_RESOURCE)))
	var carried_amount: float = max(float(task_save_data.get("carried_amount", 0.0)), 0.0)
	var failure_reason: String = str(task_save_data.get("failure_reason", ""))
	if task_state == RESOURCE_TASK_FAILED and failure_reason.contains("库存已满") and carried_amount > 0.0:
		task_state = RESOURCE_TASK_WAITING_FOR_STORAGE
		failure_reason = "等待清空建筑库存。"
	task["state"] = task_state
	task["resource_type"] = resource_type
	task["collect_elapsed_minutes"] = max(float(task_save_data.get("collect_elapsed_minutes", 0.0)), 0.0)
	task["collect_elapsed_seconds"] = float(task["collect_elapsed_minutes"])
	task["collect_required_minutes"] = max(float(task_save_data.get("collect_required_minutes", task.get("collect_required_minutes", 0.0))), 0.0)
	task["collect_required_seconds"] = float(task["collect_required_minutes"])
	task["carried_amount"] = carried_amount
	task["carry_amount_per_trip"] = max(float(task_save_data.get("carry_amount_per_trip", task.get("carry_amount_per_trip", RESOURCE_TASK_CARRY_AMOUNT))), 0.0)
	task["delivered_amount"] = max(float(task_save_data.get("delivered_amount", 0.0)), 0.0)
	task["shift_elapsed_minutes"] = max(float(task_save_data.get("shift_elapsed_minutes", 0.0)), 0.0)
	task["shift_required_minutes"] = max(float(task_save_data.get("shift_required_minutes", RESOURCE_TASK_DEFAULT_SHIFT_MINUTES)), 0.0)
	task["pending_rest_after_delivery"] = bool(task_save_data.get("pending_rest_after_delivery", false))
	task["shift_resting"] = bool(task_save_data.get("shift_resting", false))
	task["failure_reason"] = failure_reason


func _restore_villager_cycle_for_worker_resource_task(villager: Node2D, task: Dictionary) -> void:
	if villager == null or not is_instance_valid(villager):
		return
	_update_villager_resource_task_targets(villager, task, true)
	var task_state: StringName = StringName(str(task.get("state", RESOURCE_TASK_GOING_TO_RESOURCE)))
	match task_state:
		RESOURCE_TASK_COLLECTING:
			_restore_villager_to_resource_work_position(villager, task)
		RESOURCE_TASK_RETURNING_TO_BUILDING:
			_request_villager_return_to_building(villager)
		RESOURCE_TASK_DELIVERING, RESOURCE_TASK_WAITING_FOR_STORAGE:
			_restore_villager_to_building_delivery_position(villager, task)
		RESOURCE_TASK_RESTING:
			_restore_villager_to_resting_position(villager, task)
		_:
			pass


func _restore_villager_to_resource_work_position(villager: Node2D, task: Dictionary) -> void:
	villager.position = task.get("target_work_position", villager.position)
	if villager.has_method("_set_state"):
		var remaining_minutes: float = max(float(task.get("collect_required_minutes", 0.0)) - float(task.get("collect_elapsed_minutes", 0.0)), 0.0)
		villager.call("_set_state", 2, remaining_minutes)


func _restore_villager_to_building_delivery_position(villager: Node2D, task: Dictionary) -> void:
	villager.position = task.get("building_delivery_position", villager.position)
	if villager.has_method("_set_state"):
		villager.call("_set_state", 4, 0.0)


func _restore_villager_to_resting_position(villager: Node2D, task: Dictionary) -> void:
	villager.position = task.get("building_delivery_position", villager.position)
	if villager.has_method("_set_state"):
		villager.call("_set_state", 4, max(float(task.get("shift_required_minutes", 0.0)) - float(task.get("shift_elapsed_minutes", 0.0)), 0.0))


func _restore_worker_resource_overflow_to_inventory(resource_type: StringName, overflow_amount: float) -> void:
	if overflow_amount <= 0.0 or resource_inventory == null or not resource_inventory.has_method("add_amount"):
		return
	resource_inventory.call("add_amount", resource_type, overflow_amount)


func _build_governance_state_save_data_for_gameplay_state() -> Dictionary:
	if governance_state == null or not governance_state.has_method("to_save_data"):
		return {}
	return governance_state.call("to_save_data")


func _build_game_clock_save_data_for_gameplay_state() -> Dictionary:
	if game_clock == null or not game_clock.has_method("to_save_data"):
		return {}
	return game_clock.call("to_save_data")


func _get_happiness_stable_day_count_for_save() -> int:
	if happiness_system == null:
		return 0
	return max(int(happiness_system.get("stable_day_count")), 0)


func _get_victory_consecutive_riot_days_for_save() -> int:
	if victory_defeat_system == null:
		return 0
	return max(int(victory_defeat_system.get("consecutive_riot_days")), 0)


func _get_victory_completed_day_index_for_save() -> int:
	if victory_defeat_system == null:
		return 0
	return max(int(victory_defeat_system.get("completed_day_index")), 0)


func save_semantic_world() -> bool:
	var session = get_node_or_null("/root/WorldSession")
	var identity = _bootstrapped_semantic_identity
	var store = _bootstrapped_semantic_store
	if session != null and session.state == WorldSessionScript.WorldSessionState.READY:
		identity = session.identity
		store = session.get_ready_semantic_store()
	if identity == null or store == null:
		_append_event_log("保存失败：当前世界不可保存。")
		return false

	var gameplay_state: Dictionary = _build_gameplay_state_for_save()
	if gameplay_state.is_empty():
		_append_event_log("保存失败：玩法状态序列化失败。")
		return false
	var saved_message: String = "已保存当前游戏进度。"
	var event_log_for_save: Array = event_log_messages.duplicate()
	event_log_for_save.push_front(saved_message)
	while event_log_for_save.size() > 3:
		event_log_for_save.pop_back()
	gameplay_state["event_log_messages"] = event_log_for_save

	var saved: bool = WorldSemanticMapSaveScript.save_world(
		identity,
		store,
		_collect_runtime_chunks_for_save(),
		_get_semantic_camera_cell_for_save(),
		main_camera.zoom.x if main_camera != null else 1.0,
		_build_governance_bootstrap_context_for_save(),
		semantic_world_save_path,
		gameplay_state
	)
	_append_event_log(saved_message if saved else "保存失败：写入存档失败。")
	return saved


func reset_semantic_world() -> bool:
	if not _should_show_semantic_save_controls():
		_append_event_log("重置失败：当前不是语义地图模式。")
		return false
	random_map_seed = _get_next_semantic_reset_seed()
	_append_event_log("开始生成新的语义地图，seed=%d" % random_map_seed)
	if _bootstrap_via_loading_scene():
		return true
	_append_event_log("重置失败：无法启动语义 Loading 场景。")
	return false


func _on_save_map_pressed() -> void:
	save_semantic_world()


func _on_return_castle_pressed() -> void:
	var current_zoom: Vector2 = main_camera.zoom if main_camera != null else Vector2.ONE
	is_camera_dragging = false
	_focus_camera_on_castle()
	if main_camera != null:
		main_camera.zoom = current_zoom
	if _semantic_runtime_view != null and main_camera != null:
		_semantic_runtime_view.request_visual_coverage_for_camera_position(main_camera.global_position)
		_semantic_runtime_view.refresh_now()


func _on_reset_map_pressed() -> void:
	reset_semantic_world()


func _sync_random_map_seed_from_semantic_identity() -> void:
	if _bootstrapped_semantic_identity == null:
		return
	if not _bootstrapped_semantic_identity.is_valid():
		return
	random_map_seed = int(_bootstrapped_semantic_identity.seed)


func _get_next_semantic_reset_seed() -> int:
	var base_seed: int = random_map_seed
	if _bootstrapped_semantic_identity != null and _bootstrapped_semantic_identity.is_valid():
		base_seed = int(_bootstrapped_semantic_identity.seed)
	if base_seed >= WorldGenerationIdentityScript.INT64_MAX_VALUE:
		return WorldGenerationIdentityScript.INT64_MIN_VALUE + 1
	return base_seed + 1


func debug_stage7_get_regions_by_id() -> Dictionary:
	return _get_regions_by_id()


func debug_stage7_has_semantic_query_bridge() -> bool:
	return _semantic_gameplay_query_bridge != null


func _get_villager_navigation_terrain(cell: Vector2i) -> int:
	if _semantic_gameplay_query_bridge != null:
		var terrain_type: int = int(_semantic_gameplay_query_bridge.get_terrain(cell))
		if terrain_type != VILLAGER_NAVIGATION_TERRAIN_MISS:
			return terrain_type
	return super._get_villager_navigation_terrain(cell)


func debug_stage7_get_semantic_terrain(cell: Vector2i) -> int:
	if _semantic_gameplay_query_bridge == null:
		return -1
	return int(_semantic_gameplay_query_bridge.get_terrain(cell))


func debug_stage7_find_resource_region_id(cell: Vector2i, terrain_type: int) -> int:
	if _semantic_gameplay_query_bridge == null:
		return -1
	var region: RefCounted = _semantic_gameplay_query_bridge.find_resource_region_for_building_cell(cell, terrain_type)
	if region == null:
		return -1
	return int(region.get("region_id"))


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

	var map_offset: Vector2i = map_read_result.get("cell_offset", Vector2i.ZERO)
	var map_cell: Vector2i = castle_cell + map_offset
	main_camera.global_position = ground_layer.to_global(ground_layer.map_to_local(map_cell))


func _reset_load_baseline_metrics() -> void:
	_load_baseline_metrics = {
		"bootstrap_source": LOAD_BASELINE_SOURCE_UNKNOWN,
		"bootstrap_restore_mode": BOOTSTRAP_RESTORE_MODE_NONE,
		"bootstrap_context_build_count": 0,
		"scene_open_ms": -1.0,
		"ready_total_ms": -1.0,
		"read_demo_map_ms": -1.0,
		"load_world_ms": -1.0,
		"restore_ready_world_ms": -1.0,
		"build_bootstrap_context_ms": -1.0,
		"apply_bootstrap_context_ms": -1.0,
		"restore_camera_ms": -1.0,
		"time_to_first_playable_view_ms": -1.0,
		"time_to_visual_queue_drained_ms": -1.0,
		"save_file_bytes": -1,
	}
	_load_baseline_metrics_complete = false
	_load_baseline_playable_recorded = false
	_load_baseline_visual_queue_drained_recorded = false
	_load_baseline_completion_logged = false


func _get_active_governance_bootstrap_tile_rect() -> Rect2i:
	if not enable_compact_governance_bootstrap:
		return semantic_governance_bootstrap_tile_rect
	if _is_valid_compact_governance_bootstrap_tile_rect(semantic_governance_compact_bootstrap_tile_rect):
		return semantic_governance_compact_bootstrap_tile_rect
	if not _warned_invalid_compact_bootstrap_rect:
		_warned_invalid_compact_bootstrap_rect = true
		push_warning("RandomGovernancePlaytest compact governance bootstrap rect is invalid; fallback to full bootstrap rect.")
	return semantic_governance_bootstrap_tile_rect


func _is_valid_compact_governance_bootstrap_tile_rect(compact_rect: Rect2i) -> bool:
	if compact_rect.size.x <= 0 or compact_rect.size.y <= 0:
		return false
	return semantic_governance_bootstrap_tile_rect.encloses(compact_rect)


func _set_load_baseline_metric(metric_name: String, metric_value: Variant) -> void:
	_load_baseline_metrics[metric_name] = metric_value


func _elapsed_ms_since(start_usec: int) -> float:
	if start_usec <= 0:
		return 0.0
	return float(Time.get_ticks_usec() - start_usec) / 1000.0


func _elapsed_ms_between(start_usec: int, end_usec: int) -> float:
	if start_usec <= 0 or end_usec <= 0 or end_usec < start_usec:
		return 0.0
	return float(end_usec - start_usec) / 1000.0


func _get_file_size_bytes(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	return int(file.get_length())


func _mark_load_baseline_immediately_ready() -> void:
	if not _load_baseline_playable_recorded:
		_set_load_baseline_metric("time_to_first_playable_view_ms", _elapsed_ms_since(_scene_constructed_at_usec))
		_load_baseline_playable_recorded = true
	if not _load_baseline_visual_queue_drained_recorded:
		_set_load_baseline_metric("time_to_visual_queue_drained_ms", _elapsed_ms_since(_scene_constructed_at_usec))
		_load_baseline_visual_queue_drained_recorded = true
	_finalize_load_baseline_metrics_if_ready()


func _update_load_baseline_runtime_metrics() -> void:
	if _load_baseline_metrics_complete:
		return
	if _semantic_runtime_view == null:
		return
	if main_camera == null:
		return

	var runtime_snapshot: Dictionary = _semantic_runtime_view.get_debug_snapshot()
	var queue_size: int = int(runtime_snapshot.get("queue_size", -1))
	_set_load_baseline_metric("runtime_view_queue_size", queue_size)

	if not _load_baseline_playable_recorded:
		if _semantic_runtime_view.can_show_camera_position_without_gray(main_camera.global_position):
			_set_load_baseline_metric("time_to_first_playable_view_ms", _elapsed_ms_since(_scene_constructed_at_usec))
			_load_baseline_playable_recorded = true

	if not _load_baseline_visual_queue_drained_recorded and queue_size == 0:
		_set_load_baseline_metric("time_to_visual_queue_drained_ms", _elapsed_ms_since(_scene_constructed_at_usec))
		_load_baseline_visual_queue_drained_recorded = true

	_finalize_load_baseline_metrics_if_ready()


func _finalize_load_baseline_metrics_if_ready() -> void:
	if _load_baseline_metrics_complete:
		return
	if not _load_baseline_playable_recorded:
		return
	if not _load_baseline_visual_queue_drained_recorded:
		return

	_load_baseline_metrics_complete = true
	if _load_baseline_completion_logged:
		return
	_load_baseline_completion_logged = true
	print("random governance load baseline metrics | ", get_load_baseline_metrics_snapshot())
