class_name HeightmapViewer
extends Node

func print_heightmap(chunk: ChunkData) -> void:
    for z in chunk.chunk_size:
        var line := ""
        for x in chunk.chunk_size:
            line += "%02d " % chunk.get_surface_height(x, z)
        print(line)
