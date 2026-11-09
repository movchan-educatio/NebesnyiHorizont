extends SceneTree


func _init() -> void:
	print("[FSR-CHECK] adapter=", RenderingServer.get_video_adapter_name())
	print("[FSR-CHECK] api=", RenderingServer.get_video_adapter_api_version())
	print("[FSR-CHECK] bilinear=", Viewport.SCALING_3D_MODE_BILINEAR)
	print("[FSR-CHECK] fsr1=", Viewport.SCALING_3D_MODE_FSR)
	print("[FSR-CHECK] fsr2=", Viewport.SCALING_3D_MODE_FSR2)
	print("[FSR-CHECK] metadata=", ProjectSettings.get_setting("rendering/scaling_3d/mode"))
	quit()
