extends "res://scripts/chat_json_view.gd"

func _apply_to_ui() -> void:
	var icon_path := NodePath("Icon")
	if has_node(icon_path):
		var icon_rect := get_node(icon_path) as TextureRect
		if icon_rect:
			icon_rect.texture = profile_texture

	var name_path := NodePath("VBoxContainer/Name")
	if has_node(name_path):
		var name_label := get_node(name_path) as Label
		if name_label:
			name_label.text = contact_name

	var last_path := NodePath("VBoxContainer/Last_message")
	if has_node(last_path):
		var last_label := get_node(last_path) as Label
		if last_label:
			var last_text := get_last_message_text()
			last_label.text = last_text
