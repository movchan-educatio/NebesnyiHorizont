extends Control


signal back


var packed_popup := preload("res://GUI/ConfirmationPopup.tscn")

@onready var master_volume := $PanelContainer/VBoxContainer/ScrollContainer/Grid/MasterSlider
@onready var master_volume_label := $PanelContainer/VBoxContainer/ScrollContainer/Grid/MasterValue


func _ready() -> void:
	var _discard = master_volume.connect("value_changed", Callable(self, "_on_master_volume_changed"))
	master_volume.value = volume_to_slider(Audio.audio_settings["master_volume"])
	master_volume_label.text = update_slider_label(master_volume.value)

	_add_volume_row("Music Volume", "music_volume", Audio.set_music_volume)
	_add_volume_row("SFX Volume", "sfx_volume", Audio.set_sfx_volume)

	_discard = $PanelContainer/VBoxContainer/HBoxContainer/ButtonBack.connect("pressed", Callable(self, "_on_back_pressed"))


## Adds a label + HSlider + value label row to the existing 3-column grid.
func _add_volume_row(title: String, key: String, apply: Callable) -> void:
	var grid := $PanelContainer/VBoxContainer/ScrollContainer/Grid
	var label := Label.new()
	label.text = title
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = float(Audio.audio_settings.get(key, 0.8)) * 100.0
	slider.custom_minimum_size = Vector2(200, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tick_count = 5
	slider.ticks_on_borders = true
	var value_label := Label.new()
	value_label.text = "%d%%" % round(slider.value)
	grid.add_child(label)
	grid.add_child(slider)
	grid.add_child(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = "%d%%" % round(value)
		apply.call(value / 100.0)
	)


func _input(event):
	if event.is_action("ui_cancel") and event.is_pressed() and not event.is_echo():
		accept_event()
		emit_signal("back")


func _on_master_volume_changed(value: float) -> void:
	master_volume_label.text = update_slider_label(master_volume.value)
	Audio.audio_settings["master_volume"] = slider_to_volume(value)
	Audio.update_master_volume()
	Audio.save_audio_settings()


func _on_back_pressed() -> void:
	emit_signal("back")


func volume_to_slider(volume: float) -> float:
	return volume * 100.0


func slider_to_volume(value: float) -> float:
	return value / 100.0


func update_slider_label(value: float) -> String:
	var text := "%d%%" % [round(value)]
	return text
