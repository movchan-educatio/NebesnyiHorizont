## QA-only: holds a fixed touch-stick pose so a screenshot can show the
## on-screen sticks, the 3D radio and the axis grid all deflected.
extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	var pad := get_node_or_null("/root/TouchControls")
	if pad == null:
		print("[POSEQA] FAIL: TouchControls missing")
		return
	pad.call("set_menu_preview", true)
	pad.set("throttle", 0.82)
	pad.set("yaw", 0.72)
	pad.set("pitch", -0.63)
	pad.set("roll", 0.55)
	print("[POSEQA] pose set")
