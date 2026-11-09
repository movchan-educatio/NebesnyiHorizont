import bpy, os

source_files = {
    "Pisun": r"C:\Users\USER_UA\Desktop\Новий симулятор\Моделі дронів та опис до них\Pisun\d1l-duck_-_ukrainian_tailsitter_vtol_fpv_quad.glb",
    "Peleng": r"C:\Users\USER_UA\Desktop\Новий симулятор\Моделі дронів та опис до них\Пеленг\vyriy_15_-.glb",
    "Falcon-X": r"C:\Users\USER_UA\Desktop\Новий симулятор\source\СКЕТЧ.fbx",
    "Avata2": r"C:\Users\USER_UA\Desktop\Новий симулятор\Моделі дронів\dji_avata2.glb"
}

for name, path in source_files.items():
    print(f"\n==========================================")
    print(f"SOURCE FILE: {name}")
    print(f"PATH: {path}")
    print(f"EXISTS: {os.path.exists(path)}")
    print(f"==========================================")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if path.endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    for o in bpy.data.objects:
        p_name = o.parent.name if o.parent else "None"
        mw = o.matrix_world
        print(f"  {o.name:32} | type={o.type:6} | parent={p_name:22} | pos={mw.to_translation()} | rot={o.rotation_euler}")
