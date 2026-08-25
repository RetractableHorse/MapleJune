extends Node2D

@export var player: Player
@export var player_spawn: Marker2D


func _ready() -> void:
	player.died.connect(_on_player_died)
	_respawn_player()


func _respawn_player() -> void:
	player.global_position = player_spawn.global_position
	player.reset()


func _on_player_died() -> void:
	_respawn_player()
