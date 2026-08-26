extends Node2D

@export var player: Player
@export var player_spawn: Marker2D


func _ready() -> void:
	player.state_changed.connect(_on_player_state_changed)
	_respawn_player()


func _respawn_player() -> void:
	player.global_position = player_spawn.global_position
	player.reset()


func _on_player_state_changed(state: Player.State) -> void:
	prints("player state:", Player.State.find_key(state))
	if state == Player.State.DEAD:
		_respawn_player()
