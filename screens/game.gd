extends Node2D

@onready var debug_label: Label = %DebugLabel


func _process(_delta: float) -> void:
	var actions := InputMap.get_actions()

	var pressed_actions: Array = (
		actions.filter(
			func(action: StringName):
				return not action.begins_with("ui_"),
		).filter(
			func(action) -> bool:
				return Input.is_action_pressed(action),
		)
	)

	debug_label.text = ", ".join(pressed_actions)
