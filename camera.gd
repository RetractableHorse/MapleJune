extends Camera2D
## Player Camera with Zone Support
##
## TWO MODES OF OPERATION:
## 1. DEFAULT MODE - Follows player with lookahead, pan, and idle reset
##    (Active when not inside any CameraZone)
## 2. ZONE MODE - Uses CameraZone settings for axis locking, limits, zoom
##    (Active when player enters a CameraZone Area2D)
##
## Zones are ideal for slower platforming sections where you want precise
## camera control. Default mode handles fast movement with momentum-aware lookahead.

# ================================================================
# FOLLOW
# ================================================================
@export_group("Follow")
@export var target_path: NodePath
@export var follow_speed: float = 5.0

# ================================================================
# FORWARD LOOKAHEAD
# ================================================================
@export_group("Forward Lookahead")
@export var enable_lookahead: bool = true
@export var lookahead_requires_momentum: bool = false
@export var lookahead_distance: float = 40.0
@export var lookahead_speed: float = 2.0
@export var lookahead_speed_threshold: float = 50.0
@export var lookahead_direction_delay: float = 0.15

# ================================================================
# LOOK AHEAD / PAN (Hold to Look)
# ================================================================
@export_group("Pan (Hold to Look)")
@export var pan_hold_delay: float = 0.5
@export var pan_speed: float = 3.0

@export_subgroup("Vertical Pan")
@export var enable_up_pan: bool = true
@export var enable_down_pan: bool = true
@export var vertical_pan_distance: float = 80.0

@export_subgroup("Horizontal Pan")
@export var enable_left_pan: bool = false
@export var enable_right_pan: bool = false
@export var horizontal_pan_distance: float = 60.0

# ================================================================
# CAMERA LIMITS (Defaults)
# ================================================================
@export_group("Default Limits")
@export var use_default_limits: bool = true
@export var default_limit_left: int = -10000000
@export var default_limit_right: int = 10000000
@export var default_limit_top: int = -10000000
@export var default_limit_bottom: int = 10000000

# ================================================================
# ROOM SCROLL (Celeste-style)
# ================================================================
@export_group("Room Scroll")

enum RoomTransitionStyle {
	INSTANT,
	SMOOTH,
	SMOOTH_FREEZE,
	FADE,
}

@export var default_room_transition: RoomTransitionStyle = RoomTransitionStyle.SMOOTH_FREEZE
@export var room_transition_min_time: float = 0.15
@export var room_transition_max_time: float = 0.5
@export var room_transition_duration_override: float = -1.0
@export var room_fade_duration: float = 0.3

# ================================================================
# SPEED ZOOM
# ================================================================
@export_group("Speed Zoom")
@export var enable_speed_zoom: bool = false
@export var speed_zoom_base: float = 1.0
@export var speed_zoom_min: float = 0.85
@export var speed_zoom_threshold: float = 100.0
@export var speed_zoom_max_speed: float = 500.0
@export var speed_zoom_smoothing: float = 3.0
@export var speed_zoom_lookahead_bonus: float = 1.5

# ================================================================
# IDLE RESET
# ================================================================
@export_group("Idle Reset")
@export var enable_idle_reset: bool = true
@export var idle_reset_delay: float = 2.0
@export var idle_reset_speed: float = 2.0

# ================================================================
# CAMERA MOTION
# ================================================================
@export_group("Camera Motion")
@export var enable_walk_bob: bool = true
@export var walk_bob_amplitude: float = 2.0
@export var walk_bob_frequency: float = 10.0

@export var enable_airborne_float: bool = true
@export var airborne_follow_mult: float = 0.45

@export var enable_land_impact: bool = true
@export var land_impact_strength: float = 5.0
@export var land_impact_max: float = 12.0
@export var land_impact_recovery: float = 12.0
@export var land_impact_min_speed: float = 150.0

@export var enable_damage_reaction: bool = true
@export var damage_punch_intensity: float = 8.0
@export var damage_punch_duration: float = 0.2

# ================================================================
# DEBUG
# ================================================================
@export_group("Debug")
##does not work - no connection
@export var show_speed: bool = false
##does not work - no connection
@export var show_zone_debug: bool = false

# ================================================================
# INPUT ACTIONS (configurable)
# ================================================================
@export_group("Input Actions")
@export var input_move_left: StringName = &"move_left"
@export var input_move_right: StringName = &"move_right"
@export var input_move_up: StringName = &"move_up"
@export var input_move_down: StringName = &"move_down"

# ================================================================
# INTERNAL
# ================================================================
var target: Node2D
var true_position: Vector2
var pan_offset: Vector2 = Vector2.ZERO
var target_pan_offset: Vector2 = Vector2.ZERO
var hold_timer: float = 0.0
var last_input: Vector2 = Vector2.ZERO

var lookahead_offset: Vector2 = Vector2.ZERO
var target_lookahead: Vector2 = Vector2.ZERO
var current_lookahead_direction: float = 0.0
var direction_change_timer: float = 0.0

var idle_timer: float = 0.0
var last_target_position: Vector2 = Vector2.ZERO

var _speed_zoom_current: float = 1.0
var _speed_zoom_lookahead_mult: float = 1.0

# Zone state
var current_zone: Area2D = null
var zone_offset: Vector2 = Vector2.ZERO
var lock_x_axis: bool = false
var lock_y_axis: bool = false
var locked_x_position: float = 0.0
var locked_y_position: float = 0.0
var active_follow_speed: float

# Room scroll state
var current_room: Area2D = null
var room_target_limits: Rect2
var room_transitioning: bool = false
var _room_transition_style: RoomTransitionStyle = RoomTransitionStyle.INSTANT
var _room_fade_rect: ColorRect = null
var _room_player: CharacterBody2D = null
var _room_tween: Tween = null
var _room_tween_duration_override: float = -1.0

signal room_entered(room: Area2D)
signal room_exited(room: Area2D)
signal room_transition_started()
signal room_transition_finished()

# Motion state
var _walk_bob_phase: float = 0.0
var _motion_offset: Vector2 = Vector2.ZERO
var _land_impact_offset: float = 0.0
var _was_airborne: bool = false
var _pre_land_fall_speed: float = 0.0
var _damage_punch_tween: Tween

# Shake state
var _shake_tween: Tween
var _shake_offset: Vector2 = Vector2.ZERO
var _base_offset: Vector2 = Vector2.ZERO

var cutscene_active: bool = false

# Finisher focus
var _finisher_focus_active: bool = false
var _pre_finisher_zoom: Vector2 = Vector2.ONE
var _finisher_zoom_tween: Tween


func _ready() -> void:
	if target_path:
		target = get_node(target_path)
	true_position = global_position
	position_smoothing_enabled = false
	active_follow_speed = follow_speed
	_speed_zoom_current = speed_zoom_base

	if target:
		last_target_position = target.global_position

	if use_default_limits:
		limit_left = default_limit_left
		limit_right = default_limit_right
		limit_top = default_limit_top
		limit_bottom = default_limit_bottom

	_setup_room_fade_rect()
	_room_player = target as CharacterBody2D
	if not _room_player and target:
		_room_player = get_tree().get_first_node_in_group("player") as CharacterBody2D


func _physics_process(delta: float) -> void:
	if not target:
		return
	if cutscene_active:
		return

	if not room_transitioning:
		_handle_idle_reset(delta)
		_handle_pan_input(delta)
		_handle_speed_zoom(delta)
		_handle_lookahead(delta)
		_handle_camera_motion(delta)

		pan_offset = pan_offset.lerp(target_pan_offset, pan_speed * delta)
		lookahead_offset = lookahead_offset.lerp(target_lookahead, lookahead_speed * delta)

	var target_pos: Vector2
	if current_zone:
		target_pos = _calculate_zone_target()
	else:
		target_pos = _calculate_default_target()

	var effective_follow := active_follow_speed
	if not room_transitioning and enable_airborne_float and _is_target_airborne():
		effective_follow *= airborne_follow_mult

	true_position = true_position.lerp(target_pos, effective_follow * delta)

	if current_room:
		var half_vp: Vector2 = _get_base_viewport_size() / zoom * 0.5
		var r: Rect2 = room_target_limits
		true_position.x = clampf(true_position.x, r.position.x + half_vp.x, maxf(r.end.x - half_vp.x, r.position.x + half_vp.x))
		true_position.y = clampf(true_position.y, r.position.y + half_vp.y, maxf(r.end.y - half_vp.y, r.position.y + half_vp.y))

	global_position = (true_position + _motion_offset).round()


func _calculate_default_target() -> Vector2:
	return target.global_position + pan_offset + lookahead_offset


func _calculate_zone_target() -> Vector2:
	var base_target = target.global_position
	if lock_x_axis:
		base_target.x = locked_x_position
	if lock_y_axis:
		base_target.y = locked_y_position
	return base_target + zone_offset


func _is_target_stationary() -> bool:
	if target.has_method("is_on_floor") and not target.is_on_floor():
		return false
	if "velocity" in target:
		return target.velocity.length() < 5.0
	return true


func _handle_idle_reset(delta: float) -> void:
	if not enable_idle_reset:
		return
	var is_idle := _is_target_stationary()
	var has_moved := target.global_position.distance_to(last_target_position) > 1.0
	var has_input := false
	if Input.is_action_pressed(input_move_left) or Input.is_action_pressed(input_move_right):
		has_input = true
	if Input.is_action_pressed(input_move_up) or Input.is_action_pressed(input_move_down):
		has_input = true
	last_target_position = target.global_position
	if is_idle and not has_moved and not has_input:
		idle_timer += delta
	else:
		idle_timer = 0.0


func _is_idle_resetting() -> bool:
	return enable_idle_reset and idle_timer >= idle_reset_delay


func _handle_lookahead(delta: float) -> void:
	if not enable_lookahead:
		target_lookahead = Vector2.ZERO
		return
	if lookahead_requires_momentum:
		var has_momentum = false
		if "abilities" in target and target.abilities is Dictionary:
			has_momentum = target.abilities.get("momentum", false)
		if not has_momentum:
			target_lookahead = Vector2.ZERO
			return
	if _is_idle_resetting():
		target_lookahead = Vector2.ZERO
		return
	var target_velocity := Vector2.ZERO
	if "velocity" in target:
		target_velocity = target.velocity
	var speed := absf(target_velocity.x)
	if speed < lookahead_speed_threshold:
		target_lookahead = Vector2.ZERO
		current_lookahead_direction = 0.0
		direction_change_timer = 0.0
		return
	var desired_direction := signf(target_velocity.x)
	if desired_direction != current_lookahead_direction:
		direction_change_timer += delta
		if direction_change_timer >= lookahead_direction_delay:
			current_lookahead_direction = desired_direction
			direction_change_timer = 0.0
	else:
		direction_change_timer = 0.0
	var speed_factor = clampf(speed / 300.0, 0.0, 1.0)
	var lookahead_amount = lookahead_distance * speed_factor * _speed_zoom_lookahead_mult
	target_lookahead.x = current_lookahead_direction * lookahead_amount


func _handle_pan_input(delta: float) -> void:
	if _is_idle_resetting():
		hold_timer = 0.0
		last_input = Vector2.ZERO
		target_pan_offset = Vector2.ZERO
		return
	if not _is_target_stationary():
		hold_timer = 0.0
		last_input = Vector2.ZERO
		target_pan_offset = Vector2.ZERO
		return
	var input := Vector2.ZERO
	if enable_up_pan and Input.is_action_pressed(input_move_up):
		input.y = -1
	elif enable_down_pan and Input.is_action_pressed(input_move_down):
		input.y = 1
	if enable_left_pan and Input.is_action_pressed(input_move_left):
		input.x = -1
	elif enable_right_pan and Input.is_action_pressed(input_move_right):
		input.x = 1
	if input != Vector2.ZERO:
		if input == last_input:
			hold_timer += delta
		else:
			hold_timer = 0.0
		last_input = input
	else:
		hold_timer = 0.0
		last_input = Vector2.ZERO
	if hold_timer >= pan_hold_delay:
		target_pan_offset.y = input.y * vertical_pan_distance
		target_pan_offset.x = input.x * horizontal_pan_distance
	else:
		target_pan_offset = Vector2.ZERO


func _handle_speed_zoom(delta: float) -> void:
	if _finisher_focus_active:
		return
	if not enable_speed_zoom:
		_speed_zoom_lookahead_mult = 1.0
		return
	if current_zone:
		_speed_zoom_lookahead_mult = 1.0
		return
	var speed := 0.0
	if "velocity" in target:
		speed = target.velocity.length()
	var t := clampf(
		(speed - speed_zoom_threshold) / maxf(speed_zoom_max_speed - speed_zoom_threshold, 1.0),
		0.0, 1.0
	)
	var eased_t := 1.0 - pow(1.0 - t, 2.0)
	var target_zoom_val := lerpf(speed_zoom_base, speed_zoom_min, eased_t)
	_speed_zoom_current = lerpf(_speed_zoom_current, target_zoom_val, speed_zoom_smoothing * delta)
	zoom = Vector2(_speed_zoom_current, _speed_zoom_current)
	var zoom_ratio := (speed_zoom_base - _speed_zoom_current) / maxf(speed_zoom_base - speed_zoom_min, 0.001)
	_speed_zoom_lookahead_mult = lerpf(1.0, speed_zoom_lookahead_bonus, zoom_ratio)


# ================================================================
# ZONE INTERFACE
# ================================================================

func enter_camera_zone(zone: Area2D) -> void:
	current_zone = zone
	if zone.has_method("get_camera_settings"):
		var settings = zone.get_camera_settings()
		_apply_zone_settings(settings)


func exit_camera_zone(zone: Area2D) -> void:
	if current_zone == zone:
		_reset_to_defaults()


func _apply_zone_settings(settings: Dictionary) -> void:
	lock_x_axis = settings.get("lock_x", false)
	lock_y_axis = settings.get("lock_y", false)
	if lock_x_axis:
		locked_x_position = settings.get("lock_x_position", global_position.x)
	if lock_y_axis:
		locked_y_position = settings.get("lock_y_position", global_position.y)
	active_follow_speed = settings.get("follow_speed", follow_speed)
	zone_offset = settings.get("camera_offset", Vector2.ZERO)
	if settings.has("limit_left"):
		limit_left = settings.limit_left
		limit_right = settings.limit_right
		limit_top = settings.limit_top
		limit_bottom = settings.limit_bottom
	if settings.has("zoom_level"):
		var target_zoom: Vector2 = settings.zoom_level
		if zoom != target_zoom:
			var tween = create_tween()
			tween.tween_property(self, "zoom", target_zoom, 0.3).set_ease(Tween.EASE_OUT)


func _reset_to_defaults() -> void:
	current_zone = null
	lock_x_axis = false
	lock_y_axis = false
	locked_x_position = 0.0
	locked_y_position = 0.0
	zone_offset = Vector2.ZERO
	active_follow_speed = follow_speed
	if current_room:
		_snap_room_limits(room_target_limits)
	elif use_default_limits:
		limit_left = default_limit_left
		limit_right = default_limit_right
		limit_top = default_limit_top
		limit_bottom = default_limit_bottom
	_speed_zoom_current = speed_zoom_base if enable_speed_zoom else 1.0
	var restore_zoom := Vector2(_speed_zoom_current, _speed_zoom_current)
	if zoom != restore_zoom:
		var tween = create_tween()
		tween.tween_property(self, "zoom", restore_zoom, 0.3).set_ease(Tween.EASE_OUT)


# ================================================================
# ROOM SCROLL
# ================================================================

func enter_room(room: Area2D, room_rect: Rect2, style_override: int = -1, duration_override: float = -1.0) -> void:
	var old_room = current_room
	if old_room == room:
		return
	if room_transitioning:
		if _room_tween and _room_tween.is_valid():
			_room_tween.kill()
		room_transitioning = false
		if _room_player and "external_control" in _room_player:
			_room_player.external_control = false
	current_room = room
	room_target_limits = room_rect
	if old_room == null:
		_snap_room_limits(room_rect)
		room_entered.emit(room)
		return
	var style: RoomTransitionStyle
	if style_override >= 0:
		style = style_override as RoomTransitionStyle
	else:
		style = default_room_transition
	_room_transition_style = style
	_room_tween_duration_override = duration_override
	match style:
		RoomTransitionStyle.INSTANT:
			_snap_room_limits(room_rect)
			room_entered.emit(room)
		RoomTransitionStyle.SMOOTH:
			_start_room_tween(room_rect, false)
		RoomTransitionStyle.SMOOTH_FREEZE:
			_start_room_tween(room_rect, true)
		RoomTransitionStyle.FADE:
			room_transitioning = true
			room_transition_started.emit()
			if _room_player and "external_control" in _room_player:
				_room_player.external_control = true
				_room_player.velocity = Vector2.ZERO
			_do_room_fade_transition.call_deferred(room_rect)
	if old_room:
		room_exited.emit(old_room)


func snap_to_room(room: Area2D, room_rect: Rect2) -> void:
	if _room_tween and _room_tween.is_valid():
		_room_tween.kill()
	current_room = room
	room_target_limits = room_rect
	_snap_room_limits(room_rect)
	room_transitioning = false
	if _room_player and "external_control" in _room_player:
		_room_player.external_control = false


func exit_room() -> void:
	if _room_tween and _room_tween.is_valid():
		_room_tween.kill()
	var old_room = current_room
	current_room = null
	room_transitioning = false
	if use_default_limits:
		limit_left = default_limit_left
		limit_right = default_limit_right
		limit_top = default_limit_top
		limit_bottom = default_limit_bottom
	if old_room:
		room_exited.emit(old_room)


func _snap_room_limits(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)


func _get_base_viewport_size() -> Vector2:
	var w = ProjectSettings.get_setting("display/window/size/viewport_width", 360)
	var h = ProjectSettings.get_setting("display/window/size/viewport_height", 270)
	return Vector2(w, h)


func _start_room_tween(rect: Rect2, freeze_player: bool) -> void:
	if _room_tween and _room_tween.is_valid():
		_room_tween.kill()
	_room_transition_style = RoomTransitionStyle.SMOOTH_FREEZE if freeze_player else RoomTransitionStyle.SMOOTH
	room_transition_started.emit()
	lookahead_offset = Vector2.ZERO
	target_lookahead = Vector2.ZERO
	pan_offset = Vector2.ZERO
	target_pan_offset = Vector2.ZERO
	_motion_offset = Vector2.ZERO
	_land_impact_offset = 0.0
	_snap_room_limits(rect)
	var vp_size: Vector2 = _get_base_viewport_size()
	var half_vp: Vector2 = vp_size * 0.5
	var target_pos: Vector2 = Vector2(
		clampf(target.global_position.x, rect.position.x + half_vp.x, maxf(rect.end.x - half_vp.x, rect.position.x + half_vp.x)),
		clampf(target.global_position.y, rect.position.y + half_vp.y, maxf(rect.end.y - half_vp.y, rect.position.y + half_vp.y))
	)
	var dist: float = true_position.distance_to(target_pos)
	var settle_time: float
	if _room_tween_duration_override > 0.0:
		settle_time = _room_tween_duration_override
		_room_tween_duration_override = -1.0
	elif room_transition_duration_override > 0.0:
		settle_time = room_transition_duration_override
	else:
		settle_time = clampf(dist / 600.0, room_transition_min_time, room_transition_max_time)
	if freeze_player and _room_player and "external_control" in _room_player:
		_room_player.external_control = true
		_room_player.velocity = Vector2.ZERO
	room_transitioning = true
	if freeze_player:
		_room_tween = create_tween()
		_room_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		_room_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		_room_tween.tween_property(self, "true_position", target_pos, settle_time)
		_room_tween.finished.connect(_finish_room_transition)
	else:
		var saved_follow: float = active_follow_speed
		active_follow_speed = maxf(follow_speed * 3.0, 15.0)
		_room_tween = create_tween()
		_room_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		_room_tween.tween_interval(settle_time)
		_room_tween.finished.connect(func() -> void:
			active_follow_speed = saved_follow
			_finish_room_transition()
		)


func _do_room_fade_transition(rect: Rect2) -> void:
	if not _room_fade_rect:
		_snap_room_limits(rect)
		_finish_room_transition()
		return
	var tw := create_tween()
	tw.tween_property(_room_fade_rect, "color:a", 1.0, room_fade_duration)
	await tw.finished
	var vp_size: Vector2 = _get_base_viewport_size()
	var half_vp: Vector2 = vp_size * 0.5
	var snap_pos: Vector2 = target.global_position
	snap_pos.x = clampf(snap_pos.x, rect.position.x + half_vp.x, maxf(rect.end.x - half_vp.x, rect.position.x + half_vp.x))
	snap_pos.y = clampf(snap_pos.y, rect.position.y + half_vp.y, maxf(rect.end.y - half_vp.y, rect.position.y + half_vp.y))
	true_position = snap_pos
	global_position = snap_pos.round()
	_snap_room_limits(rect)
	force_update_scroll()
	await get_tree().create_timer(0.05).timeout
	tw = create_tween()
	tw.tween_property(_room_fade_rect, "color:a", 0.0, room_fade_duration)
	await tw.finished
	_finish_room_transition()


func _finish_room_transition() -> void:
	if _room_player and "external_control" in _room_player:
		_room_player.external_control = false
	room_transitioning = false
	room_transition_finished.emit()
	room_entered.emit(current_room)


func _setup_room_fade_rect() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	canvas.name = "RoomFadeLayer"
	add_child(canvas)
	_room_fade_rect = ColorRect.new()
	_room_fade_rect.color = Color(0, 0, 0, 0)
	_room_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(_room_fade_rect)


# ================================================================
# CAMERA SHAKE
# ================================================================

func shake(intensity: float, duration: float = 0.0) -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	if duration <= 0.0:
		duration = clampf(intensity * 0.03, 0.08, 0.35)
	var steps := clampi(int(intensity * 1.5), 4, 12)
	var step_time := duration / steps
	_shake_tween = create_tween()
	for i in steps:
		var decay := 1.0 - (float(i) / steps)
		var mag := intensity * decay
		_shake_tween.tween_callback(func():
			offset = _base_offset + Vector2(
				randf_range(-mag, mag),
				randf_range(-mag, mag)
			)
		)
		_shake_tween.tween_interval(step_time)
	_shake_tween.tween_callback(func(): offset = _base_offset)


# ================================================================
# CAMERA MOTION
# ================================================================

func _is_target_airborne() -> bool:
	if target and target.has_method("is_on_floor"):
		return not target.is_on_floor()
	return false


func _handle_camera_motion(delta: float) -> void:
	var airborne := _is_target_airborne()
	if _was_airborne and not airborne:
		_on_landed()
	if airborne and "velocity" in target:
		_pre_land_fall_speed = maxf(_pre_land_fall_speed, target.velocity.y)
	if not airborne:
		_pre_land_fall_speed = 0.0
	_was_airborne = airborne
	var bob_y := 0.0
	if enable_walk_bob and not airborne and target and "velocity" in target:
		var speed := absf(target.velocity.x)
		if speed > 20.0:
			var freq := walk_bob_frequency * clampf(speed / 200.0, 0.6, 1.5)
			_walk_bob_phase += freq * delta * TAU
			if _walk_bob_phase > TAU:
				_walk_bob_phase -= TAU
			bob_y = sin(_walk_bob_phase) * walk_bob_amplitude * clampf(speed / 100.0, 0.0, 1.0)
		else:
			_walk_bob_phase = move_toward(_walk_bob_phase, 0.0, delta * 8.0)
			bob_y = sin(_walk_bob_phase) * walk_bob_amplitude * 0.3
	else:
		_walk_bob_phase = move_toward(_walk_bob_phase, 0.0, delta * 8.0)
	_land_impact_offset = move_toward(_land_impact_offset, 0.0, land_impact_recovery * delta)
	_motion_offset = Vector2(0.0, bob_y + _land_impact_offset)


func _on_landed() -> void:
	if not enable_land_impact:
		return
	if _pre_land_fall_speed < land_impact_min_speed:
		return
	var t := clampf((_pre_land_fall_speed - land_impact_min_speed) / 400.0, 0.0, 1.0)
	_land_impact_offset = lerpf(land_impact_strength, land_impact_max, t)


# ================================================================
# FINISHER FOCUS
# ================================================================

func finisher_focus_in(target_pos: Vector2, zoom_amount: float = 1.6, duration: float = 0.15) -> void:
	if _finisher_focus_active:
		return
	_finisher_focus_active = true
	_pre_finisher_zoom = zoom
	if _finisher_zoom_tween and _finisher_zoom_tween.is_valid():
		_finisher_zoom_tween.kill()
	_finisher_zoom_tween = create_tween()
	_finisher_zoom_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_finisher_zoom_tween.tween_property(self, "zoom", Vector2(zoom_amount, zoom_amount), duration)


func finisher_focus_out(duration: float = 0.3) -> void:
	if not _finisher_focus_active:
		return
	_finisher_focus_active = false
	if _finisher_zoom_tween and _finisher_zoom_tween.is_valid():
		_finisher_zoom_tween.kill()
	_finisher_zoom_tween = create_tween()
	_finisher_zoom_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_finisher_zoom_tween.tween_property(self, "zoom", _pre_finisher_zoom, duration)


func damage_punch(source_dir: Vector2 = Vector2.ZERO) -> void:
	if not enable_damage_reaction:
		return
	if _damage_punch_tween and _damage_punch_tween.is_valid():
		_damage_punch_tween.kill()
	var punch_dir: Vector2
	if source_dir.length() > 0.1:
		punch_dir = source_dir.normalized()
	else:
		punch_dir = Vector2(randf_range(-1, 1), randf_range(-0.5, -1)).normalized()
	var punch := punch_dir * damage_punch_intensity
	offset = _base_offset + punch
	_damage_punch_tween = create_tween()
	_damage_punch_tween.tween_property(self, "offset", _base_offset, damage_punch_duration)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
