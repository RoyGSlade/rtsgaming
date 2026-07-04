class_name WaterSpan
extends RefCounted

## A contiguous vertical run of water blocks in one XZ column, as derived
## live from WaterFlowSimulator's current state. Transient render-time data
## (never serialized), unlike WaterCell which is exported on ChunkData.

var surface_y: int = 0
var floor_y: int = 0

## Depth in blocks. surface_y and floor_y are both block indices of water
## blocks (inclusive), so a single-block-deep span is depth 1, not 0 - the
## depth texture and shore-foam shader treat 0 as "no water at all".
func depth() -> float:
	return float(surface_y - floor_y + 1)
