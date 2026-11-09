## QA: campaign gating, progress and stars.
extends Node

func _ready() -> void:
	Global.campaign_records.clear()
	assert(Global.campaign_unlocked_mission() == 1)
	assert(Global.campaign_completed_count() == 0)
	for mission_id in range(1, 6):
		Global.campaign_records["mission_%d" % mission_id] = {
			"completed": true, "stars": mission_id % 3 + 1,
			"best_score": 100 * mission_id, "best_time": 100.0,
			"highest_diff": 2,
		}
		var expected := mini(mission_id + 1, 5)
		assert(Global.campaign_unlocked_mission() == expected)
		assert(Global.campaign_completed_count() == mission_id)
	assert(Global.campaign_is_complete())
	assert(Global.campaign_stars_total() == 2 + 3 + 1 + 2 + 3)
	print("[CAMPAIGNQA] PASS · unlocked=5 · completed=5 · stars=",
			Global.campaign_stars_total())
	Global.campaign_records.clear()
	get_tree().quit(0)
