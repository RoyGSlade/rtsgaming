class_name ChunkManager
extends Node

var chunks: Dictionary = {}

func set_chunk(chunk: ChunkData) -> void:
    chunks[chunk.chunk_position] = chunk

func get_chunk(chunk_position: Vector2i) -> ChunkData:
    return chunks.get(chunk_position, null)

func has_chunk(chunk_position: Vector2i) -> bool:
    return chunks.has(chunk_position)

func unload_chunk(chunk_position: Vector2i) -> void:
    chunks.erase(chunk_position)

func get_loaded_positions() -> Array:
    return chunks.keys()
