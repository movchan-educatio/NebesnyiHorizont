import bpy, os

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор"

def find_file(pattern, ext=(".glb", ".gltf", ".fbx")):
    for root, dirs, files in os.walk(base_dir):
        if ".godot" in root:
            continue
        for f in files:
            if pattern.lower() in f.lower() and f.lower().endswith(ext):
                return os.path.join(root, f)
    return None

pisun_file = find_file("d1l-duck")
peleng_file = find_file("vyriy_15")
falcon_file = find_file("СКЕТЧ.fbx")
if not falcon_file:
    falcon_file = find_file("falcon")
avata_file = find_file("dji_avata2")

targets = [
    ("Pisun", pisun_file),
    ("Peleng", peleng_file),
    ("Falcon", falcon_file),
    ("Avata", avata_file)
]

for name, path in targets:
    if not path or not os.path.exists(path):
        print(f"Skipping {name}, path not found: {path}")
        continue
    print(f"\n==========================================")
    print(f"TARGET: {name} -> {path}")
    print(f"==========================================")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if path.endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
        
    for o in bpy.data.objects:
        p_name = o.parent.name if o.parent else "None"
        mw = o.matrix_world
        print(f"  {o.name:32} | type={o.type:6} | parent={p_name:22} | world_pos={mw.to_translation()} | dims={o.dimensions}")
