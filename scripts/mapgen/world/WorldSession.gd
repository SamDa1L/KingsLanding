extends Node


const WorldSemanticStoreScript := preload("res://scripts/mapgen/world/WorldSemanticStore.gd")

const INVALID_RUN_ID: int = 0

enum WorldSessionState {
	EMPTY,
	PREWARMING,
	READY,
}

var state: WorldSessionState = WorldSessionState.EMPTY
var active_prewarm_run_id: int = 0
var identity = null
var semantic_store = null
var has_active_builder: bool = false
var last_error: String = ""


func _ready() -> void:
	state = WorldSessionState.EMPTY
	active_prewarm_run_id = 0
	identity = null
	semantic_store = null
	has_active_builder = false
	last_error = ""


func begin_new_world(new_identity) -> int:
	last_error = ""

	if state != WorldSessionState.EMPTY:
		last_error = "begin_new_world requires EMPTY session state"
		return INVALID_RUN_ID
	if has_active_builder:
		last_error = "begin_new_world requires no active prewarm builder"
		return INVALID_RUN_ID
	if new_identity == null:
		last_error = "begin_new_world requires non-null identity"
		return INVALID_RUN_ID
	if not new_identity.is_valid():
		last_error = "begin_new_world requires valid identity"
		return INVALID_RUN_ID

	active_prewarm_run_id += 1
	var new_store = WorldSemanticStoreScript.new()
	if not new_store.bind_prewarm_batch(new_identity, active_prewarm_run_id):
		last_error = "begin_new_world failed to bind semantic store: %s" % new_store.last_submit_error
		return INVALID_RUN_ID

	identity = new_identity
	semantic_store = new_store
	state = WorldSessionState.PREWARMING
	return active_prewarm_run_id


func mark_current_prewarm_ready(run_id: int, store) -> bool:
	last_error = ""

	if state != WorldSessionState.PREWARMING:
		last_error = "mark_current_prewarm_ready requires PREWARMING state"
		return false
	if run_id != active_prewarm_run_id:
		last_error = "mark_current_prewarm_ready run id mismatch"
		return false
	if semantic_store == null:
		last_error = "mark_current_prewarm_ready requires active semantic store"
		return false
	if store != semantic_store:
		last_error = "mark_current_prewarm_ready store instance mismatch"
		return false
	if semantic_store.prewarm_state != WorldSemanticStoreScript.PrewarmState.READY:
		last_error = "mark_current_prewarm_ready requires READY store"
		return false

	state = WorldSessionState.READY
	return true


func restore_ready_world(restored_identity, restored_store) -> bool:
	last_error = ""
	if state != WorldSessionState.EMPTY:
		last_error = "restore_ready_world requires EMPTY session state"
		return false
	if has_active_builder:
		last_error = "restore_ready_world requires no active prewarm builder"
		return false
	if restored_identity == null or not restored_identity.is_valid():
		last_error = "restore_ready_world requires valid identity"
		return false
	if restored_store == null:
		last_error = "restore_ready_world requires semantic store"
		return false
	if restored_store.prewarm_state != WorldSemanticStoreScript.PrewarmState.READY:
		last_error = "restore_ready_world requires READY store"
		return false

	identity = restored_identity
	semantic_store = restored_store
	state = WorldSessionState.READY
	return true


func invalidate_current_prewarm() -> void:
	last_error = ""
	if state != WorldSessionState.PREWARMING and semantic_store == null and identity == null:
		return

	if semantic_store != null and state == WorldSessionState.PREWARMING:
		semantic_store.invalidate_prewarm()

	identity = null
	semantic_store = null
	has_active_builder = false
	state = WorldSessionState.EMPTY


func end_current_world() -> void:
	last_error = ""
	if state != WorldSessionState.READY:
		last_error = "end_current_world requires READY state"
		return
	if has_active_builder:
		last_error = "end_current_world requires no active prewarm builder"
		return

	identity = null
	semantic_store = null
	state = WorldSessionState.EMPTY


func can_enter_gameplay() -> bool:
	if state != WorldSessionState.READY:
		return false
	if semantic_store == null:
		return false
	return semantic_store.prewarm_state == WorldSemanticStoreScript.PrewarmState.READY


func get_ready_semantic_store():
	if not can_enter_gameplay():
		return null
	return semantic_store
