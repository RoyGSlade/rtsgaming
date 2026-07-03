class_name OverlayStateMap
extends RefCounted

## Per-cell runtime state (damage/wetness/mud/snow) that the terrain shader
## blends against dedicated overlay texture-array layers. Nothing in the
## codebase triggers these automatically yet (no combat/weather/season
## systems exist) — this is the plumbing future gameplay systems call into
## via set_value().

enum Channel { DAMAGE, WETNESS, MUD, SNOW }

var width: int
var depth: int

var _image: Image
var _texture: ImageTexture
var _dirty := false

func _init(map_width: int, map_depth: int) -> void:
    width = maxi(1, map_width)
    depth = maxi(1, map_depth)
    _image = Image.create(width, depth, false, Image.FORMAT_RGBA8)
    _image.fill(Color(0, 0, 0, 0))
    _texture = ImageTexture.create_from_image(_image)

func set_value(x: int, z: int, channel: Channel, value: float) -> void:
    if x < 0 or x >= width or z < 0 or z >= depth:
        return
    var color := _image.get_pixel(x, z)
    value = clampf(value, 0.0, 1.0)
    match channel:
        Channel.DAMAGE:
            color.r = value
        Channel.WETNESS:
            color.g = value
        Channel.MUD:
            color.b = value
        Channel.SNOW:
            color.a = value
    _image.set_pixel(x, z, color)
    _dirty = true

func get_value(x: int, z: int, channel: Channel) -> float:
    if x < 0 or x >= width or z < 0 or z >= depth:
        return 0.0
    var color := _image.get_pixel(x, z)
    match channel:
        Channel.DAMAGE:
            return color.r
        Channel.WETNESS:
            return color.g
        Channel.MUD:
            return color.b
        Channel.SNOW:
            return color.a
    return 0.0

func get_texture() -> ImageTexture:
    if _dirty:
        _texture.update(_image)
        _dirty = false
    return _texture
