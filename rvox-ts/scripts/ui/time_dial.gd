class_name TimeDial
extends Control

## A drawn (not texture-based) circular clock face for scrubbing
## SunMoonRig.time_of_day on demand. Click/drag anywhere in the dial to
## set the time directly; the auto-advancing day/night cycle keeps
## running from wherever it's set (no separate pause/resume control —
## day_length_seconds is long enough that a drag doesn't visibly fight it).
## sun_moon_rig is assigned directly by game_main.gd (same integration
## point everything else in this scene is wired through), not resolved
## via an exported NodePath.

const TICK_COUNT := 4
const HAND_COLOR := Color(1.0, 1.0, 1.0, 0.85)

var sun_moon_rig: SunMoonRig
var _dragging := false

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
    queue_redraw()

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        _dragging = event.pressed
        if event.pressed:
            _set_time_from_point(event.position)
    elif event is InputEventMouseMotion and _dragging:
        _set_time_from_point(event.position)

func _set_time_from_point(point: Vector2) -> void:
    if sun_moon_rig == null:
        return
    var center: Vector2 = size * 0.5
    var offset: Vector2 = point - center
    if offset.length() < 1.0:
        return
    var angle: float = atan2(offset.y, offset.x)
    var t: float = (angle + PI * 0.5) / TAU
    sun_moon_rig.time_of_day = fmod(t + 1.0, 1.0)
    queue_redraw()

func _draw() -> void:
    var radius: float = minf(size.x, size.y) * 0.5 - 4.0
    var center: Vector2 = size * 0.5

    var face_color: Color = Color(0.15, 0.16, 0.22, 0.9)
    var accent_color: Color = HAND_COLOR
    if sun_moon_rig != null:
        face_color = sun_moon_rig.sky_horizon_color.darkened(0.35)
        face_color.a = 0.92

    draw_circle(center, radius, face_color)
    draw_arc(center, radius, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.35), 1.5, true)

    for i in TICK_COUNT:
        var t: float = float(i) / float(TICK_COUNT)
        var a: float = _time_to_angle(t)
        var dir: Vector2 = Vector2(cos(a), sin(a))
        draw_line(center + dir * (radius - 8.0), center + dir * radius, Color(1.0, 1.0, 1.0, 0.5), 2.0)

    if sun_moon_rig == null:
        return

    var current_angle: float = _time_to_angle(sun_moon_rig.time_of_day)
    var hand_dir: Vector2 = Vector2(cos(current_angle), sin(current_angle))
    var handle: Vector2 = center + hand_dir * (radius - 12.0)
    var handle_color: Color = sun_moon_rig.sun_color if sun_moon_rig.daylight_factor > 0.15 else sun_moon_rig.moon_color

    draw_line(center, handle, accent_color, 2.0)
    draw_circle(handle, 6.0, handle_color)
    draw_circle(center, 2.5, accent_color)

    var hours: int = int(sun_moon_rig.time_of_day * 24.0) % 24
    var minutes: int = int(fmod(sun_moon_rig.time_of_day * 24.0, 1.0) * 60.0)
    var label := "%02d:%02d" % [hours, minutes]
    var font: Font = ThemeDB.fallback_font
    var font_size := 13
    var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
    draw_string(font, center - text_size * 0.5 + Vector2(0.0, text_size.y * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1, 1, 1, 0.9))

## 0.0 (midnight) points up; time advances clockwise, matching a clock face.
func _time_to_angle(t: float) -> float:
    return t * TAU - PI * 0.5
