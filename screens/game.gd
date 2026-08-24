extends Node2D

@export var player: CharacterBody2D
@export var player_spawn: Marker2D

@onready var debug_label: Label = %DebugLabel


func _ready() -> void:
	_respawn_player()


func _process(_delta: float) -> void:
	var actions := ["move_left", "move_right", "jump", "sprint"]

	var pressed_actions: Array = actions.filter(
		func(input) -> bool:
			return Input.is_action_pressed(input),
	)

	debug_label.text = ", ".join(pressed_actions)


func _respawn_player() -> void:
	player.global_position = player_spawn.global_position
	player.reset()


func _on_player_died() -> void:
	_respawn_player()
