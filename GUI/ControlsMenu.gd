## Backwards-compatible wrapper for the old options menu entry.
##
## The controls UI now lives in ControlsScreen.tscn so the main menu, the pause
## menu and the options menu all show exactly the same modern screen.
extends Control

signal back


func _ready() -> void:
	var screen := preload("res://GUI/ControlsScreen.tscn").instantiate()
	screen.embedded = true
	screen.process_mode = Node.PROCESS_MODE_ALWAYS
	screen.back.connect(_on_screen_back)
	add_child(screen)


func _on_screen_back() -> void:
	back.emit()
