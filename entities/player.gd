extends CharacterBody2D

@export_group("Movement")
@export_range(1.0, 5000.0) var max_speed := 750.0
@export_range(1.0, 5000.0) var move_acceleration := 1500.0

## Velocity when turning around to face the other way.
## Set higher than `move_acceleration` to let the player turn a bit tighter
@export_range(1.0, 5000.0) var turnaround_acceleration := 2200.0

## How fast you slow down on the ground
@export_range(1.0, 5000.0) var ground_friction := 1000.0

## How fast you slow down in the air
@export_range(1.0, 5000.0) var air_friction := 100.0

@export_group("Jumping")
@export_range(1.0, 5000.0) var jump_velocity := 700.0
@export_range(1.0, 5000.0) var gravity := 2500.0
@export_range(0.0, 1.0, 0.01) var max_jump_time := 0.2

## Grace period for when the player can jump after leaving the ground
@export_range(0.0, 1.0, 0.01) var max_coyote_time := 0.1

## Grace period for when the player can jump right before hitting the ground
@export_range(0.0, 1.0, 0.01) var max_trampoline_time := 0.08

signal died

enum JumpState {
	GROUNDED,
	JUMPING,
	FALLING,
}

var movement := 0.0

var jump_state := JumpState.GROUNDED
var remaining_jump_time := 0.0
var remaining_coyote_time := 0.0
var remaining_trampoline_time := 0.0

var dead := false


func reset() -> void:
	velocity = Vector2()
	dead = false


func _process(_delta: float) -> void:
	movement = Input.get_axis("move_left", "move_right")

	if Input.is_action_just_pressed("jump"):
		_start_jump()

	if Input.is_action_just_released("jump"):
		_finish_jump()


func _physics_process(delta: float) -> void:
	if dead:
		return

	if global_position.y > 1000:
		velocity = Vector2()
		dead = true
		died.emit()

	if movement == 0:
		var friction := ground_friction if is_on_floor() else air_friction
		velocity.x = move_toward(velocity.x, 0, friction * delta)
	else:
		var accel := move_acceleration

		if signf(movement) != signf(velocity.x):
			accel = turnaround_acceleration

		velocity.x = move_toward(velocity.x, max_speed * movement, accel * delta)

	_update_jump(delta)

	move_and_slide()


func _start_jump():
	var has_grounded_state := jump_state == JumpState.GROUNDED

	var is_falling_with_remaining_coyote_time := (
		jump_state == JumpState.FALLING and remaining_coyote_time > 0
	)

	var can_jump = has_grounded_state or is_falling_with_remaining_coyote_time

	if can_jump:
		jump_state = JumpState.JUMPING
		remaining_jump_time = max_jump_time
	else:
		# if we can't jump, reset the remaining trampoline time,
		# so a jump can happen later if we hit the ground before it reaches 0
		remaining_trampoline_time = max_trampoline_time


func _finish_jump():
	if jump_state == JumpState.JUMPING:
		jump_state = JumpState.FALLING


func _update_jump(delta: float):
	match jump_state:
		JumpState.GROUNDED:
			velocity.y = 0

			if not is_on_floor():
				jump_state = JumpState.FALLING
				remaining_coyote_time = max_coyote_time

		JumpState.JUMPING:
			velocity.y = -jump_velocity
			remaining_jump_time -= delta

			if remaining_jump_time < 0:
				jump_state = JumpState.FALLING

		JumpState.FALLING:
			velocity.y += gravity * delta
			remaining_coyote_time -= delta
			remaining_trampoline_time -= delta

			if is_on_floor():
				if remaining_trampoline_time > 0:
					jump_state = JumpState.JUMPING
					remaining_jump_time = max_jump_time
				else:
					jump_state = JumpState.GROUNDED
					velocity.y = 0
