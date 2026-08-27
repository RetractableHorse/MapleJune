class_name Player
extends CharacterBody2D

@export_category("Walking & Running")
@export_range(1.0, 5000.0) var max_speed := 325.0
@export_range(1.0, 5000.0) var move_acceleration := 750.0

## Velocity when turning around to face the other way.
## Set higher than `move_acceleration` to let the player turn a bit tighter
@export_range(1.0, 5000.0) var turnaround_acceleration := 1100.0

## How fast you slow down on the ground
@export_range(1.0, 5000.0) var ground_friction := 500.0


@export_category("Jumping")
## How fast you slow down in the air
@export_range(1.0, 5000.0) var air_friction := 50.0

@export_range(1.0, 5000.0) var jump_speed := 440.0
@export_range(1.0, 5000.0) var gravity := 1800.0
@export_range(0.0, 1.0, 0.01) var max_jump_time := 0.2

## Grace period for when the player can jump after leaving the ground
@export_range(0.0, 1.0, 0.01) var max_coyote_time := 0.1

## Grace period for when the player can jump right before hitting the ground
@export_range(0.0, 1.0, 0.01) var max_trampoline_time := 0.08


@export_category("Dashing")
@export_range(1.0, 5000.0) var dash_speed := 500.0
@export_range(1.0, 5000.0) var dash_air_impulse := 150.0
@export_range(1.0, 5000.0) var dash_gravity := 300.0
@export_range(1.0, 5000.0) var dash_jump_speed := 500.0
@export var infinite_dash := false
@export_range(0.0, 5.0, 0.05) var max_dash_time := 0.4

signal state_changed(state: State)

enum State {
	IDLE,
	FALLING,
	RUNNING,
	JUMPING,
	DASHING,
	WALL_SLIDE,
	DEAD,
}

## for values that should only ever be -1 or 1, never 0
enum Direction {
	LEFT = -1,
	RIGHT = 1,
}

var state := State.IDLE:
	set(new_state):
		_handle_state_event(ExitStateEvent.new())
		state = new_state
		state_changed.emit(new_state)
		_handle_state_event(EnterStateEvent.new())

var movement := 0.0
var facing := Direction.RIGHT:
	set(value):
		if Direction.find_key(value):
			facing = value

var jump_requested := false
var remaining_jump_time := 0.0
var remaining_coyote_time := 0.0
var remaining_trampoline_time := 0.0

var dash_facing := Direction.RIGHT
var remaining_dash_time := 0.0

var _just_jumped_from_wall_slide := false

# using a separate transform node for the sprite so the sprite's own transform
# can be configured independent of us flipping it (or whatever else)
@onready var sprite_transform: Node2D = %SpriteTransform


func reset() -> void:
	velocity = Vector2()
	state = State.IDLE


func _physics_process(delta: float) -> void:
	movement = Input.get_axis("move_left", "move_right")

	if Input.is_action_just_pressed("jump"):
		_handle_state_event(StartJumpEvent.new())

	if Input.is_action_just_released("jump"):
		_handle_state_event(FinishJumpEvent.new())

	if Input.is_action_just_pressed("dash"):
		_handle_state_event(StartDashEvent.new())

	if Input.is_action_just_released("dash"):
		_handle_state_event(FinishDashEvent.new())

	if state == State.DEAD:
		return

	if _check_fallout_death():
		return

	_handle_state_event(UpdateEvent.new(delta))
	move_and_slide()

	sprite_transform.scale.x = facing


# aight here's the Entire Thing™️
# the player should have different behaviors in each state depending on what happens,
# and we're using this weird-looking event setup to put together all of the code
# for each of those different things that happen. for example,
# this lets us define what should happen when we enter the jump state,
# and _while_ we're jumping (or anything other event) in the same place,
# and not scattered in some separate `_start_jump()` method with its own state checks and logic
func _handle_state_event(event: StateEvent) -> void:
	match state:
		State.IDLE:
			if event is StartJumpEvent:
				state = State.JUMPING

			if event is UpdateEvent:
				_apply_ground_friction(event.delta)

				velocity.y = 0

				if _check_falling():
					return

				if is_on_floor() and movement != 0:
					state = State.RUNNING

		State.RUNNING:
			if event is StartJumpEvent:
				state = State.JUMPING

			if event is UpdateEvent:
				if movement == 0:
					state = State.IDLE
					return

				if signf(movement) == -signf(velocity.x):
					_apply_turnaround_accel(event.delta)
				else:
					_apply_movement_accel(event.delta)

				if _check_wall_slide():
					return

				if not is_on_floor():
					state = State.FALLING

					# we could put this in "enter" for falling,
					# but we only want to set this if we go from running to falling,
					# because any other case is just... falling,
					# e.g. from idle, it'd be because a platform disappeared,
					# and from wall slide, because we ran out of wall to slide on
					remaining_coyote_time = max_coyote_time
					return

				_apply_gravity(event.delta)
				_apply_facing_from_movement()

		State.FALLING:
			if event is StartJumpEvent:
				if remaining_coyote_time > 0:
					remaining_coyote_time = 0
					state = State.JUMPING
					return

				if is_on_wall_only():
					state = State.JUMPING
					velocity.x = get_wall_normal().x * 300.0
					_apply_facing_from_movement()
					return

				remaining_trampoline_time = max_trampoline_time

			if event is UpdateEvent:
				# only apply gravity if we have no more coyote time
				# this prevents a dumb quirk where the player dips for a bit after going off a ledge,
				# and makes the coyote time jump look smoother
				if remaining_coyote_time > 0:
					velocity.y = 0
				else:
					_apply_gravity(event.delta)

				if movement == 0:
					_apply_air_friction(event.delta)
				else:
					_apply_movement_accel(event.delta)

				if is_on_floor():
					if remaining_trampoline_time > 0:
						state = State.JUMPING
						remaining_jump_time = max_jump_time
					elif movement != 0:
						state = State.RUNNING
					else:
						state = State.IDLE

				if _check_wall_slide():
					return

				if is_on_wall_only():
					_apply_inverse_wall_facing()
				else:
					_apply_facing_from_movement()

				remaining_trampoline_time -= event.delta
				remaining_coyote_time -= event.delta

		State.JUMPING:
			if event is EnterStateEvent:
				remaining_jump_time = max_jump_time

			if event is FinishJumpEvent:
				remaining_jump_time = 0.0
				state = State.FALLING

			if event is UpdateEvent:
				if is_on_wall_only():
					_apply_inverse_wall_facing()
				else:
					_apply_facing_from_movement()

				if movement == 0:
					_apply_air_friction(event.delta)
				else:
					_apply_movement_accel(event.delta)

				velocity.y = -jump_speed

				remaining_jump_time -= event.delta

				if remaining_jump_time < 0:
					state = State.FALLING

				# when we go to jumping from wall sliding, technically the character
				# hasn't `move_and_slide()`d away from the wall at this point,
				# so it'll re-trigger the wall slide check and go right back to the wall slide
				# ...while in the air, jumping, which is the weirdest fuckin thing 🫠
				#
				# so that's why we need this awful `_just_jumped_from_wall_slide` flag,
				# to basically ignore this check for a tick until after the player has moved
				# and is no longer _actually_ colliding with the wall
				if not _just_jumped_from_wall_slide and _check_wall_slide():
					return

				_just_jumped_from_wall_slide = false

		State.WALL_SLIDE:
			if event is EnterStateEvent:
				facing = int(signf(get_wall_normal().x)) as Direction

			if event is StartJumpEvent:
				velocity.x = get_wall_normal().x * 300.0
				state = State.JUMPING
				_just_jumped_from_wall_slide = true

			if event is UpdateEvent:
				if not _is_moving_against_wall() or not is_on_wall_only():
					state = State.FALLING

					# give some grace period for jumping just shortly after facing away from the wall,
					# to make wall jumping easier
					#remaining_coyote_time = max_coyote_time
					return

				if is_on_floor():
					state = State.IDLE
					return

				facing = int(signf(get_wall_normal().x)) as Direction
				velocity.y = minf(velocity.y + 1000.0 * event.delta, 150.0)

		State.DASHING:
			if event is UpdateEvent:
				if _check_wall_slide():
					return

				velocity.x = dash_facing * dash_speed

				# while dashing, if we're moving upward, apply lessened gravity to move downward,
				# but once we're level, stay level
				velocity.y = minf(velocity.y + dash_gravity * event.delta, 0)

				if infinite_dash:
					return

				remaining_dash_time -= event.delta
				if remaining_dash_time < 0:
					if is_on_floor():
						state = State.IDLE
					else:
						state = State.FALLING


func _is_moving_against_wall() -> bool:
	return signf(movement) == -signf(get_wall_normal().x)


func _apply_gravity(delta: float) -> void:
	velocity.y += gravity * delta


func _apply_ground_friction(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, ground_friction * delta)


func _apply_air_friction(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, air_friction * delta)


func _apply_movement_accel(delta: float) -> void:
	velocity.x = move_toward(velocity.x, max_speed * movement, move_acceleration * delta)


func _apply_turnaround_accel(delta: float) -> void:
	velocity.x = move_toward(velocity.x, max_speed * movement, turnaround_acceleration * delta)


func _apply_inverse_wall_facing() -> void:
	facing = int(signf(get_wall_normal().x)) as Direction


func _check_falling() -> bool:
	if is_on_floor():
		return false

	state = State.FALLING
	remaining_coyote_time = max_coyote_time

	return true


func _check_wall_slide() -> bool:
	if is_on_wall_only() and _is_moving_against_wall():
		state = State.WALL_SLIDE
		return true

	return false
	#if not is_on_wall_only():
	#return false
	#
	#
	#get_wall_normal()
#
#state = State.WALL_SLIDE
#return true


func _check_fallout_death() -> bool:
	if global_position.y > 1000:
		velocity = Vector2()
		state = State.DEAD
		return true

	return false


func _apply_facing_from_movement() -> void:
	facing = int(signf(movement)) as Direction


@abstract
class StateEvent:
	pass


class EnterStateEvent extends StateEvent:
	pass


class ExitStateEvent extends StateEvent:
	pass


class UpdateEvent extends StateEvent:
	var delta: float


	@warning_ignore("shadowed_variable")
	func _init(
		delta: float
	) -> void:
		self.delta = delta


class StartJumpEvent extends StateEvent:
	pass


class FinishJumpEvent extends StateEvent:
	pass


class StartDashEvent extends StateEvent:
	pass


class FinishDashEvent extends StateEvent:
	pass
