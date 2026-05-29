class_name GeneratedChunkData
extends RefCounted


const DIR_N := 1
const DIR_E := 2
const DIR_S := 4
const DIR_W := 8


var chunk_coords: Vector2i = Vector2i.ZERO
var origin_cell: Vector2i = Vector2i.ZERO
var size: int = 32
var cells: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	chunk_coords = Vector2i.ZERO
	origin_cell = Vector2i.ZERO
	size = 32
	cells.clear()


func setup(next_chunk_coords: Vector2i, next_origin_cell: Vector2i, next_size: int) -> void:
	chunk_coords = next_chunk_coords
	origin_cell = next_origin_cell
	size = max(next_size, 1)
	cells.clear()


func register_cell(cell: Vector2i) -> void:
	cells[cell] = true


func unregister_cell(cell: Vector2i) -> void:
	cells.erase(cell)


func has_cell(cell: Vector2i) -> bool:
	return cells.has(cell)


func get_cell_count() -> int:
	return cells.size()


func get_local_cell(cell: Vector2i) -> Vector2i:
	return cell - origin_cell


func is_within_chunk(cell: Vector2i) -> bool:
	var local_cell := get_local_cell(cell)
	return local_cell.x >= 0 and local_cell.x < size and local_cell.y >= 0 and local_cell.y < size


func is_boundary_cell(cell: Vector2i, direction_mask: int = 0) -> bool:
	if not is_within_chunk(cell):
		return false

	var local_cell := get_local_cell(cell)
	if direction_mask == 0:
		return local_cell.x == 0 or local_cell.x == size - 1 or local_cell.y == 0 or local_cell.y == size - 1

	var matches_boundary := false

	if (direction_mask & DIR_N) != 0 and local_cell.y == 0:
		matches_boundary = true
	if (direction_mask & DIR_E) != 0 and local_cell.x == size - 1:
		matches_boundary = true
	if (direction_mask & DIR_S) != 0 and local_cell.y == size - 1:
		matches_boundary = true
	if (direction_mask & DIR_W) != 0 and local_cell.x == 0:
		matches_boundary = true

	return matches_boundary


func get_boundary_cells(direction_mask: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in cells.keys():
		if is_boundary_cell(cell, direction_mask):
			result.append(cell)
	return result

