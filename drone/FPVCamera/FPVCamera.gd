extends Camera3D
class_name FPVCamera


@export var fov_h := 150.0: set = _set_fov_h
@export var clip_near := 0.005 # (float, 0.001, 1)
@export var clip_far := 1000.0 # (float, 10, 10000)

var viewports := []
var cameras := []
var camera_layer := 11
var num_cameras := 5
var fpv_environment: Environment = load("res://drone/FPVCamera/FPVCameraEnvironment.tres")

@onready var render_quad: MeshInstance3D = null
var mat: ShaderMaterial = load("res://drone/FPVCamera/FPVCamera.tres")


func _ready() -> void:
	# Never let the lens clip into walls/ground at the authored 0.005 m default.
	near = maxf(clip_near, 0.03)
	far = clip_far
	# We use the lightweight screen-space FPVOverlay shader instead of rendering
	# 5 separate 3D SubViewports every frame (which multiplied draw calls by 6x!).
	set_process(false)


func _process(_delta: float) -> void:
	var fisheye_mode: int = Graphics.graphics_settings["fisheye_mode"]
	if fisheye_mode != Graphics.FisheyeMode.OFF:
		for camera in cameras:
			camera.global_transform = global_transform
		if fisheye_mode == Graphics.FisheyeMode.FULL:
			cameras[1].rotate_object_local(Vector3.UP, PI/2)
			cameras[2].rotate_object_local(Vector3.UP, -PI/2)
			cameras[3].rotate_object_local(Vector3.RIGHT, -PI/2)
			cameras[4].rotate_object_local(Vector3.RIGHT, PI/2)


func _set_fov_h(angle: float) -> void:
	fov_h = angle
	if mat:
		mat.set_shader_parameter("hfov", fov_h)


func show_fisheye(show: bool) -> void:
	render_quad.visible = show


func _on_fisheye_resolution_changed() -> void:
	for viewport in viewports:
		viewport.size = Vector2i(Graphics.fisheye_resolution, Graphics.fisheye_resolution)


func _on_fisheye_msaa_changed() -> void:
	for viewport in viewports:
		if Graphics.graphics_settings["fisheye_msaa"] == Graphics.FisheyeMSAA.SAME_AS_GAME:
			viewport.msaa = Graphics.graphics_settings["msaa"]
		else:
			viewport.msaa = Graphics.graphics_settings["fisheye_msaa"]


func _exit_tree() -> void:
	viewports.clear()
	cameras.clear()
