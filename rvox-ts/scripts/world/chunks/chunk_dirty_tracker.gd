class_name ChunkDirtyTracker
extends RefCounted

var dirty_chunks: Dictionary = {}

func mark_dirty(chunk_position: Vector2i) -> void:
    dirty_chunks[chunk_position] = true

func clear_dirty(chunk_position: Vector2i) -> void:
    dirty_chunks.erase(chunk_position)

func pop_all_dirty() -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for key in dirty_chunks.keys():
        result.append(key)
    dirty_chunks.clear()
    return result
