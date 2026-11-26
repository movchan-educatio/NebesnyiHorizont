class_name RuinsFreestyleRings
extends RefCounted
## Technical 28-gate FPV freestyle course for Ruins (ruins).
## Instead of a flat oval, gates are threaded through real industrial and urban
## openings: viaduct under-spans, Hall #3 end-to-end, Overpass collapsed span,
## Main Hall #1 under the moving overhead crane, Ruin Shell #52/#54/#57 breaches,
## Cooling Tower arch + vertical funnel climb, Slab Slalom weave, Torn Billboard
## hole, Pipe Rack underpass, East Warehouse gates, 54 m Corrugated Pipe Tunnel,
## Water Tower 4-leg truss, Container Bridge missing-container tower hole + span,
## and Hall #2 end-to-end back to the Gantry Crane and South Avenue Finish.

const FreestyleCourseScript = preload("res://scripts/util/freestyle_course.gd")

const COL_PRIMARY := Color(0.08, 0.94, 0.86)
const COL_TECHNICAL := Color(1.0, 0.62, 0.14)
const COL_START := Color(0.16, 0.98, 0.48)
const COL_FINISH := Color(1.0, 0.78, 0.14)

## Each entry:
##   pos: [x, y, z] in Godot world coords
##   dir: [dx, dy, dz] flight direction through opening (optional -> auto tangent)
##   size: gate radius (m)
##   shape: FreestyleCourse.SHAPE_*
##   roll: deg
##   col: "start" | "finish" | "tech" | "primary"
##   tag: descriptive opening name for QA checks
const GATES_DATA := [
	# 1. START: Centered cleanly in the open viaduct bay ahead of Freestyle Spawn (21, 72)
	{"pos": [21.0, 4.3, 47.0], "dir": [-0.30, 0.0, -0.95], "size": 3.8, "shape": FreestyleCourseScript.SHAPE_ARCH, "roll": 0.0, "col": "start", "tag": "Viaduct_Start"},
	# 2. Central Yard approach toward Hall #3 North Gate
	{"pos": [-22.0, 4.8, -14.0], "dir": [-0.95, -0.05, -0.30], "size": 3.4, "shape": FreestyleCourseScript.SHAPE_HEXAGON, "roll": -10.0, "col": "primary", "tag": "Yard_NorthApproach"},
	# 3. Hall #3 North Wall Gate Entry -> interior pass
	{"pos": [-55.0, 3.2, -18.0], "dir": [0.0, 0.0, 1.0], "size": 2.4, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": 0.0, "col": "tech", "tag": "Hall3_NorthGate"},
	# 4. Hall #3 South Wall Gate Exit
	{"pos": [-55.0, 3.2, 2.0], "dir": [0.0, 0.0, 1.0], "size": 2.4, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": 0.0, "col": "tech", "tag": "Hall3_SouthGate"},
	# 5. Climb up and drop through the Overpass collapsed 13 m deck gap
	{"pos": [-39.1, 13.0, 21.8], "dir": [-0.30, -0.75, 0.59], "size": 3.6, "shape": FreestyleCourseScript.SHAPE_DIAMOND, "roll": 0.0, "col": "tech", "tag": "Overpass_CollapsedGap"},
	# 6. Main Factory Hall #1 East End Gate
	{"pos": [-73.0, 3.2, 40.0], "dir": [-1.0, 0.0, 0.0], "size": 2.6, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": 0.0, "col": "tech", "tag": "Hall1_EastGate"},
	# 7. Main Hall #1 Interior — under the moving overhead crane (crane is at y=9.2)
	{"pos": [-105.0, 3.6, 40.0], "dir": [-1.0, 0.0, 0.0], "size": 2.7, "shape": FreestyleCourseScript.SHAPE_HEXAGON, "roll": 0.0, "col": "tech", "tag": "Hall1_UnderCrane"},
	# 8. Main Hall #1 West End Gate Exit
	{"pos": [-137.0, 3.2, 40.0], "dir": [-1.0, 0.0, 0.0], "size": 2.6, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": 0.0, "col": "tech", "tag": "Hall1_WestGate"},
	# 9. Ruin Shell #52 blown-out transverse ground breach
	{"pos": [-92.0, 2.4, 88.0], "dir": [-0.25, 0.10, 0.96], "size": 1.8, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": 0.0, "col": "tech", "tag": "Ruin52_Breach"},
	# 10. Cooling Tower Arch A Entry (crosses over train corridor safely at y >= 7 on approach)
	{"pos": [-202.7, 3.8, 161.9], "dir": [-0.68, 0.08, 0.73], "size": 2.4, "shape": FreestyleCourseScript.SHAPE_ARCH, "roll": 0.0, "col": "tech", "tag": "CoolingTower_ArchA"},
	# 11. Cooling Tower Inner Hyperboloid Vertical Funnel Climb
	{"pos": [-215.0, 22.0, 175.0], "dir": [0.0, 1.0, 0.0], "size": 4.6, "shape": FreestyleCourseScript.SHAPE_HEXAGON, "roll": 0.0, "col": "tech", "tag": "CoolingTower_Throat"},
	# 12. Cooling Tower Top Rim Exit (44 m)
	{"pos": [-215.0, 45.8, 175.0], "dir": [0.92, -0.22, 0.32], "size": 4.8, "shape": FreestyleCourseScript.SHAPE_DIAMOND, "roll": 0.0, "col": "tech", "tag": "CoolingTower_RimExit"},
	# 13. Slab Slalom West Weave
	{"pos": [12.0, 3.2, 203.0], "dir": [0.96, 0.0, 0.28], "size": 2.4, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": 14.0, "col": "primary", "tag": "SlabSlalom_West"},
	# 14. Slab Slalom East Weave
	{"pos": [28.0, 3.4, 207.0], "dir": [0.95, 0.10, -0.28], "size": 2.4, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": -14.0, "col": "primary", "tag": "SlabSlalom_East"},
	# 15. Torn Billboard Main Hole (4.68 x 4.58 m elevated steel panel opening)
	{"pos": [146.06, 10.09, 148.72], "dir": [0.259, -0.05, -0.965], "size": 1.6, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": 0.0, "col": "tech", "tag": "Billboard_Hole1"},
	# 16. Elevated Pipe Rack South Underpass (below 7 m multi-pipe rack)
	{"pos": [215.0, 3.4, 88.0], "dir": [0.0, 0.0, -1.0], "size": 2.5, "shape": FreestyleCourseScript.SHAPE_ARCH, "roll": 0.0, "col": "primary", "tag": "PipeRack_UnderSouth"},
	# 17. Elevated Pipe Rack North Underpass
	{"pos": [215.0, 3.4, 52.0], "dir": [-0.35, 0.0, -0.94], "size": 2.5, "shape": FreestyleCourseScript.SHAPE_ARCH, "roll": 0.0, "col": "primary", "tag": "PipeRack_UnderNorth"},
	# 18. East Warehouse East End Gate
	{"pos": [198.0, 2.8, 45.0], "dir": [-1.0, 0.0, 0.0], "size": 2.1, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": 0.0, "col": "tech", "tag": "Warehouse_EastGate"},
	# 19. East Warehouse West End Gate Exit
	{"pos": [162.0, 2.8, 45.0], "dir": [-1.0, 0.0, 0.0], "size": 2.1, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": 0.0, "col": "tech", "tag": "Warehouse_WestGate"},
	# 20. Ruin Shell #54 Wide Structural Breach
	{"pos": [118.92, 2.3, -13.05], "dir": [-0.149, 0.0, -0.989], "size": 1.8, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": 0.0, "col": "tech", "tag": "Ruin54_Breach"},
	# 21. 54 m Corrugated Pipe Tunnel Entry
	{"pos": [174.5, 6.0, -120.7], "dir": [0.819, 0.0, -0.574], "size": 3.0, "shape": FreestyleCourseScript.SHAPE_HEXAGON, "roll": 0.0, "col": "tech", "tag": "PipeTunnel_Entry"},
	# 22. 54 m Pipe Tunnel Mid-Bore (under skylight tear)
	{"pos": [195.0, 6.0, -135.0], "dir": [0.819, 0.0, -0.574], "size": 3.0, "shape": FreestyleCourseScript.SHAPE_HEXAGON, "roll": 0.0, "col": "tech", "tag": "PipeTunnel_Mid"},
	# 23. 54 m Pipe Tunnel Exit (clear outside mouth before banking west)
	{"pos": [221.2, 6.4, -153.4], "dir": [0.40, 0.20, -0.89], "size": 3.2, "shape": FreestyleCourseScript.SHAPE_HEXAGON, "roll": 0.0, "col": "tech", "tag": "PipeTunnel_Exit"},
	# 24. Water Tower 4-Leg Steel Truss Thread
	{"pos": [15.0, 7.2, -80.0], "dir": [-0.88, -0.10, -0.46], "size": 2.3, "shape": FreestyleCourseScript.SHAPE_DIAMOND, "roll": 0.0, "col": "tech", "tag": "WaterTower_Legs"},
	# 25. Ruin Shell #57 Multi-Floor Breach
	{"pos": [-45.8, 3.8, -144.8], "dir": [-0.95, 0.0, -0.31], "size": 2.0, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": 0.0, "col": "tech", "tag": "Ruin57_Breach"},
	# 26. Container Bridge Missing-Container Tower Hole (12 m x 2.57 m slot!)
	{"pos": [-222.85, 3.94, -156.50], "dir": [0.342, 0.0, 0.940], "size": 1.20, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": 0.0, "col": "tech", "tag": "ContainerBridge_TowerHole"},
	# 27. Factory Hall #2 End-to-End Pass (-130, 0, -62, -15 deg)
	{"pos": [-130.0, 3.4, -62.0], "dir": [0.966, 0.05, 0.259], "size": 2.5, "shape": FreestyleCourseScript.SHAPE_SQUARE, "roll": 0.0, "col": "tech", "tag": "Hall2_Interior"},
	# 28. Gantry Crane Frame -> South Avenue Finish
	{"pos": [-35.0, 11.4, 78.0], "dir": [0.98, -0.14, 0.10], "size": 3.2, "shape": FreestyleCourseScript.SHAPE_DIAMOND, "roll": 0.0, "col": "tech", "tag": "GantryCrane_Span"},
	# 29. FINISH Gate on Main Avenue South Plaza
	{"pos": [21.0, 4.8, 76.0], "dir": [0.0, 0.0, -1.0], "size": 4.2, "shape": FreestyleCourseScript.SHAPE_ARCH, "roll": 0.0, "col": "finish", "tag": "Avenue_Finish"},
]


static func waypoints() -> Array:
	var out: Array = []
	for g in GATES_DATA:
		var p: Array = g["pos"]
		out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return out


static func build_specs(ground_fn: Callable = Callable()) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var total := GATES_DATA.size()
	for i in range(total):
		var g: Dictionary = GATES_DATA[i]
		var p: Array = g["pos"]
		var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
		var dir: Vector3
		if g.has("dir"):
			var d: Array = g["dir"]
			dir = Vector3(float(d[0]), float(d[1]), float(d[2])).normalized()
		else:
			var np: Array = GATES_DATA[(i + 1) % total]["pos"]
			dir = (Vector3(float(np[0]), float(np[1]), float(np[2])) - pos).normalized()
		var size := float(g.get("size", 3.2))
		var shape := int(g.get("shape", FreestyleCourseScript.SHAPE_SQUARE))
		var col_key := String(g.get("col", "primary"))
		var col := COL_PRIMARY
		if col_key == "start":
			col = COL_START
		elif col_key == "finish":
			col = COL_FINISH
		elif col_key == "tech":
			col = COL_TECHNICAL
		var gy := 0.0
		var lgy := 0.0
		var rgy := 0.0
		if ground_fn.is_valid():
			gy = float(ground_fn.call(pos.x, pos.z))
			var right := dir.cross(Vector3.UP)
			if right.length_squared() < 0.001:
				right = Vector3.RIGHT
			else:
				right = right.normalized()
			lgy = float(ground_fn.call(pos.x - right.x * size * 0.9, pos.z - right.z * size * 0.9))
			rgy = float(ground_fn.call(pos.x + right.x * size * 0.9, pos.z + right.z * size * 0.9))
		specs.append({
			"pos": pos,
			"dir": dir,
			"size": size,
			"shape": shape,
			"roll": deg_to_rad(float(g.get("roll", 0.0))),
			"color": col,
			"ground_y": gy,
			"left_ground_y": lgy,
			"right_ground_y": rgy,
			"over_water": false,
			"tag": String(g.get("tag", "Gate%d" % (i + 1))),
		})
	return specs
