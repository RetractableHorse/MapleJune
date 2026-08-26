class_name Player
extends CharacterBody2D

@export_range(1.0, 5000.0) var max_speed := 325.0
@export_range(1.0, 5000.0) var move_acceleration := 750.0

## Velocity when turning around to face the other way.
## Set higher than `move_acceleration` to let the player turn a bit tighter
@export_range(1.0, 5000.0) var turnaround_acceleration := 1100.0

## How fast you slow down on the ground
@export_range(1.0, 5000.0) var ground_friction := 500.0

## How fast you slow down in the air
@export_range(1.0, 5000.0) var air_friction := 50.0

@export_range(1.0, 5000.0) var jump_speed := 440.0
@export_range(1.0, 5000.0) var dash_jump_speed := 500.0
@export_range(1.0, 5000.0) var gravity := 1800.0
@export_range(0.0, 1.0, 0.01) var max_jump_time := 0.2

## Grace period for when the player can jump after leaving the ground
@export_range(0.0, 1.0, 0.01) var max_coyote_time := 0.1

## Grace period for when the player can jump right before hitting the ground
@export_range(0.0, 1.0, 0.01) var max_trampoline_time := 0.08

@export_range(1.0, 5000.0) var dash_speed := 500.0
@export_range(0.0, 5.0, 0.05) var max_dash_time := 0.4
@export var infinite_dash := false
@export_range(1.0, 5000.0) var dash_air_impulse := 150.0
@export_range(1.0, 5000.0) var dash_gravity := 300.0

signal state_changed(state: State)

enum State {
	IDLE,
	FALLING,
	WALKING,
	RUNNING,
	JUMPING,
	DASHING,
	DEAD,
}

var state := State.IDLE:
	set(new_state):
		state = new_state
		state_changed.emit(new_state)

var movement := 0.0
var facing := 1
var dash_facing := 1
var remaining_dash_time := 0.0
var remaining_jump_time := 0.0
var remaining_coyote_time := 0.0
var remaining_trampoline_time := 0.0

@onready var sprite_container: Node2D = $SpriteContainer

var is_dashing: bool:
	get:
		return remaining_dash_time > 0.0


func reset() -> void:
	velocity = Vector2()
	state = State.IDLE


func _process(_delta: float) -> void:
	movement = Input.get_axis("move_left", "move_right")

	if Input.is_action_just_pressed("jump"):
		_start_jump()

	if Input.is_action_just_released("jump"):
		_finish_jump()

	if Input.is_action_just_pressed("dash"):
		_start_dash()

	if Input.is_action_just_released("dash"):
		_finish_dash()

	if movement != 0:
		facing = int(signf(movement))

	sprite_container.scale.x = facing


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if _check_fallout_death():
		return

	_process_state(delta)
	move_and_slide()


func _process_state(delta: float) -> void:
	match state:
		State.IDLE:
			_apply_ground_friction(delta)

			velocity.y = 0

			if _check_falling():
				return

			if is_on_floor() and movement != 0:
				state = State.WALKING

		State.FALLING:
			_apply_movement_accel(delta)
			_apply_gravity(delta)

			remaining_coyote_time -= delta
			remaining_trampoline_time -= delta

			if is_on_floor():
				if remaining_trampoline_time > 0:
					state = State.JUMPING
					remaining_jump_time = max_jump_time
				else:
					state = State.IDLE
					velocity.y = 0

		State.WALKING:
			_apply_movement_accel(delta)

			if not is_on_floor():
				state = State.FALLING

			if movement == 0:
				state = State.IDLE

		State.RUNNING:
			pass

		State.JUMPING:
			_apply_movement_accel(delta)

			var applied_jump_speed = jump_speed

			if is_dashing:
				applied_jump_speed = dash_jump_speed

			velocity.y = -applied_jump_speed
			remaining_jump_time -= delta

			if remaining_jump_time < 0:
				state = State.FALLING

		State.DASHING:
			velocity.x = dash_facing * dash_speed

			# while dashing, if we're moving upward, apply lessened gravity to move downward,
			# but once we're level, stay level
			velocity.y = minf(velocity.y + dash_gravity * delta, 0)

			if infinite_dash:
				return

			remaining_dash_time -= delta
			if remaining_dash_time < 0:
				if is_on_floor():
					state = State.IDLE
				else:
					state = State.FALLING


func _apply_gravity(delta: float) -> void:
	velocity.y += gravity * delta


func _apply_ground_friction(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, ground_friction * delta)


func _apply_movement_accel(delta: float) -> void:
	velocity.x = move_toward(velocity.x, max_speed * movement, move_acceleration * delta)


func _check_falling() -> bool:
	if is_on_floor():
		return false

	state = State.FALLING
	remaining_coyote_time = max_coyote_time
	return true


func _check_fallout_death() -> bool:
	if global_position.y > 1000:
		velocity = Vector2()
		state = State.DEAD
		return true

	return false


func _update_movement_velocity(delta: float):
	if movement == 0:
		var friction := ground_friction

		if not is_on_floor():
			friction = air_friction

		velocity.x = move_toward(velocity.x, 0, friction * delta)
		return

	if is_dashing:
		remaining_dash_time -= delta
		velocity.x = dash_speed * movement
		return

	var accel := move_acceleration

	if signf(movement) != signf(velocity.x):
		accel = turnaround_acceleration

	velocity.x = move_toward(velocity.x, max_speed * movement, accel * delta)


func _start_jump():
	var is_falling_with_remaining_coyote_time := (
		state == State.FALLING and remaining_coyote_time > 0
	)

	var can_jump = is_on_floor() or is_falling_with_remaining_coyote_time

	if can_jump:
		state = State.JUMPING
		remaining_jump_time = max_jump_time
	else:
		# if we can't jump, reset the remaining trampoline time,
		# so a jump can happen later if we hit the ground before it reaches 0
		remaining_trampoline_time = max_trampoline_time


func _finish_jump():
	if state == State.JUMPING:
		state = State.FALLING


func _start_dash() -> void:
	#if state != State.GROUNDED:
	#velocity.y -= dash_air_impulse
	state = State.DASHING
	dash_facing = facing
	remaining_dash_time = max_dash_time


func _finish_dash() -> void:
	remaining_dash_time = 0.0
	if not is_on_floor():
		state = State.FALLING
	elif movement != 0:
		state = State.WALKING
	else:
		state = State.IDLE
