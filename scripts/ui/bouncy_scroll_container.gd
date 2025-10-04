extends ScrollContainer
class_name BouncyScrollContainer

@export var enable_vertical: bool = true
@export var enable_horizontal: bool = false
@export_range(16.0, 240.0) var max_overshoot: float = 80.0
@export_range(0.05, 1.0) var drag_resistance: float = 0.55
@export_range(12.0, 160.0) var spring_damping: float = 32.0
@export_range(0.0, 0.06) var content_stretch: float = 0.022
@export var wave_max_children: int = 6
@export_range(0.1, 0.95) var wave_falloff: float = 0.65
@export_range(0.0, 0.1) var wave_strength: float = 0.035
@export_range(0.0, 80.0) var snap_threshold: float = 18.0
@export_range(0.0, 0.06) var in_bounds_stretch: float = 0.015
@export_range(0.0, 0.06) var in_bounds_wave_strength: float = 0.022
@export_range(120.0, 2400.0) var in_bounds_velocity_reference: float = 820.0
@export_range(0.0, 0.8) var direction_change_boost: float = 0.4

const SPEED_SMOOTHING := 18.0
const DIRECTION_BOOST_DECAY := 4.2
const WHEEL_STEP := 52.0
const WEB_WHEEL_MULTIPLIER := 0.3
const WEB_PAN_MULTIPLIER := 0.4

var _content: Control
var _content_base_scale := Vector2.ONE
var _overscroll_v := 0.0
var _overscroll_h := 0.0
var _velocity_v := 0.0
var _velocity_h := 0.0
var _dragging := false
var _last_pointer_pos := Vector2.ZERO
var _last_drag_time_v := 0.0
var _last_drag_time_h := 0.0
var _child_base_scales := {}
var _snap_tween_v: Tween
var _snap_tween_h: Tween
var _snap_active_v := false
var _snap_active_h := false
var _last_scroll_position_v := 0.0
var _smoothed_scroll_speed_v := 0.0
var _last_scroll_direction_v := 0
var _direction_boost_v := 0.0
var _is_web := false

func _ready() -> void:
	_is_web = OS.get_name() == "Web"
	set_physics_process(true)
	call_deferred("_setup_content")
	get_v_scroll_bar().value_changed.connect(_apply_offsets)
	get_h_scroll_bar().value_changed.connect(_apply_offsets)
	_last_scroll_position_v = scroll_vertical

func _setup_content() -> void:
	if get_child_count() == 0: return
	_content = get_child(0) as Control
	if not _content: return
	
	_content_base_scale = _content.scale
	_child_base_scales.clear()
	
	for child in _content.get_children():
		if child is Control:
			_child_base_scales[child] = child.scale
			child.tree_exiting.connect(_on_child_tree_exiting.bind(child))
	
	_content.child_entered_tree.connect(_on_child_added)
	_content.child_exiting_tree.connect(_on_child_removed)
	_apply_offsets()

func _on_child_added(child: Node) -> void:
	if child is Control:
		_child_base_scales[child] = child.scale
		child.tree_exiting.connect(_on_child_tree_exiting.bind(child))
	_apply_offsets()

func _on_child_removed(child: Node) -> void:
	_child_base_scales.erase(child)
	_apply_offsets()

func _on_child_tree_exiting(child: Node) -> void:
	_child_base_scales.erase(child)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_content): return
	
	_update_scroll_metrics(delta)
	
	if not _dragging:
		var return_rate := 1.0 - exp(-spring_damping * delta)
		if enable_vertical and not _snap_active_v and absf(_overscroll_v) > 0.01:
			_overscroll_v = lerpf(_overscroll_v, 0.0, return_rate)
			_velocity_v = 0.0
		if enable_horizontal and not _snap_active_h and absf(_overscroll_h) > 0.01:
			_overscroll_h = lerpf(_overscroll_h, 0.0, return_rate)
			_velocity_h = 0.0
	
	# Force horizontal overscroll to zero if horizontal scrolling is disabled
	if not enable_horizontal and absf(_overscroll_h) > 0.01:
		_overscroll_h = 0.0
		_velocity_h = 0.0
	
	_apply_offsets()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_start_drag(mb.position)
			else:
				_end_drag()
			accept_event()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			if _handle_mouse_wheel(mb):
				accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var global_pos := touch.position
		if _content and _is_interactive_control_at_point(_content, global_pos):
			return
		if touch.pressed:
			_start_drag(touch.position)
		else:
			_end_drag()
		accept_event()
	elif event is InputEventScreenDrag and _dragging:
		var drag := event as InputEventScreenDrag
		_handle_pointer_delta(drag.position - _last_pointer_pos)
		_last_pointer_pos = drag.position
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_handle_pointer_delta(motion.position - _last_pointer_pos)
		_last_pointer_pos = motion.position
		accept_event()
	elif event is InputEventPanGesture:
		if _handle_pan_delta(-(event as InputEventPanGesture).delta):
			accept_event()

func _start_drag(pos: Vector2) -> void:
	_dragging = true
	_last_pointer_pos = pos
	_last_drag_time_v = Time.get_ticks_msec() / 1000.0
	_last_drag_time_h = _last_drag_time_v
	_cancel_snapback(true)
	_cancel_snapback(false)
	_velocity_v = 0.0
	_velocity_h = 0.0

func _end_drag() -> void:
	_dragging = false
	_begin_snapback(true)
	_begin_snapback(false)

func _handle_pointer_delta(delta: Vector2) -> void:
	var handled := false
	if enable_vertical: handled = _apply_axis_drag(delta.y, true) or handled
	if enable_horizontal: handled = _apply_axis_drag(delta.x, false) or handled
	if not handled:
		if enable_vertical:
			scroll_vertical -= int(delta.y)
		if enable_horizontal:
			scroll_horizontal -= int(delta.x)

func _handle_pan_delta(delta: Vector2) -> bool:
	var adjusted_delta := delta
	if _is_web:
		adjusted_delta *= WEB_PAN_MULTIPLIER
	var handled := false
	# Only process the axis that is enabled
	if enable_vertical: 
		handled = _apply_axis_drag(adjusted_delta.y, true) or handled
	if enable_horizontal: 
		handled = _apply_axis_drag(adjusted_delta.x, false) or handled
	# If horizontal is disabled, ignore horizontal pan completely
	elif absf(adjusted_delta.x) > absf(adjusted_delta.y):
		# This is primarily a horizontal pan gesture, so reject it
		return false
	return handled

func _handle_mouse_wheel(event: InputEventMouseButton) -> bool:
	var step := WHEEL_STEP * maxf(1.0, absf(event.factor))
	if _is_web:
		step *= WEB_WHEEL_MULTIPLIER
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP: return _apply_axis_drag(step, true, false)
		MOUSE_BUTTON_WHEEL_DOWN: return _apply_axis_drag(-step, true, false)
		MOUSE_BUTTON_WHEEL_LEFT: return _apply_axis_drag(step, false, false)
		MOUSE_BUTTON_WHEEL_RIGHT: return _apply_axis_drag(-step, false, false)
	return false

func _apply_axis_drag(delta: float, is_vertical: bool, update_velocity: bool = true) -> bool:
	var bar: ScrollBar
	if is_vertical:
		bar = get_v_scroll_bar()
	else:
		bar = get_h_scroll_bar()
	if not bar: return false
	
	var prev_value := bar.value
	var max_value := maxf(0.0, bar.max_value - bar.page)
	var clamped := clampf(prev_value - delta, 0.0, max_value)
	bar.value = clamped
	
	if absf(clamped - prev_value) > 0.05:
		if is_vertical:
			_overscroll_v = lerpf(_overscroll_v, 0.0, 0.7)
			if absf(_overscroll_v) < 0.1: _overscroll_v = 0.0
			_velocity_v = 0.0
			_cancel_snapback(true)
		else:
			_overscroll_h = lerpf(_overscroll_h, 0.0, 0.7)
			if absf(_overscroll_h) < 0.1: _overscroll_h = 0.0
			_velocity_h = 0.0
			_cancel_snapback(false)
		return true
	
	var current := _overscroll_v if is_vertical else _overscroll_h
	var normalized := absf(current) / max_overshoot if max_overshoot > 0.0 else 0.0
	var resistance := 1.0 + (normalized * normalized * 1.8)
	var applied := (delta * drag_resistance) / resistance
	var next := _soft_limit(current + applied, max_overshoot)
	
	if update_velocity:
		_update_drag_velocity(current, next, is_vertical)
	
	if is_vertical: _overscroll_v = next
	else: _overscroll_h = next
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
		if _snap_tween_v and _snap_tween_v.is_running(): _snap_tween_v.kill()
		_snap_tween_v = null
		_snap_active_v = false
	else:
		if _snap_tween_h and _snap_tween_h.is_running(): _snap_tween_h.kill()
		_snap_tween_h = null
		_snap_active_h = false

func _begin_snapback(is_vertical: bool) -> void:
	if is_vertical and not enable_vertical: return
	if not is_vertical and not enable_horizontal: return
	
	var value := _overscroll_v if is_vertical else _overscroll_h
	if absf(value) <= 0.01: return
	
	_cancel_snapback(is_vertical)
	
	var magnitude := minf(absf(value), max_overshoot)
	var normalized := clampf(magnitude / max_overshoot, 0.0, 1.0)
	var duration := lerpf(0.24, 0.36, normalized)
	var property := "_overscroll_v" if is_vertical else "_overscroll_h"
	var overshoot_target := -signf(value) * minf(magnitude * 0.32, maxf(snap_threshold, 0.001))
	
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	
	if absf(overshoot_target) > 0.01:
		tween.tween_property(self, property, overshoot_target, duration * 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, property, 0.0, duration * 0.48).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	else:
		tween.tween_property(self, property, 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	
	tween.finished.connect(_on_snap_finished.bind(is_vertical))
	
	if is_vertical:
		_snap_tween_v = tween
		_snap_active_v = true
		_velocity_v = 0.0
	else:
		_snap_tween_h = tween
		_snap_active_h = true
		_velocity_h = 0.0

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

func _apply_offsets(_val: float = 0.0) -> void:
	if not _content: return
	var x_offset := -scroll_horizontal + _overscroll_h if enable_horizontal else 0.0
	var y_offset := -scroll_vertical + _overscroll_v
	_content.position = Vector2(x_offset, y_offset)
	_apply_content_stretch()
	_apply_child_wave()

func _apply_content_stretch() -> void:
	if not _content: return
	
	var overscroll_amount := clampf(absf(_overscroll_v) / max_overshoot, 0.0, 1.0) if max_overshoot > 0.0 else 0.0
	var velocity_amount := clampf(absf(_smoothed_scroll_speed_v) / maxf(in_bounds_velocity_reference, 1.0) + _direction_boost_v, 0.0, 1.0)
	var stretch_amount := (overscroll_amount * content_stretch) + (velocity_amount * in_bounds_stretch)
	
	if stretch_amount <= 0.0005:
		_content.scale = _content_base_scale
		return
	
	var direction := signf(_overscroll_v)
	if absf(direction) < 0.01: direction = -signf(_smoothed_scroll_speed_v)
	if direction == 0.0 and _last_scroll_direction_v != 0: direction = -float(_last_scroll_direction_v)
	
	var stretch := clampf(1.0 + (stretch_amount * direction), 0.95, 1.05)
	_content.pivot_offset = _content.size * 0.5
	_content.scale = Vector2(_content_base_scale.x, _content_base_scale.y * stretch)

func _apply_child_wave() -> void:
	if not _content:
		_reset_child_wave()
		return
	
	var overscroll_amount := clampf(absf(_overscroll_v) / max_overshoot, 0.0, 1.0) if max_overshoot > 0.0 else 0.0
	var velocity_amount := clampf(absf(_smoothed_scroll_speed_v) / maxf(in_bounds_velocity_reference, 1.0) + _direction_boost_v, 0.0, 1.0)
	var amplitude := (overscroll_amount * wave_strength) + (velocity_amount * in_bounds_wave_strength)
	
	if amplitude <= 0.0005 or wave_max_children <= 0:
		_reset_child_wave()
		return
	
	var direction := signf(_overscroll_v)
	if absf(direction) < 0.01: direction = -signf(_smoothed_scroll_speed_v)
	if direction == 0.0 and _last_scroll_direction_v != 0: direction = -float(_last_scroll_direction_v)
	
	var applied := 0
	for child in _content.get_children():
		if not (child is Control): continue
		var ctrl := child as Control
		var base_scale: Vector2 = _child_base_scales.get(ctrl, ctrl.scale)
		
		if applied < wave_max_children:
			var fall := pow(wave_falloff, float(applied))
			var scale_factor := clampf(1.0 + (direction * amplitude * fall), 0.96, 1.04)
			ctrl.pivot_offset = ctrl.size * 0.5
			ctrl.scale = Vector2(base_scale.x, base_scale.y * scale_factor)
			applied += 1
		else:
			ctrl.scale = base_scale

func _reset_child_wave() -> void:
	for key in _child_base_scales.keys():
		if not is_instance_valid(key): continue
		(key as Control).scale = _child_base_scales[key]

func _update_scroll_metrics(delta: float) -> void:
	var dt := maxf(delta, 0.0001)
	var smoothing := clampf(dt * SPEED_SMOOTHING, 0.0, 1.0)
	
	if enable_vertical:
		var current := scroll_vertical
		var speed := (current - _last_scroll_position_v) / dt
		_smoothed_scroll_speed_v = lerpf(_smoothed_scroll_speed_v, speed, smoothing)
		
		var direction := int(signf(speed)) if absf(speed) > 5.0 else 0
		if direction != 0 and direction != _last_scroll_direction_v:
			_direction_boost_v = direction_change_boost
		
		_direction_boost_v = maxf(_direction_boost_v - dt * DIRECTION_BOOST_DECAY, 0.0)
		
		if direction != 0: _last_scroll_direction_v = direction
		elif _direction_boost_v <= 0.0001: _last_scroll_direction_v = 0
		
		_last_scroll_position_v = current
	else:
		_smoothed_scroll_speed_v = lerpf(_smoothed_scroll_speed_v, 0.0, smoothing)
		_direction_boost_v = maxf(_direction_boost_v - dt * DIRECTION_BOOST_DECAY, 0.0)
		if _direction_boost_v <= 0.0001: _last_scroll_direction_v = 0
		_last_scroll_position_v = scroll_vertical

func _soft_limit(value: float, limit: float) -> float:
	if limit <= 0.0: return 0.0
	var magnitude := absf(value)
	var cap := limit * 0.98
	if magnitude <= cap: return value
	var excess := magnitude - cap
	var softened := cap + (excess / (1.0 + excess * 1.4))
	return signf(value) * minf(softened, limit)

func _is_interactive_control_at_point(control: Control, global_point: Vector2) -> bool:
	if not control.visible or control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false

	var local_point: Vector2 = control.get_global_transform().affine_inverse() * global_point
	if not Rect2(Vector2.ZERO, control.size).has_point(local_point):
		return false

	if _is_control_interactive(control):
		return true

	for child in control.get_children():
		if child is Control and _is_interactive_control_at_point(child as Control, global_point):
			return true

	return false

func _is_control_interactive(control: Control) -> bool:
	if control is BaseButton:
		return true
	if control is LineEdit or control is TextEdit:
		return true
	if control is SpinBox or control is OptionButton:
		return true
	if control is ScrollBar or control is Slider:
		return true
	if control.focus_mode != Control.FOCUS_NONE:
		return true
	if control.mouse_filter == Control.MOUSE_FILTER_STOP and control.is_in_group("contact_cards"):
		return true
	return false
