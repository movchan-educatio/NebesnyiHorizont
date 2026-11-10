extends Node

## Measures the synchronous drone-preview cost when the user presses
## Previous/Next in the main menu or hangar.  Run headless:
##   godot --headless --path . res://test/bench_drone_switch.tscn

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	var holder := Node3D.new()
	holder.name = "BenchHolder"
	add_child(holder)
	var total_first := 0.0
	var total_second := 0.0
	for pass_idx in range(2):
		print("[DRONEBENCH] pass ", pass_idx + 1)
		for i in range(DroneCatalog.count()):
			var t0 := Time.get_ticks_usec()
			var model: Node3D = DroneCatalog.attach_model(holder, i)
			var t1 := Time.get_ticks_usec()
			if model != null:
				MenuUI.fit_preview_model(model, 0.52, -0.205)
			var t2 := Time.get_ticks_usec()
			var p := DroneCatalog.preset(i)
			print("[DRONEBENCH] %02d %-22s attach=%6.1fms fit=%5.1fms total=%6.1fms" % [
				i, str(p.get("name", "?")), (t1 - t0) / 1000.0,
				(t2 - t1) / 1000.0, (t2 - t0) / 1000.0])
			if pass_idx == 0:
				total_first += (t2 - t0) / 1000.0
			else:
				total_second += (t2 - t0) / 1000.0
			if model != null:
				holder.remove_child(model)
				model.queue_free()
			await get_tree().process_frame
	print("[DRONEBENCH] first_pass_total=%.1fms second_pass_total=%.1fms" % [
		total_first, total_second])
	get_tree().quit()
