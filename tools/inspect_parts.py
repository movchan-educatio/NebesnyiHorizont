import bpy, bmesh

def inspect_mesh(filepath):
    print("=" * 60)
    print("FILE:", filepath)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=filepath)
    for o in bpy.data.objects:
        if o.type == 'MESH':
            bm = bmesh.new()
            bm.from_mesh(o.data)
            # Find loose parts (connected components)
            parts = []
            visited = set()
            for v in bm.verts:
                if v in visited:
                    continue
                part = []
                stack = [v]
                visited.add(v)
                while stack:
                    curr = stack.pop()
                    part.append(curr.co)
                    for edge in curr.link_edges:
                        other = edge.other_vert(curr)
                        if other not in visited:
                            visited.add(other)
                            stack.append(other)
                parts.append(part)
            print(f"Mesh '{o.name}': {len(bm.verts)} vertices, {len(parts)} connected components (loose parts)")
            for i, p in enumerate(parts):
                xs = [v.x for v in p]
                ys = [v.y for v in p]
                zs = [v.z for v in p]
                dx = max(xs) - min(xs)
                dy = max(ys) - min(ys)
                dz = max(zs) - min(zs)
                cx = (max(xs) + min(xs)) / 2
                cy = (max(ys) + min(ys)) / 2
                cz = (max(zs) + min(zs)) / 2
                print(f"  Part {i}: {len(p)} verts, size=({dx:.3f}, {dy:.3f}, {dz:.3f}), center=({cx:.3f}, {cy:.3f}, {cz:.3f})")
            bm.free()

inspect_mesh(r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\d1l-duck_-_ukrainian_tailsitter_vtol_fpv_quad.glb")
inspect_mesh(r"C:\Users\USER_UA\Desktop\Новий симулятор\Моделі дронів та опис до них\Пеленг\vyriy_15_-.glb")
