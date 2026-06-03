class_name WorldSemanticGrid
extends RefCounted


const SEMANTIC_CHUNK_SIZE: Vector2i = Vector2i(32, 32)
const TILES_PER_CHUNK: int = 1024

const PREWARM_TILE_RECT: Rect2i = Rect2i(
	Vector2i(-1024, -1024),
	Vector2i(2048, 2048)
)

const PREWARM_CHUNK_RECT: Rect2i = Rect2i(
	Vector2i(-32, -32),
	Vector2i(64, 64)
)

const PREWARM_TOTAL_CHUNKS: int = 4096


static func world_cell_to_chunk_coords(world_cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(world_cell.x) / float(SEMANTIC_CHUNK_SIZE.x)),
		floori(float(world_cell.y) / float(SEMANTIC_CHUNK_SIZE.y))
	)


static func world_cell_to_local_coords(world_cell: Vector2i) -> Vector2i:
	return Vector2i(
		posmod(world_cell.x, SEMANTIC_CHUNK_SIZE.x),
		posmod(world_cell.y, SEMANTIC_CHUNK_SIZE.y)
	)


static func local_coords_to_index(local_coords: Vector2i) -> int:
	return local_coords.y * SEMANTIC_CHUNK_SIZE.x + local_coords.x


static func world_cell_to_local_index(world_cell: Vector2i) -> int:
	return local_coords_to_index(world_cell_to_local_coords(world_cell))


static func chunk_coords_to_origin_cell(chunk_coords: Vector2i) -> Vector2i:
	return Vector2i(
		chunk_coords.x * SEMANTIC_CHUNK_SIZE.x,
		chunk_coords.y * SEMANTIC_CHUNK_SIZE.y
	)


static func is_cell_in_prewarm_rect(world_cell: Vector2i) -> bool:
	return PREWARM_TILE_RECT.has_point(world_cell)


static func is_chunk_in_prewarm_rect(chunk_coords: Vector2i) -> bool:
	return PREWARM_CHUNK_RECT.has_point(chunk_coords)


static func enumerate_prewarm_chunk_coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.resize(PREWARM_TOTAL_CHUNKS)

	var write_index := 0
	for y in range(PREWARM_CHUNK_RECT.position.y, PREWARM_CHUNK_RECT.end.y):
		for x in range(PREWARM_CHUNK_RECT.position.x, PREWARM_CHUNK_RECT.end.x):
			result[write_index] = Vector2i(x, y)
			write_index += 1

	return result
