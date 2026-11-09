import json, struct, sys, os

def read_glb(path):
    with open(path, 'rb') as f:
        data = f.read()
    magic, version, length = struct.unpack_from('<III', data, 0)
    off = 12
    chunks = []
    while off < length:
        clen, ctype = struct.unpack_from('<II', data, off)
        off += 8
        chunks.append((ctype, data[off:off+clen]))
        off += clen
    for ctype, payload in chunks:
        if ctype == 0x4E4F534A:
            return json.loads(payload.decode('utf-8'))
    return None

for name in ["vegetation_library.glb", "oak_hero.glb", "pine_hero.glb"]:
    path = os.path.join(
        r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\frontline\vegetation",
        name)
    js = read_glb(path)
    print("=" * 60)
    print(name)
    for i, n in enumerate(js.get("nodes", [])):
        m = js["meshes"][n["mesh"]] if n.get("mesh") is not None else None
        if m is None:
            print("node", i, n.get("name"), "(no mesh)")
            continue
        tri = 0
        attrs = set()
        for p in m["primitives"]:
            acc = js["accessors"][p["indices"]]
            tri += acc["count"] // 3
            attrs.update(p["attributes"].keys())
        print("node", i, n.get("name"), "tris=", tri, "attrs=", sorted(attrs))
    print("images:", len(js.get("images", [])), "materials:", len(js.get("materials", [])),
          "animations:", len(js.get("animations", [])))
    for a in js.get("animations", []):
        chans = a.get("channels", [])
        targets = set(t["target"]["path"] for t in chans)
        print("  anim", a.get("name"), "channels", len(chans), "targets", targets)
