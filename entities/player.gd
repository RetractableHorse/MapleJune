extends CharacterBody2D

const DEFAULT_SPEED = 400.0
const SPRINT_SPEED = 750.0
const JUMP_VELOCITY = -1200.0
const GRAVITY = 1700.0
const MOVE_ACCELERATION = 1500.0
const TURNAROUND_ACCELERATION = 2200.0
const GROUND_FRICTION = 1000.0
const AIR_FRICTION = 100.0
const JUMP_BUFFER_TIME = 0.08

signal fallout

enum State {
	DEFAULT,
	JUMPING,
	FALLOUT,
}

var state := State.DEFAULT
var jump_buffer := 0.0


func reset() -> void:
	velocity = Vector2()
	state = State.DEFAULT


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		jump_buffer = JUMP_BUFFER_TIME


func _physics_process(delta: float) -> void:
	match state:
		State.DEFAULT:
			_apply_gravity(delta)
			_move(delta)
			_process_buffered_jump(delta)
			_check_fallout(delta)

		State.JUMPING:
			_move(delta)
			_check_fallout(delta)

		State.FALLOUT:
			pass


func _process_buffered_jump(delta: float) -> void:
	if jump_buffer > 0:
		jump_buffer -= delta

	if is_on_floor() and jump_buffer > 0:
		jump_buffer = 0

		state = State.JUMPING

		var tween := create_tween()
		tween.tween_property(self, 'velocity:y', 0, 0.3).from(JUMP_VELOCITY)
		await tween.finished

		state = State.DEFAULT


func _apply_gravity(delta: float) -> void:
	if not is_on_floor() and state != State.JUMPING:
		velocity += Vector2.DOWN * GRAVITY * delta


func _move(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")

	if direction == 0:
		var friction := GROUND_FRICTION if is_on_floor() else AIR_FRICTION
		velocity.x = move_toward(velocity.x, 0, friction * delta)
	else:
		var speed := (SPRINT_SPEED
			if Input.is_action_pressed("sprint")
			else DEFAULT_SPEED)

		var accel := (
			TURNAROUND_ACCELERATION
			if signf(direction) != signf(velocity.x)
			else MOVE_ACCELERATION
		)

		velocity.x = move_toward(velocity.x, speed * direction, accel * delta)

	move_and_slide()


func _check_fallout(_delta: float) -> void:
	if global_position.y > 1000:
		velocity = Vector2()
		state = State.FALLOUT
		fallout.emit()
