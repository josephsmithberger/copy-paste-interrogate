extends ChatJsonView
signal contact_selected(chat_path:String)

const FOCUS_STYLE: StyleBox = preload("res://assets/ui/contact_card_focus.tres")
var _default_panel_style: StyleBox

func _ready() -> void:
	# Ensure clicks on child controls bubble up to this Panel so _gui_input is called
	if self is Control:
		(self as Control).mouse_filter = Control.MOUSE_FILTER_STOP
	# Set mouse_filter on common children to PASS so they don't consume the event
	var bubble_paths := [
		NodePath("HBoxContainer"),
		NodePath("HBoxContainer/Icon"),
		NodePath("HBoxContainer/VBoxContainer"),
		NodePath("HBoxContainer/VBoxContainer/Name"),
		NodePath("HBoxContainer/VBoxContainer/Last_message"),
	]
	for p in bubble_paths:
		if has_node(p):
			var n := get_node(p)
			if n is Control:
				(n as Control).mouse_filter = Control.MOUSE_FILTER_PASS

	# Cache default style so we can restore when unselected
	_default_panel_style = get_theme_stylebox("panel")

	# Continue with base ready only if a path is set (explicit empty path means defer)
	if chat_json_path != "":
		super._ready()

	# Add to a global group so ChatHandler can reliably find ALL cards even if
	# scene hierarchy changes (prevents multiple lingering highlights when path lookup fails)
	if not is_in_group("contact_cards"):
		add_to_group("contact_cards")

func set_selected(selected: bool) -> void:
	# Apply or restore the PanelContainer style box
	if selected:
		add_theme_stylebox_override("panel", FOCUS_STYLE)
	else:
		if _default_panel_style:
			add_theme_stylebox_override("panel", _default_panel_style)
		else:
			remove_theme_stylebox_override("panel")


func _apply_to_ui() -> void:
	var icon_node_path := NodePath("HBoxContainer/Icon")
	if has_node(icon_node_path):
		var icon_rect := get_node(icon_node_path) as TextureRect
		if icon_rect:
			icon_rect.texture = profile_texture

	var name_path := NodePath("HBoxContainer/VBoxContainer/Name")
	if has_node(name_path):
		var name_label := get_node(name_path) as Label
		if name_label:
			name_label.text = contact_name

	var last_path := NodePath("HBoxContainer/VBoxContainer/Last_message")
	if has_node(last_path):
		var last_label := get_node(last_path) as Label
		if last_label:
			var last_text := get_last_message_text()
			last_label.text = last_text

func refresh_last_message(text_override: String = "") -> void:
	# Update only the last message label; used by chat handler when new messages arrive
	var last_path := NodePath("HBoxContainer/VBoxContainer/Last_message")
	if has_node(last_path):
		var last_label := get_node(last_path) as Label
		if last_label:
			if text_override != "":
				last_label.text = text_override
			else:
				last_label.text = get_last_message_text()

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			contact_selected.emit(chat_json_path)
			accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			contact_selected.emit(chat_json_path)
			accept_event()

func unread_message():
	$HBoxContainer/notification.show()

func clear_notifcations():
	$HBoxContainer/notification.hide()

func clear_notifications():
	clear_notifcations()
