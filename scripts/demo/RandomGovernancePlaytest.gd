class_name RandomGovernancePlaytest
extends "res://scripts/demo/GovernanceDemo.gd"


const NoiseBasedMapGeneratorScript := preload("res://scripts/mapgen/NoiseBasedMapGenerator.gd")
const GeneratedMapRendererScript := preload("res://scripts/mapgen/GeneratedMapRenderer.gd")
const GeneratedMapCompatibilityAdapterScript := preload("res://scripts/mapgen/GeneratedMapCompatibilityAdapter.gd")
const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd")
const MapTypes := preload("res://scripts/map/MapTypes.gd")
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

	loading_instance.set("auto_start", true)
	loading_instance.set("auto_transition_to_gameplay", true)
	loading_instance.set("auto_free_on_transition", true)
	loading_instance.set("gameplay_scene", gameplay_scene_resource)

	if get_parent() != null:
		get_parent().call_deferred("add_child", loading_instance)
	else:
		get_tree().root.call_deferred("add_child", loading_instance)

	call_deferred("queue_free")
	return true


func _setup_semantic_save_controls() -> void:
	if save_map_button != null and not save_map_button.pressed.is_connected(_on_save_map_pressed):
		save_map_button.pressed.connect(_on_save_map_pressed)
	if reset_map_button != null and not reset_map_button.pressed.is_connected(_on_reset_map_pressed):
		reset_map_button.pressed.connect(_on_reset_map_pressed)


func _update_semantic_save_controls() -> void:
	var controls_visible: bool = _should_show_semantic_save_controls()
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
	_pending_restored_camera_cell = Vector2i.ZERO
	_pending_restored_camera_zoom = 1.0
	_has_pending_restored_camera_state = false


func _try_restore_saved_world(session) -> bool:
	if not enable_semantic_world_restore:
		return false
	if session == null or session.state != WorldSessionScript.WorldSessionState.EMPTY:
		return false
	if not WorldSemanticMapSaveScript.has_save(DEFAULT_SEMANTIC_WORLD_SAVE_PATH):
		return false

	_set_load_baseline_metric("save_file_bytes", _get_file_size_bytes(DEFAULT_SEMANTIC_WORLD_SAVE_PATH))
	var load_world_started_usec: int = Time.get_ticks_usec()
	var loaded_world: Dictionary = WorldSemanticMapSaveScript.load_world(DEFAULT_SEMANTIC_WORLD_SAVE_PATH)
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


func save_semantic_world() -> bool:
	var session = get_node_or_null("/root/WorldSession")
	var identity = _bootstrapped_semantic_identity
	var store = _bootstrapped_semantic_store
	if session != null and session.state == WorldSessionScript.WorldSessionState.READY:
		identity = session.identity
		store = session.get_ready_semantic_store()
	if identity == null or store == null:
		_append_event_log("保存失败：当前不是可保存的语义世界。")
		return false

	var saved: bool = WorldSemanticMapSaveScript.save_world(
		identity,
		store,
		_collect_runtime_chunks_for_save(),
		_get_semantic_camera_cell_for_save(),
		main_camera.zoom.x if main_camera != null else 1.0,
		_build_governance_bootstrap_context_for_save(),
		DEFAULT_SEMANTIC_WORLD_SAVE_PATH
	)
	_append_event_log("已保存当前语义地图。" if saved else "保存失败：写入存档失败。")
	return saved


func reset_semantic_world() -> bool:
	if not _should_show_semantic_save_controls():
		_append_event_log("重置失败：当前不是语义地图模式。")
		return false
	if _bootstrap_via_loading_scene():
		return true
	_append_event_log("重置失败：无法启动语义 Loading 场景。")
	return false


func _on_save_map_pressed() -> void:
	save_semantic_world()


func _on_reset_map_pressed() -> void:
	reset_semantic_world()


func debug_stage7_get_regions_by_id() -> Dictionary:
	return _get_regions_by_id()


func debug_stage7_has_semantic_query_bridge() -> bool:
	return _semantic_gameplay_query_bridge != null


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
