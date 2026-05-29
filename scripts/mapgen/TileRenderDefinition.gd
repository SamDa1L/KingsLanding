class_name TileRenderDefinition # 图块渲染定义表类型名，供其他脚本直接引用。
extends RefCounted # 这是一个纯数据定义脚本，不需要挂到场景树里。


const GeneratedTileDataScript := preload("res://scripts/mapgen/GeneratedTileData.gd") # 预加载地图语义常量来源，避免地形字符串手写出错。
const TILE_SOURCE_ID := 0 # 当前使用的 TileSet source id，对应 MasterSimple_tileset.tres 的 source 0。
const DIR_N := 1 # 北方向掩码位，表示上方邻居。
const DIR_E := 2 # 东方向掩码位，表示右方邻居。
const DIR_S := 4 # 南方向掩码位，表示下方邻居。
const DIR_W := 8 # 西方向掩码位，表示左方邻居。
const MASK_N := DIR_N # 只有上边接壤目标地形的掩码。
const MASK_E := DIR_E # 只有右边接壤目标地形的掩码。
const MASK_S := DIR_S # 只有下边接壤目标地形的掩码。
const MASK_W := DIR_W # 只有左边接壤目标地形的掩码。
const MASK_NE := DIR_N | DIR_E # 上边和右边同时接壤目标地形的掩码。
const MASK_ES := DIR_E | DIR_S # 右边和下边同时接壤目标地形的掩码。
const MASK_SW := DIR_S | DIR_W # 下边和左边同时接壤目标地形的掩码。
const MASK_WN := DIR_W | DIR_N # 左边和上边同时接壤目标地形的掩码。
const MASK_NS := DIR_N | DIR_S # 上边和下边同时接壤目标地形的掩码。
const MASK_EW := DIR_E | DIR_W # 左边和右边同时接壤目标地形的掩码。
const MASK_NES := DIR_N | DIR_E | DIR_S # 上右下三边接壤目标地形的掩码。
const MASK_ESW := DIR_E | DIR_S | DIR_W # 右下左三边接壤目标地形的掩码。
const MASK_SWN := DIR_S | DIR_W | DIR_N # 下左上三边接壤目标地形的掩码。
const MASK_WNE := DIR_W | DIR_N | DIR_E # 左上右三边接壤目标地形的掩码。
const MASK_NESW := DIR_N | DIR_E | DIR_S | DIR_W # 四边全部接壤目标地形的掩码。
const INVALID_ATLAS := Vector2i(-1, -1) # 无效图集坐标，表示当前没有可用素材。
const BASE_TILE_ATLAS := { # 基础地形语义到基础图块坐标的映射表。
	GeneratedTileDataScript.TERRAIN_PLAIN: Vector2i(1, 1), # 平原基础图块坐标。
	GeneratedTileDataScript.TERRAIN_WATER: Vector2i(1, 5), # 深水基础图块坐标。
	GeneratedTileDataScript.TERRAIN_SHALLOW_WATER: Vector2i(1, 5), # 浅水基础图块坐标，当前与深水共用同一张图。
	GeneratedTileDataScript.TERRAIN_SAND: Vector2i(1, 8), # 沙地基础图块坐标。
} # 基础地形映射表结束。

const RESOURCE_TILE_ATLAS := { # 资源覆盖层语义到资源图块坐标的映射表。
	&"wood": Vector2i(6, 1), # 木材资源图块坐标。
	&"stone": Vector2i(6, 3), # 石料资源图块坐标。
} # 资源图块映射表结束。

const TRANSITION_OVERLAY_ATLAS := { # 过渡叠加层定义表，按过渡类型和方向掩码索引。
	&"water_to_land": { # 水体朝陆地过渡时使用的叠加图规则。
		MASK_N: Vector2i(1, 4), # 上方是陆地时叠加的水岸过渡图。
		MASK_E: Vector2i(2, 5), # 右方是陆地时叠加的水岸过渡图。
		MASK_S: Vector2i(3, 6), # 下方是陆地时叠加的水岸过渡图。
		MASK_W: Vector2i(3, 5), # 左方是陆地时叠加的水岸过渡图。
		MASK_NE: Vector2i(2, 4), # 上右两侧是陆地时叠加的拐角过渡图。
		MASK_ES: Vector2i(4, 6), # 右下两侧是陆地时叠加的拐角过渡图。
		MASK_SW: Vector2i(0, 6), # 下左两侧是陆地时叠加的拐角过渡图。
		MASK_WN: Vector2i(0, 4), # 左上两侧是陆地时叠加的拐角过渡图。
		# MASK_NS: Vector2i(1, 4), # 上下两侧是陆地时的临时过渡图坐标。
		# MASK_EW: Vector2i(3, 5), # 左右两侧是陆地时的临时过渡图坐标。
		# MASK_NES: Vector2i(2, 4), # 上右下三侧是陆地时的临时过渡图坐标。
		# MASK_ESW: Vector2i(4, 6), # 右下左三侧是陆地时的临时过渡图坐标。
		# MASK_SWN: Vector2i(5, 6), # 下左上三侧是陆地时的临时过渡图坐标。
		# MASK_WNE: Vector2i(0, 4), # 左上右三侧是陆地时的临时过渡图坐标。
		# MASK_NESW: Vector2i(1, 4), # 四侧都是陆地时的临时过渡图坐标。
	} # water_to_land 过渡规则结束。
} # 过渡叠加定义表结束。

const DIRECTIONAL_BASE_TILE_ATLAS := {} # 完整方向基础图替代方案的预留表，当前未启用。


static func get_base_tile(base_terrain: StringName) -> Vector2i: # 按基础地形语义查询基础图块坐标。
	return BASE_TILE_ATLAS.get(base_terrain, INVALID_ATLAS) # 找到就返回 atlas 坐标，没找到就返回无效坐标。


static func get_resource_tile(resource_type: StringName) -> Vector2i: # 按资源语义查询资源图块坐标。
	return RESOURCE_TILE_ATLAS.get(resource_type, INVALID_ATLAS) # 找到就返回 atlas 坐标，没找到就返回无效坐标。


static func get_transition_tile(transition_name: StringName, mask: int) -> Vector2i: # 按过渡类型和方向掩码查询叠加图块坐标。
	if not TRANSITION_OVERLAY_ATLAS.has(transition_name): # 如果这个过渡类型没有配置，直接返回无效坐标。
		return INVALID_ATLAS # 调用方看到无效坐标后应跳过绘制。
	var transition_tiles: Dictionary = TRANSITION_OVERLAY_ATLAS[transition_name] # 取出该过渡类型下的完整方向映射表。
	return transition_tiles.get(mask, INVALID_ATLAS) # 根据方向掩码取图，没有配置就返回无效坐标。
