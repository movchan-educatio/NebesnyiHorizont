"""Read-only GLB complexity audit for the mobile combat asset budget.

Run with `python tools/audit_mobile_assets.py`. It reports GLB mesh/object
counts, primitives/draw-call candidates, materials, vertices, skins, animation
clips and file bytes without importing or modifying source assets.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = [
    "Assets/combat/rifleman.glb",
    "Assets/combat/soldier_detailed_merged.glb",
    "Assets/vehicles/apache_hecu_half-life.glb",
    "Assets/vehicles/apache_hecu_half-life_mobile.glb",
    "Assets/vehicles/btr-90_ussr.glb",
    "Assets/vehicles/low_poly_t-72_tank_-_game_ready.glb",
    "Assets/vehicles/gaz_tigr_low_poly.glb",
    "Assets/Drones/ua_norm/leleka_100.glb",
    "Assets/Drones/ua_norm/leleka_100_mobile.glb",
    "Assets/Drones/ua_norm/furia_a1sm.glb",
    "Assets/Drones/ua_norm/furia_a1sm_mobile.glb",
    "Assets/Drones/ua_norm/chaklun_jet.glb",
    "Assets/Drones/ua_norm/chaklun_jet_mobile.glb",
]
MOBILE_PAIRS = [
	("Assets/vehicles/apache_hecu_half-life.glb",
	 "Assets/vehicles/apache_hecu_half-life_mobile.glb"),
	("Assets/Drones/ua_norm/leleka_100.glb",
	 "Assets/Drones/ua_norm/leleka_100_mobile.glb"),
	("Assets/Drones/ua_norm/furia_a1sm.glb",
	 "Assets/Drones/ua_norm/furia_a1sm_mobile.glb"),
	("Assets/Drones/ua_norm/chaklun_jet.glb",
	 "Assets/Drones/ua_norm/chaklun_jet_mobile.glb"),
]


def load_json(path: Path) -> dict:
    data = path.read_bytes()
    magic, version, declared = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2 or declared != len(data):
        raise ValueError(f"Invalid GLB header: {path}")
    off = 12
    while off < len(data):
        size, chunk_type = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off : off + size]
        off += size
        if chunk_type == 0x4E4F534A:
            return json.loads(chunk.decode("utf-8").rstrip("\x00 "))
    raise ValueError(f"No JSON chunk: {path}")


def _mul(a: list[list[float]], b: list[list[float]]) -> list[list[float]]:
	return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)]
			for r in range(4)]


def _node_matrix(node: dict) -> list[list[float]]:
	if "matrix" in node:
		v = node["matrix"]
		return [[float(v[c * 4 + r]) for c in range(4)] for r in range(4)]
	t = node.get("translation", [0.0, 0.0, 0.0])
	s = node.get("scale", [1.0, 1.0, 1.0])
	x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
	rot = [
		[1 - 2 * (y*y + z*z), 2 * (x*y - z*w), 2 * (x*z + y*w)],
		[2 * (x*y + z*w), 1 - 2 * (x*x + z*z), 2 * (y*z - x*w)],
		[2 * (x*z - y*w), 2 * (y*z + x*w), 1 - 2 * (x*x + y*y)],
	]
	m = [[rot[r][c] * float(s[c]) for c in range(3)] + [float(t[r])]
			for r in range(3)]
	m.append([0.0, 0.0, 0.0, 1.0])
	return m


def world_bounds(doc: dict) -> tuple[list[float], list[float]]:
	nodes = doc.get("nodes", [])
	parents = {}
	for i, node in enumerate(nodes):
		for child in node.get("children", []):
			parents[child] = i
	world = {}
	def get_world(i: int) -> list[list[float]]:
		if i in world:
			return world[i]
		local = _node_matrix(nodes[i])
		world[i] = _mul(get_world(parents[i]), local) if i in parents else local
		return world[i]
	points = []
	for i, node in enumerate(nodes):
		mesh_id = node.get("mesh")
		if mesh_id is None:
			continue
		m = get_world(i)
		for primitive in doc["meshes"][mesh_id].get("primitives", []):
			position_id = primitive.get("attributes", {}).get("POSITION")
			if position_id is None:
				continue
			accessor = doc["accessors"][position_id]
			lo, hi = accessor.get("min"), accessor.get("max")
			if lo is None or hi is None:
				continue
			for mask in range(8):
				p = [float(hi[a] if mask & (1 << a) else lo[a]) for a in range(3)] + [1.0]
				points.append([sum(m[r][c] * p[c] for c in range(4)) for r in range(3)])
	if not points:
		return [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]
	return ([min(p[i] for p in points) for i in range(3)],
			[max(p[i] for p in points) for i in range(3)])


def audit(rel: str) -> None:
    path = ROOT / rel
    if not path.exists():
        print(f"MISSING  {rel}")
        return
    doc = load_json(path)
    primitives = sum(len(mesh.get("primitives", [])) for mesh in doc.get("meshes", []))
    vertices = 0
    for mesh in doc.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            accessor = primitive.get("attributes", {}).get("POSITION")
            if accessor is not None:
                vertices += int(doc.get("accessors", [])[accessor].get("count", 0))
    scene_objects = sum(1 for n in doc.get("nodes", []) if "mesh" in n)
    clips = [a.get("name", "<unnamed>") for a in doc.get("animations", [])]
    lo, hi = world_bounds(doc)
    size = [round(hi[i] - lo[i], 4) for i in range(3)]
    print(
        f"{rel}: bytes={path.stat().st_size} objects={scene_objects} "
        f"primitives={primitives} materials={len(doc.get('materials', []))} "
        f"vertices={vertices} skins={len(doc.get('skins', []))} "
        f"animations={len(clips)} {clips} bounds={size}"
    )


if __name__ == "__main__":
	for asset in ASSETS:
		audit(asset)
	failures = 0
	for original_rel, mobile_rel in MOBILE_PAIRS:
		original_path, mobile_path = ROOT / original_rel, ROOT / mobile_rel
		if not original_path.exists() or not mobile_path.exists():
			failures += 1
			print(f"[MOBILE_AUDIT] FAIL missing pair: {original_rel} / {mobile_rel}")
			continue
		original_doc, mobile_doc = load_json(original_path), load_json(mobile_path)
		original_lo, original_hi = world_bounds(original_doc)
		mobile_lo, mobile_hi = world_bounds(mobile_doc)
		max_delta = max(abs(a - b) for a, b in zip(original_lo + original_hi,
				mobile_lo + mobile_hi))
		original_objects = sum(1 for n in original_doc.get("nodes", []) if "mesh" in n)
		mobile_objects = sum(1 for n in mobile_doc.get("nodes", []) if "mesh" in n)
		original_prims = sum(len(m.get("primitives", [])) for m in original_doc.get("meshes", []))
		mobile_prims = sum(len(m.get("primitives", [])) for m in mobile_doc.get("meshes", []))
		ok = max_delta <= 0.01 and mobile_objects < original_objects \
				and mobile_prims < original_prims
		print(f"[MOBILE_AUDIT] {'PASS' if ok else 'FAIL'} "
			  f"{Path(original_rel).name}: bounds_delta={max_delta:.6f} "
			  f"objects={original_objects}->{mobile_objects} "
			  f"primitives={original_prims}->{mobile_prims}")
		if not ok:
			failures += 1
	if failures:
		raise SystemExit(1)
