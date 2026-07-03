class_name WorldDebugOverlay
extends Node

func print_chunk_summary(chunk: ChunkData) -> void:
    print("Chunk %s dirty=%s" % [chunk.chunk_position, chunk.dirty])
    print("grass=%s dirt=%s stone=%s water=%s trees=%s" % [
        chunk.count_block(&"grass"),
        chunk.count_block(&"dirt"),
        chunk.count_block(&"stone"),
        chunk.count_block(&"water"),
        chunk.count_block(&"oak_log")
    ])
