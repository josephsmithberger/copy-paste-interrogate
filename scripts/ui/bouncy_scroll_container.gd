extends ScrollContainer
class_name BouncyScrollContainer

## iMessage-inspired elastic scroll with crisp S-curve snap and element wave.
## Fast initial response, smooth sustain, then rapid snap-back.

@export var enable_vertical: bool = true
@export var enable_horizontal: bool = false
@export_range(16.0, 240.0, 1.0) var max_overshoot: float = 80.0
@export_range(0.05, 1.0, 0.01) var drag_resistance: float = 0.28
@export_range(120.0, 1200.0, 10.0) var spring_stiffness: float = 680.0
@export_range(12.0, 160.0, 1.0) var spring_damping: float = 52.0
@export_range(0.0, 0.06, 0.002) var content_stretch: float = 0.022
@export var wave_max_children: int = 6
@export_range(0.1, 0.95, 0.05) var wave_falloff: float = 0.65
@export_range(0.0, 0.1, 0.002) var wave_strength: float = 0.035
@export_range(0.0, 80.0, 0.5) var snap_threshold: float = 18.0
@export_range(0.0, 0.06, 0.002) var in_bounds_stretch: float = 0.015
@export_range(0.0, 0.06, 0.002) var in_bounds_wave_strength: float = 0.022
@export_range(120.0, 2400.0, 10.0) var in_bounds_velocity_reference: float = 820.0
@export_range(0.0, 0.8, 0.05) var direction_change_boost: float = 0.4

const SPEED_SMOOTHING := 18.0
const DIRECTION_BOOST_DECAY := 4.2

const WHEEL_STEP := 52.0

var _content: Control
var _content_base_scale: Vector2 = Vector2.ONE
var _overscroll_v: float = 0.0
var _overscroll_h: float = 0.0
var _velocity_v: float = 0.0
var _velocity_h: float = 0.0
var _dragging: bool = false
var _drag_pointer_index: int = -1
var _last_pointer_pos: Vector2 = Vector2.ZERO
var _last_drag_time_v: float = 0.0
var _last_drag_time_h: float = 0.0
var _child_base_scales: Dictionary = {}
var _snap_tween_v: Tween
var _snap_tween_h: Tween
var _snap_active_v: bool = false
var _snap_active_h: bool = false
var _last_scroll_position_v: float = 0.0
var _smoothed_scroll_speed_v: float = 0.0
var _last_scroll_direction_v: int = 0
var _direction_boost_v: float = 0.0

func _ready() -> void:
	set_physics_process(true)
	call_deferred("_ensure_content_ready")
	_connect_scrollbars()
	_capture_initial_scroll_positions()

func _ensure_content_ready() -> void:
	if get_child_count() == 0:
		return
	_content = get_child(0) as Control
	if _content == null:
		return
	_content_base_scale = _content.scale
	_child_base_scales.clear()
	for child in _content.get_children():
		_cache_child_scale(child)
	if not _content.is_connected("child_entered_tree", Callable(self, "_on_content_child_entered")):
		_content.child_entered_tree.connect(Callable(self, "_on_content_child_entered"))
	if not _content.is_connected("child_exiting_tree", Callable(self, "_on_content_child_exiting")):
		_content.child_exiting_tree.connect(Callable(self, "_on_content_child_exiting"))
	_apply_offsets()

func _cache_child_scale(node: Node) -> void:
	if node is Control:
		var ctrl := node as Control
		_child_base_scales[ctrl] = ctrl.scale
		if not ctrl.is_connected("tree_exiting", Callable(self, "_on_child_tree_exiting")):
			ctrl.tree_exiting.connect(Callable(self, "_on_child_tree_exiting").bind(ctrl))

func _on_content_child_entered(child: Node) -> void:
	_cache_child_scale(child)
	_apply_offsets()

func _on_content_child_exiting(child: Node) -> void:
	if child in _child_base_scales:
		_child_base_scales.erase(child)
	_apply_offsets()

func _on_child_tree_exiting(ctrl: Control) -> void:
	if ctrl in _child_base_scales:
		_child_base_scales.erase(ctrl)

func _connect_scrollbars() -> void:
	var vbar := get_v_scroll_bar()
	if vbar and not vbar.is_connected("value_changed", Callable(self, "_on_scrollbar_changed")):
		vbar.value_changed.connect(Callable(self, "_on_scrollbar_changed"))
	var hbar := get_h_scroll_bar()
	if hbar and not hbar.is_connected("value_changed", Callable(self, "_on_scrollbar_changed")):
		hbar.value_changed.connect(Callable(self, "_on_scrollbar_changed"))

func _on_scrollbar_changed(_value: float) -> void:
	_apply_offsets()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_content):
		return
	_update_scroll_metrics(delta)
	if not _dragging:
		var return_rate := 1.0 - exp(-spring_damping * delta)
		if enable_vertical and not _snap_active_v and absf(_overscroll_v) > 0.01:
			_overscroll_v = lerpf(_overscroll_v, 0.0, return_rate)
			_velocity_v = 0.0
		if enable_horizontal and not _snap_active_h and absf(_overscroll_h) > 0.01:
			_overscroll_h = lerpf(_overscroll_h, 0.0, return_rate)
			_velocity_h = 0.0
	_apply_offsets()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_start_drag(mouse_event.position, mouse_event.device)
				accept_event()
				return
			else:
				_end_drag()
				accept_event()
				return
		elif mouse_event.pressed and mouse_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			var wheel_handled := _handle_mouse_wheel(mouse_event)
			if wheel_handled:
				accept_event()
			return
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_handle_pointer_delta(motion.position - _last_pointer_pos)
		_last_pointer_pos = motion.position
		accept_event()
		return
	elif event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		var handled := _handle_pan_delta(-pan.delta)
		if handled:
			accept_event()
			return

func _start_drag(pointer_position: Vector2, pointer_index: int) -> void:
	_dragging = true
	_drag_pointer_index = pointer_index
	_last_pointer_pos = pointer_position
	_last_drag_time_v = Time.get_ticks_msec() / 1000.0
	_last_drag_time_h = _last_drag_time_v
	_cancel_snapback(true)
	_cancel_snapback(false)
	_velocity_v = 0.0
	_velocity_h = 0.0

func _end_drag() -> void:
	_dragging = false
	_drag_pointer_index = -1
	_begin_snapback(true)
	_begin_snapback(false)

func _handle_pointer_delta(delta: Vector2) -> void:
	var handled := false
	if enable_vertical:
		handled = _apply_axis_drag(delta.y, true) or handled
	if enable_horizontal:
		handled = _apply_axis_drag(delta.x, false) or handled
	if not handled:
		scroll_vertical -= int(delta.y)
		scroll_horizontal -= int(delta.x)

func _handle_pan_delta(delta: Vector2) -> bool:
	var handled := false
	if enable_vertical:
		handled = _apply_axis_drag(delta.y, true) or handled
	if enable_horizontal:
		handled = _apply_axis_drag(delta.x, false) or handled
	return handled

func _handle_mouse_wheel(event: InputEventMouseButton) -> bool:
	var step := WHEEL_STEP * maxf(1.0, absf(event.factor))
	var handled := false
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			handled = _apply_axis_drag(step, true, false)
		MOUSE_BUTTON_WHEEL_DOWN:
			handled = _apply_axis_drag(-step, true, false)
		MOUSE_BUTTON_WHEEL_LEFT:
			handled = _apply_axis_drag(step, false, false)
		MOUSE_BUTTON_WHEEL_RIGHT:
			handled = _apply_axis_drag(-step, false, false)
	return handled

func _apply_axis_drag(delta: float, is_vertical: bool, update_velocity: bool = true) -> bool:
	var bar: ScrollBar = null
	if is_vertical:
		bar = get_v_scroll_bar()
	else:
		bar = get_h_scroll_bar()
	if bar == null:
		return false
	var prev_value: float = bar.value
	var max_value: float = maxf(0.0, bar.max_value - bar.page)
	var unclamped: float = prev_value - delta
	var clamped: float = clampf(unclamped, 0.0, max_value)
	bar.value = clamped
	var consumed := absf(clamped - prev_value) > 0.05
	if consumed:
		if is_vertical:
			# Quick decay of overscroll when scrolling normally (Apple feels responsive).
			_overscroll_v = lerpf(_overscroll_v, 0.0, 0.55)
			if absf(_overscroll_v) < 0.1:
				_overscroll_v = 0.0
			_velocity_v = 0.0
			_cancel_snapback(true)
		else:
			_overscroll_h = lerpf(_overscroll_h, 0.0, 0.55)
			if absf(_overscroll_h) < 0.1:
				_overscroll_h = 0.0
			_velocity_h = 0.0
			_cancel_snapback(false)
		return true

	# Progressive resistance: never hard-stop, but exponentially harder to drag further.
	var current_overscroll := _overscroll_v if is_vertical else _overscroll_h
	var normalized := 0.0
	if max_overshoot > 0.0:
		normalized = absf(current_overscroll) / max_overshoot
	# Quadratic resistance curve (Apple's characteristic soft wall).
	var resistance := 1.0 + (normalized * normalized * 3.2)
	var applied := (delta * drag_resistance) / resistance
	var next := current_overscroll + applied
	next = _soft_limit(next, max_overshoot)
	if update_velocity:
		_update_drag_velocity(current_overscroll, next, is_vertical)
	if is_vertical:
		_overscroll_v = next
	else:
		_overscroll_h = next
	return true

func _update_drag_velocity(previous: float, current: float, is_vertical: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var last := _last_drag_time_v if is_vertical else _last_drag_time_h
	var dt := maxf(now - last, 0.0001)
	var velocity := (current - previous) / dt
	if is_vertical:
		_velocity_v = velocity
		_last_drag_time_v = now
	else:
		_velocity_h = velocity
		_last_drag_time_h = now

func _cancel_snapback(is_vertical: bool) -> void:
	if is_vertical:
		if _snap_tween_v and _snap_tween_v.is_running():
			_snap_tween_v.kill()
		_snap_tween_v = null
		_snap_active_v = false
	else:
		if _snap_tween_h and _snap_tween_h.is_running():
			_snap_tween_h.kill()
		_snap_tween_h = null
		_snap_active_h = false

func _begin_snapback(is_vertical: bool) -> void:
	if is_vertical:
		if not enable_vertical:
			return
		var value := _overscroll_v
		if absf(value) <= 0.01:
			return
		_cancel_snapback(true)
		var magnitude: float = minf(absf(value), max_overshoot)
		var normalized: float = clampf(magnitude / max_overshoot, 0.0, 1.0)
		# Apple's S-curve: quick start, sustained middle, snap finish.
		var duration: float = lerpf(0.24, 0.36, normalized)
		var property := "_overscroll_v"
		var overshoot_limit: float = maxf(snap_threshold, 0.001)
		# Reduced overshoot factor for tighter feel (Apple uses minimal reverse bounce).
		var overshoot_target: float = -signf(value) * minf(magnitude * 0.32, overshoot_limit)
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		if absf(overshoot_target) > 0.01:
			# Fast out of gate (QUART = x⁴, sharper than SINE).
			tween.tween_property(self, property, overshoot_target, duration * 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
			# Quick snap back (EXPO for rapid finish).
			tween.tween_property(self, property, 0.0, duration * 0.48).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		else:
			# Single phase with CUBIC for smooth S when overshoot is negligible.
			tween.tween_property(self, property, 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_snap_tween_v = tween
		_snap_active_v = true
		_velocity_v = 0.0
		_overscroll_v = value
		_snap_tween_v.finished.connect(Callable(self, "_on_snap_finished").bind(true))
	else:
		if not enable_horizontal:
			return
		var value_h := _overscroll_h
		if absf(value_h) <= 0.01:
			return
		_cancel_snapback(false)
		var magnitude_h: float = minf(absf(value_h), max_overshoot)
		var normalized_h: float = clampf(magnitude_h / max_overshoot, 0.0, 1.0)
		var duration_h: float = lerpf(0.24, 0.36, normalized_h)
		var property_h := "_overscroll_h"
		var overshoot_limit_h: float = maxf(snap_threshold, 0.001)
		var overshoot_target_h: float = -signf(value_h) * minf(magnitude_h * 0.32, overshoot_limit_h)
		var tween_h := create_tween()
		tween_h.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		if absf(overshoot_target_h) > 0.01:
			tween_h.tween_property(self, property_h, overshoot_target_h, duration_h * 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
			tween_h.tween_property(self, property_h, 0.0, duration_h * 0.48).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		else:
			tween_h.tween_property(self, property_h, 0.0, duration_h).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_snap_tween_h = tween_h
		_snap_active_h = true
		_velocity_h = 0.0
		_overscroll_h = value_h
		_snap_tween_h.finished.connect(Callable(self, "_on_snap_finished").bind(false))

func _on_snap_finished(is_vertical: bool) -> void:
	if is_vertical:
		_snap_active_v = false
		_snap_tween_v = null
		_overscroll_v = 0.0
		_velocity_v = 0.0
	else:
		_snap_active_h = false
		_snap_tween_h = null
		_overscroll_h = 0.0
		_velocity_h = 0.0

func _apply_offsets() -> void:
	if _content == null:
		return
	# Base ScrollContainer offset (the internal scroll position) + elastic overshoot.
	var base_offset := Vector2(-scroll_horizontal, -scroll_vertical)
	var elastic_offset := Vector2(_overscroll_h, _overscroll_v)
	_content.position = base_offset + elastic_offset
	_apply_content_stretch()
	_apply_child_wave()

func _apply_content_stretch() -> void:
	if _content == null:
		return
	var overscroll_amount := 0.0
	if max_overshoot > 0.0:
		overscroll_amount = clampf(absf(_overscroll_v) / max_overshoot, 0.0, 1.0)
	var velocity_amount := clampf(absf(_smoothed_scroll_speed_v) / maxf(in_bounds_velocity_reference, 1.0), 0.0, 1.0)
	velocity_amount = clampf(velocity_amount + _direction_boost_v, 0.0, 1.0)
	var stretch_amount := (overscroll_amount * content_stretch) + (velocity_amount * in_bounds_stretch)
	if stretch_amount <= 0.0005:
		_content.scale = _content_base_scale
		return
	var direction := signf(_overscroll_v)
	if absf(direction) < 0.01:
		direction = -signf(_smoothed_scroll_speed_v)
	if direction == 0.0 and _last_scroll_direction_v != 0:
		direction = -float(_last_scroll_direction_v)
	# Tighter scale range for subtlety (Apple prefers understated visual feedback).
	var stretch := clampf(1.0 + (stretch_amount * direction), 0.95, 1.05)
	_content.pivot_offset = _content.size * 0.5
	_content.scale = Vector2(_content_base_scale.x, _content_base_scale.y * stretch)

func _apply_child_wave() -> void:
	if _content == null:
		_reset_child_wave()
		return
	var overscroll_amount := 0.0
	if max_overshoot > 0.0:
		overscroll_amount = clampf(absf(_overscroll_v) / max_overshoot, 0.0, 1.0)
	var velocity_amount := clampf(absf(_smoothed_scroll_speed_v) / maxf(in_bounds_velocity_reference, 1.0), 0.0, 1.0)
	velocity_amount = clampf(velocity_amount + _direction_boost_v, 0.0, 1.0)
	var amplitude := (overscroll_amount * wave_strength) + (velocity_amount * in_bounds_wave_strength)
	if amplitude <= 0.0005 or wave_max_children <= 0:
		_reset_child_wave()
		return
	var direction := signf(_overscroll_v)
	if absf(direction) < 0.01:
		direction = -signf(_smoothed_scroll_speed_v)
	if direction == 0.0 and _last_scroll_direction_v != 0:
		direction = -float(_last_scroll_direction_v)
	var applied := 0
	for child in _content.get_children():
		if not (child is Control):
			continue
		var ctrl := child as Control
		var base_scale: Vector2 = _child_base_scales.get(ctrl, ctrl.scale)
		if applied < wave_max_children:
			var fall := pow(wave_falloff, float(applied))
			# Tighter scale range (Apple's elements compress subtly, not dramatically).
			var scale_factor := clampf(1.0 + (direction * amplitude * fall), 0.96, 1.04)
			ctrl.pivot_offset = ctrl.size * 0.5
			ctrl.scale = Vector2(base_scale.x, base_scale.y * scale_factor)
			applied += 1
		else:
			ctrl.scale = base_scale

func _reset_child_wave() -> void:
	for key in _child_base_scales.keys():
		if not is_instance_valid(key):
			continue
		var ctrl := key as Control
		ctrl.scale = _child_base_scales[key]

func _capture_initial_scroll_positions() -> void:
	_last_scroll_position_v = scroll_vertical

func _update_scroll_metrics(delta: float) -> void:
	var dt := maxf(delta, 0.0001)
	var smoothing := clampf(dt * SPEED_SMOOTHING, 0.0, 1.0)
	if enable_vertical:
		var current_v := scroll_vertical
		var delta_v := current_v - _last_scroll_position_v
		var speed_v := delta_v / dt
		_smoothed_scroll_speed_v = lerpf(_smoothed_scroll_speed_v, speed_v, smoothing)
		var direction_v := 0
		if absf(speed_v) > 5.0:
			direction_v = int(signf(speed_v))
		if direction_v != 0 and direction_v != _last_scroll_direction_v:
			_direction_boost_v = direction_change_boost
		_direction_boost_v = maxf(_direction_boost_v - dt * DIRECTION_BOOST_DECAY, 0.0)
		if direction_v != 0:
			_last_scroll_direction_v = direction_v
		elif _direction_boost_v <= 0.0001:
			_last_scroll_direction_v = 0
		_last_scroll_position_v = current_v
	else:
		_smoothed_scroll_speed_v = lerpf(_smoothed_scroll_speed_v, 0.0, smoothing)
		_direction_boost_v = maxf(_direction_boost_v - dt * DIRECTION_BOOST_DECAY, 0.0)
		if _direction_boost_v <= 0.0001:
			_last_scroll_direction_v = 0
		_last_scroll_position_v = scroll_vertical

func _soft_limit(value: float, limit: float) -> float:
	# Apple's rubber-band physics: logarithmic resistance, never a hard stop.
	if limit <= 0.0:
		return 0.0
	var magnitude := absf(value)
	var cap := limit * 0.98
	if magnitude <= cap:
		return value
	var excess := magnitude - cap
	# More aggressive softening curve for tighter feel.
	var softened := cap + (excess / (1.0 + excess * 1.4))
	return signf(value) * minf(softened, limit)
