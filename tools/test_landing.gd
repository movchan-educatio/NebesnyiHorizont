extends SceneTree

func _init():
    var level_scene = load("res://sceneries/BigLevel.tscn")
    var level = level_scene.instantiate()
    root.add_child(level)
    print("Level instantiated")
    await process_frame
    await process_frame
    var drone = level.get_node("Drone")
    print("Drone pos: ", drone.global_position)
    print("Drone mass: ", drone.mass)
    print("Drone custom_integrator: ", drone.custom_integrator)
    # Simulate flight down to ground
    drone.global_position = Vector3(0, 0.5, 220)
    drone.linear_velocity = Vector3(0, -0.5, 0)
    drone.freeze = false
    
    for f in range(60):
        await physics_frame
        if f % 10 == 0:
            print("Frame ", f, " pos: ", drone.global_position, " vel: ", drone.linear_velocity)
            var space = drone.get_world_3d().direct_space_state
            var q = PhysicsRayQueryParameters3D.create(drone.global_position + Vector3.UP, drone.global_position + Vector3.DOWN * 2.0)
            var hit = space.intersect_ray(q)
            if not hit.is_empty():
                print("  Ray hit: ", hit.collider.name, " at ", hit.position)
    quit()
