class_name DynamicResolutionController
extends Node

## Adaptive 3D resolution scaling: samples framerate and nudges the viewport's
## 3D render scale down when the GPU falls behind and back up when it has
## headroom, so the game holds a target framerate on weaker hardware without a
## fixed-quality compromise. The 2D/UI layer is never scaled - only the 3D
## world is rendered at a lower internal resolution and upscaled.
##
## "Smart when available": when the backend exposes a RenderingDevice
## (Forward+/Mobile) the downscaled image is upscaled with FSR 2 (temporal,
## sharp) instead of plain bilinear; on the Compatibility backend, or at native
## resolution, it stays bilinear. FSR 2 is only engaged while actually
## upscaling so native rendering pays no temporal-upscaler cost.
##
## The scale decision lives in the pure static compute_next_scale() so the
## hysteresis logic is unit-testable without a viewport or a running frame loop.

## Framerate to hold. 0 = follow the monitor's refresh rate.
@export var target_fps := 0
@export var min_scale := 0.5
@export var max_scale := 1.0
## How much to change scale per adjustment. Small steps keep changes subtle.
@export var step := 0.05
## Seconds between adjustments - long enough to average out a frame spike.
@export var sample_interval := 0.5
@export var enabled := true

## Optional HUD label; when set, shows the current render scale and framerate.
var status_label: Label

var _viewport: Viewport
var _fsr_available := false
var _scale := 1.0
var _accum := 0.0


func _ready() -> void:
	_viewport = get_viewport()
	_fsr_available = RenderingServer.get_rendering_device() != null
	if _viewport != null:
		_scale = _viewport.scaling_3d_scale
	_apply_scale()


func _process(delta: float) -> void:
	if not enabled or _viewport == null:
		return
	_accum += delta
	if _accum < sample_interval:
		return
	_accum = 0.0
	var fps := Engine.get_frames_per_second()
	var target := _target_fps()
	var next := compute_next_scale(_scale, fps, float(target), min_scale, max_scale, step)
	if not is_equal_approx(next, _scale):
		_scale = next
		_apply_scale()
	_update_label(fps, target)


## Target framerate, resolving 0 to the monitor refresh rate (60 if unknown).
func _target_fps() -> int:
	if target_fps > 0:
		return target_fps
	var refresh := DisplayServer.screen_get_refresh_rate()
	return int(round(refresh)) if refresh > 0.0 else 60


## Pure scaling decision with hysteresis: drop a step when clearly below target,
## climb a step when comfortably above it, hold inside the dead-band between
## (0.90x..0.98x of target) so the scale doesn't oscillate every sample.
static func compute_next_scale(current: float, fps: float, target: float, low: float, high: float, delta_step: float) -> float:
	if target <= 0.0:
		return current
	if fps < target * 0.90:
		return clampf(current - delta_step, low, high)
	if fps > target * 0.98:
		return clampf(current + delta_step, low, high)
	return current


func _apply_scale() -> void:
	if _viewport == null:
		return
	_viewport.scaling_3d_scale = _scale
	# Only pay for the temporal upscaler while actually upscaling; render at
	# native resolution with cheap bilinear (a no-op at scale 1.0).
	if _scale < 0.999 and _fsr_available:
		_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	else:
		_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR


func _update_label(fps: float, target: int) -> void:
	if status_label == null:
		return
	var mode := "FSR2" if (_scale < 0.999 and _fsr_available) else "native"
	status_label.text = "Render %d%% (%s) · %d/%d fps" % [
		int(round(_scale * 100.0)), mode, int(round(fps)), target
	]
