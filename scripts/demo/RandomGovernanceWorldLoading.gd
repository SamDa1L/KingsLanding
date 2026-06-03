class_name RandomGovernanceWorldLoading
extends Control


signal loading_started(run_id: int)
signal loading_ready(run_id: int, store)
signal loading_failed(run_id: int, first_error: String)
signal gameplay_transition_requested(gameplay_instance: Node)


const WorldGenerationIdentityScript := preload("res://scripts/mapgen/world/WorldGenerationIdentity.gd")
const WorldPrewarmBuilderScript := preload("res://scripts/mapgen/world/WorldPrewarmBuilder.gd")
const WorldSemanticGridScript := preload("res://scripts/mapgen/world/WorldSemanticGrid.gd")
const WorldSemanticStoreScript := preload("res://scripts/mapgen/world/WorldSemanticStore.gd")
const WorldSessionScript := preload("res://scripts/mapgen/world/WorldSession.gd")

enum LoadingState {
	IDLE,
	GENERATING,
	BUILDING_VISUALS,
	FAILED,
	READY,
	TRANSITIONED,
}

@export var world_seed: int = 20260529
@export var gameplay_scene: PackedScene
@export var submission_budget_usec: int = 1000
@export var visual_build_units_per_frame: int = 256
@export var auto_start: bool = true
@export var auto_transition_to_gameplay: bool = true
@export var auto_free_on_transition: bool = true
@export var generator_version: String = WorldGenerationIdentityScript.DEFAULT_GENERATOR_VERSION
@export var deterministic_hash_version: String = WorldGenerationIdentityScript.DEFAULT_DETERMINISTIC_HASH_VERSION
@export var terrain_backend_id: String = WorldGenerationIdentityScript.DEFAULT_TERRAIN_BACKEND_ID
@export var semantic_digest_version: int = WorldGenerationIdentityScript.DEFAULT_SEMANTIC_DIGEST_VERSION
@export var generator_parameter_profile: Dictionary = {}

@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var progress_label: Label = $Panel/VBoxContainer/ProgressLabel
@onready var elapsed_label: Label = $Panel/VBoxContainer/ElapsedLabel
@onready var average_label: Label = $Panel/VBoxContainer/AverageLabel
@onready var error_label: Label = $Panel/VBoxContainer/ErrorLabel
@onready var retry_button: Button = $Panel/VBoxContainer/RetryButton

var state: LoadingState = LoadingState.IDLE
var builder = null
var current_identity = null
var current_store = null
var current_run_id: int = 0
var started_at_usec: int = 0
var submitted_chunk_count: int = 0
var total_chunk_count: int = WorldSemanticGridScript.PREWARM_TOTAL_CHUNKS
var first_error: String = ""
var last_gameplay_instance: Node = null
var terminal_cleanup_requested: bool = false
var baseline_memory_static_bytes: int = 0
var ready_memory_static_bytes: int = 0
var peak_memory_static_bytes: int = 0
var ready_metrics_snapshot: Dictionary = {}
var visual_build_done_units: int = 0
var visual_build_total_units: int = 0
var visual_build_stage_name: String = ""
var visual_build_prepared: bool = false

var test_chunk_result_provider: Callable = Callable()
var test_worker_count_override: int = -1
var test_max_in_flight_results_override: int = -1


func _ready() -> void:
	if retry_button != null:
		retry_button.pressed.connect(_on_retry_pressed)
	_update_ui()
	if auto_start:
		call_deferred("start_loading")


func _process(_delta: float) -> void:
	if builder != null and not builder.is_terminal():
		builder.process_submission_budget(submission_budget_usec)
		submitted_chunk_count = builder.submitted_chunk_count

		if builder.state == WorldPrewarmBuilderScript.BuilderState.FAILING and not terminal_cleanup_requested:
			terminal_cleanup_requested = true
			builder.cancel_and_wait()
		elif builder.state == WorldPrewarmBuilderScript.BuilderState.CANCELLING and not terminal_cleanup_requested:
			terminal_cleanup_requested = true
			builder.cancel_and_wait()

	if state == LoadingState.BUILDING_VISUALS:
		_process_visual_build()

	_update_ui()


func start_loading() -> bool:
	if builder != null and not builder.is_terminal():
		return false
	if not has_node("/root/WorldSession"):
		first_error = "WorldSession autoload is missing"
		state = LoadingState.FAILED
		_update_ui()
		return false

	var session = get_node("/root/WorldSession")
	if session.state == WorldSessionScript.WorldSessionState.READY:
		session.end_current_world()
	elif session.state == WorldSessionScript.WorldSessionState.PREWARMING:
		session.invalidate_current_prewarm()

	current_identity = WorldGenerationIdentityScript.create(
		world_seed,
		generator_version,
		deterministic_hash_version,
		terrain_backend_id,
		generator_parameter_profile,
		semantic_digest_version
	)
	if current_identity == null or not current_identity.is_valid():
		first_error = "Failed to create valid WorldGenerationIdentity"
		state = LoadingState.FAILED
		_update_ui()
		return false

	current_run_id = session.begin_new_world(current_identity)
	if current_run_id == WorldSessionScript.INVALID_RUN_ID:
		first_error = "WorldSession.begin_new_world failed: %s" % String(session.last_error)
		state = LoadingState.FAILED
		_update_ui()
		return false

	current_store = session.semantic_store
	builder = WorldPrewarmBuilderScript.new()
	builder.test_chunk_result_provider = test_chunk_result_provider
	builder.test_worker_count_override = test_worker_count_override
	builder.test_max_in_flight_results_override = test_max_in_flight_results_override
	builder.progress_changed.connect(_on_builder_progress_changed)
	builder.prewarm_completed.connect(_on_builder_completed)
	builder.prewarm_failed.connect(_on_builder_failed)
	builder.prewarm_cancelled.connect(_on_builder_cancelled)

	session.has_active_builder = true
	if not builder.start(current_identity, current_store, current_run_id):
		session.has_active_builder = false
		session.invalidate_current_prewarm()
		first_error = "WorldPrewarmBuilder.start failed"
		state = LoadingState.FAILED
		_update_ui()
		return false

	state = LoadingState.GENERATING
	first_error = ""
	terminal_cleanup_requested = false
	last_gameplay_instance = null
	started_at_usec = Time.get_ticks_usec()
	submitted_chunk_count = 0
	visual_build_done_units = 0
	visual_build_total_units = 0
	visual_build_stage_name = ""
	visual_build_prepared = false
	baseline_memory_static_bytes = OS.get_static_memory_usage()
	ready_memory_static_bytes = 0
	peak_memory_static_bytes = baseline_memory_static_bytes
	ready_metrics_snapshot = {}
	loading_started.emit(current_run_id)
	_update_ui()
	return true


func retry_loading() -> bool:
	if builder != null and not builder.is_terminal():
		return false
	builder = null
	current_identity = null
	current_store = null
	current_run_id = 0
	first_error = ""
	terminal_cleanup_requested = false
	state = LoadingState.IDLE
	return start_loading()


func transition_to_gameplay() -> bool:
	if state == LoadingState.READY and last_gameplay_instance != null:
		last_gameplay_instance.visible = true
		gameplay_transition_requested.emit(last_gameplay_instance)
		state = LoadingState.TRANSITIONED
		if auto_free_on_transition:
			queue_free()
		return true

	if state != LoadingState.READY:
		return false
	if gameplay_scene == null:
		return false

	var session = get_node("/root/WorldSession")
	if not session.can_enter_gameplay():
		return false

	last_gameplay_instance = gameplay_scene.instantiate()
	if last_gameplay_instance != null:
		last_gameplay_instance.set("auto_build_full_visuals_on_ready", false)
	if get_parent() != null:
		get_parent().add_child(last_gameplay_instance)
	else:
		get_tree().root.add_child(last_gameplay_instance)
	if last_gameplay_instance != null:
		last_gameplay_instance.visible = true

	gameplay_transition_requested.emit(last_gameplay_instance)
	state = LoadingState.TRANSITIONED
	if auto_free_on_transition:
		queue_free()
	return true


func can_retry() -> bool:
	return state == LoadingState.FAILED


func can_enter_gameplay() -> bool:
	return state == LoadingState.READY


func get_elapsed_usec() -> int:
	if started_at_usec <= 0:
		return 0
	return Time.get_ticks_usec() - started_at_usec


func get_average_submit_usec() -> float:
	if builder == null:
		return 0.0
	if submitted_chunk_count <= 0:
		return 0.0
	return float(get_elapsed_usec()) / float(submitted_chunk_count)


func get_memory_metrics() -> Dictionary:
	return {
		"baseline_static_bytes": baseline_memory_static_bytes,
		"ready_static_bytes": ready_memory_static_bytes,
		"peak_static_bytes": peak_memory_static_bytes,
	}


func get_ready_metrics_snapshot() -> Dictionary:
	return ready_metrics_snapshot.duplicate(true)


func _on_builder_progress_changed(next_submitted_count: int, _total_count: int) -> void:
	submitted_chunk_count = next_submitted_count
	_update_ui()


func _on_builder_completed(run_id: int, completed_store) -> void:
	var session = get_node("/root/WorldSession")
	session.has_active_builder = false

	if run_id != current_run_id:
		first_error = "completed run id mismatch"
		state = LoadingState.FAILED
		session.invalidate_current_prewarm()
		loading_failed.emit(run_id, first_error)
		_update_ui()
		return

	if not session.mark_current_prewarm_ready(run_id, completed_store):
		first_error = "mark_current_prewarm_ready failed: %s" % String(session.last_error)
		state = LoadingState.FAILED
		session.invalidate_current_prewarm()
		loading_failed.emit(run_id, first_error)
		_update_ui()
		return

	state = LoadingState.READY
	current_store = completed_store
	ready_memory_static_bytes = OS.get_static_memory_usage()
	if ready_memory_static_bytes > peak_memory_static_bytes:
		peak_memory_static_bytes = ready_memory_static_bytes
	ready_metrics_snapshot = get_memory_metrics()
	loading_ready.emit(run_id, completed_store)
	_update_ui()

	if auto_transition_to_gameplay:
		_begin_visual_build_before_transition()


func _begin_visual_build_before_transition() -> void:
	if gameplay_scene == null:
		first_error = "gameplay_scene is missing"
		state = LoadingState.FAILED
		_update_ui()
		return

	last_gameplay_instance = gameplay_scene.instantiate()
	if last_gameplay_instance == null:
		first_error = "Failed to instantiate gameplay_scene"
		state = LoadingState.FAILED
		_update_ui()
		return

	last_gameplay_instance.set("auto_build_full_visuals_on_ready", false)
	last_gameplay_instance.set("visual_build_mode", 0)
	last_gameplay_instance.visible = false
	if get_parent() != null:
		get_parent().add_child(last_gameplay_instance)
	else:
		get_tree().root.add_child(last_gameplay_instance)

	state = LoadingState.BUILDING_VISUALS
	visual_build_done_units = 0
	visual_build_total_units = 0
	visual_build_stage_name = "准备绘制"
	visual_build_prepared = false
	call_deferred("_prepare_visual_build_instance")


func _prepare_visual_build_instance() -> void:
	if state != LoadingState.BUILDING_VISUALS:
		return
	if last_gameplay_instance == null:
		first_error = "Gameplay instance lost before visual build"
		state = LoadingState.FAILED
		_update_ui()
		return
	last_gameplay_instance.call("prepare_full_visual_build")
	visual_build_prepared = true
	_update_visual_build_progress()


func _process_visual_build() -> void:
	if last_gameplay_instance == null:
		first_error = "Gameplay instance lost during visual build"
		state = LoadingState.FAILED
		return
	if not last_gameplay_instance.has_method("process_full_visual_build_budget"):
		first_error = "Gameplay scene does not support visual build budget"
		state = LoadingState.FAILED
		return
	if not visual_build_prepared:
		return

	var has_more: bool = bool(last_gameplay_instance.call("process_full_visual_build_budget", visual_build_units_per_frame))
	_update_visual_build_progress()
	if has_more:
		return

	if bool(last_gameplay_instance.call("is_full_visual_build_complete")):
		last_gameplay_instance.call("finalize_full_visual_build")
		_update_visual_build_progress()
		state = LoadingState.READY
		if auto_transition_to_gameplay:
			transition_to_gameplay()
	else:
		first_error = "Visual build stopped before completion"
		state = LoadingState.FAILED


func _update_visual_build_progress() -> void:
	if last_gameplay_instance == null:
		return
	visual_build_stage_name = String(last_gameplay_instance.call("get_visual_build_stage_name"))
	visual_build_done_units = int(last_gameplay_instance.call("get_visual_build_done_units"))
	visual_build_total_units = int(last_gameplay_instance.call("get_visual_build_total_units"))


func _on_builder_failed(run_id: int, next_first_error: String) -> void:
	var session = get_node("/root/WorldSession")
	session.has_active_builder = false
	if session.state == WorldSessionScript.WorldSessionState.PREWARMING:
		session.invalidate_current_prewarm()

	first_error = next_first_error
	state = LoadingState.FAILED
	loading_failed.emit(run_id, next_first_error)
	_update_ui()


func _on_builder_cancelled(run_id: int) -> void:
	var session = get_node("/root/WorldSession")
	session.has_active_builder = false
	if session.state == WorldSessionScript.WorldSessionState.PREWARMING:
		session.invalidate_current_prewarm()

	first_error = "Prewarm cancelled"
	state = LoadingState.FAILED
	loading_failed.emit(run_id, first_error)
	_update_ui()


func _on_retry_pressed() -> void:
	retry_loading()


func _update_ui() -> void:
	peak_memory_static_bytes = maxi(peak_memory_static_bytes, OS.get_static_memory_usage())
	if status_label != null:
		if state == LoadingState.BUILDING_VISUALS:
			status_label.text = "状态: %s - %s" % [_get_state_text(), visual_build_stage_name]
		else:
			status_label.text = "状态: %s" % _get_state_text()
	if progress_label != null:
		if state == LoadingState.BUILDING_VISUALS:
			progress_label.text = "绘制进度: %d / %d" % [visual_build_done_units, visual_build_total_units]
		else:
			progress_label.text = "语义进度: %d / %d" % [submitted_chunk_count, total_chunk_count]
	if elapsed_label != null:
		elapsed_label.text = "耗时: %.3f s" % (float(get_elapsed_usec()) / 1000000.0)
	if average_label != null:
		if state == LoadingState.BUILDING_VISUALS:
			average_label.text = "语义提交已完成；当前正在绘制初始视口 TileMap"
		else:
			average_label.text = "平均提交耗时: %.3f us" % get_average_submit_usec()
	if error_label != null:
		error_label.text = "错误: %s" % first_error
	if retry_button != null:
		retry_button.disabled = not can_retry()


func _get_state_text() -> String:
	match state:
		LoadingState.IDLE:
			return "IDLE"
		LoadingState.GENERATING:
			return "GENERATING"
		LoadingState.BUILDING_VISUALS:
			return "BUILDING_VISUALS"
		LoadingState.FAILED:
			return "FAILED"
		LoadingState.READY:
			return "READY"
		LoadingState.TRANSITIONED:
			return "TRANSITIONED"
	return "UNKNOWN"
