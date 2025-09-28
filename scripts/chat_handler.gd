extends ChatJsonView

# ChatHandler
# Listens for contact_card "contact_selected(chat_path)" signals, loads the
# referenced chat JSON (via inherited reload_with_path) and populates:
#  - Profile icon: $VBoxContainer/Profile_icon
#  - Message bubbles inside $ScrollContainer/VBoxContainer
#    * contact / other author -> res://scenes/npc_message_bubble.tscn
#    * player author          -> res://scenes/user_message_bubble.tscn
#
# This script purposefully overrides _ready WITHOUT calling the base implementation
# so that the default template JSON is NOT auto-loaded. Data only appears after
# the user selects a contact.

const NPC_BUBBLE_SCENE_PATH := "res://scenes/npc_message_bubble.tscn"
const PLAYER_BUBBLE_SCENE_PATH := "res://scenes/user_message_bubble.tscn"


var _npc_bubble_scene: PackedScene
var _player_bubble_scene: PackedScene
var _loaded_once: bool = false
var _bottom_sep: HSeparator
var _scroll_tween: Tween

# Public knobs
@export var scroll_ease_duration: float = 0.5

# Current contact context
var current_contact_path: String = ""
var _current_contact_card: Node

@onready var _profile_icon: TextureRect = $VBoxContainer/Profile_icon
@onready var _scroll: ScrollContainer = $ScrollContainer
@onready var _messages_root: VBoxContainer = $ScrollContainer/VBoxContainer
@onready var _message_input: LineEdit = $VBoxContainer/Message
@onready var send_audio:AudioStreamPlayer = $send_audio
@onready var recieve_audio:AudioStreamPlayer = $recieve_audio

func _ready() -> void:
	# Do not call super._ready(); we only load when a contact is clicked.
	_npc_bubble_scene = load(NPC_BUBBLE_SCENE_PATH)
	_player_bubble_scene = load(PLAYER_BUBBLE_SCENE_PATH)
	_connect_existing_contact_cards()
	_watch_for_new_contact_cards()
	# Disable input until a contact is selected
	if _message_input:
		_message_input.editable = false
		_message_input.placeholder_text = "Select a contact to start"
	# No implicit auto-selection; user must click a contact

func _connect_existing_contact_cards() -> void:
	var contact_list := _get_contact_list()
	if contact_list == null:
		return
	for child in contact_list.get_children():
		_try_connect_card(child)

func _watch_for_new_contact_cards() -> void:
	var contact_list := _get_contact_list()
	if contact_list == null:
		return
	if not contact_list.is_connected("child_entered_tree", Callable(self, "_on_contact_list_child_entered")):
		contact_list.connect("child_entered_tree", Callable(self, "_on_contact_list_child_entered"))
	else:
		pass

func _on_contact_list_child_entered(child: Node) -> void:
	_try_connect_card(child)
	# No auto-selection logic

func _try_connect_card(node: Node) -> void:
	if node == null:
		return
	if not node.has_signal("contact_selected"):
		# Likely a separator or non-card.
		return
	if node.is_connected("contact_selected", Callable(self, "_on_contact_selected")):
		return
	# Bind the node so the handler knows which card emitted the signal
	node.connect("contact_selected", Callable(self, "_on_contact_selected").bind(node))

func _get_contact_list() -> Node:
	# ChatView (this) path: MarginContainer/HSplitContainer/ChatView
	# Contact list container node (named 'Chatlist' in the scene currently)
	var path := NodePath("../PanelContainer/ScrollContainer/Chatlist") # Keep node name until renamed in scene
	if has_node(path):
		return get_node(path)
	return null

func _on_contact_selected(chat_path: String, card: Node) -> void:
	# If we have never loaded, force load even if path matches default.
	if chat_path == chat_json_path and _loaded_once and card == _current_contact_card:
		# Same card re-clicked; nothing to change.
		return
	reload_with_path(chat_path)
	current_contact_path = chat_path
	_current_contact_card = card

	# Visual selection: unselect ALL existing cards via group (more robust than relying only on list hierarchy)
	for c in get_tree().get_nodes_in_group("contact_cards"):
		if c.has_method("set_selected"):
			c.set_selected(c == card)

	# (Optional) Fallback: if group was somehow empty, use the original contact list traversal
	if get_tree().get_nodes_in_group("contact_cards").is_empty():
		var contact_list := _get_contact_list()
		if contact_list:
			for child in contact_list.get_children():
				if child.has_method("set_selected"):
					child.set_selected(child == card)

func _apply_to_ui() -> void:
	# Called after a successful load in reload_with_path().
	# Inform DialogueEngine about the loaded conversation so it can track steps
	var engine := get_node_or_null("/root/DialogueEngine")
	if engine:
		# Re-open the JSON to get the raw dictionary used by the engine
		var file := FileAccess.open(chat_json_path, FileAccess.READ)
		if file:
			var text := file.get_as_text()
			file.close()
			var data: Variant = JSON.parse_string(text)
			if typeof(data) == TYPE_DICTIONARY:
				# Do not force reload if already present; preserves step index & history
				engine.load_conversation(chat_json_path, data, false)
	_apply_profile_icon()
	_rebuild_message_bubbles()
	_seed_vocabulary_from_history()
	_defer_scroll_to_bottom()
	_loaded_once = true
	# Enable input once a chat is loaded
	if _message_input:
		_message_input.editable = true
		_message_input.placeholder_text = "Message"

func _apply_profile_icon() -> void:
	if _profile_icon:
		_profile_icon.texture = profile_texture

func _rebuild_message_bubbles() -> void:
	if _messages_root == null:
		return
	# Clear existing bubbles
	for c in _messages_root.get_children():
		c.queue_free()

	# Add a top separator so there's always scrollable space above the first message
	var top_sep := HSeparator.new()
	top_sep.name = "TopSeparator"
	top_sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Provide 50px vertical space at the top for scroll offset purposes
	top_sep.custom_minimum_size = Vector2(0, 100)
	# Make the separator invisible by using an empty style box
	top_sep.add_theme_stylebox_override("separator", StyleBoxEmpty.new())
	_messages_root.add_child(top_sep)

	# Prefer full persistent history from DialogueEngine if available
	var engine := get_node_or_null("/root/DialogueEngine")
	var display_history: Array = []
	if engine and engine.has_method("get_history"):
		display_history = engine.get_history(chat_json_path)
	if display_history.is_empty():
		display_history = chat_history

	for entry in display_history:
		var author := str(entry.get("author", "contact"))
		var text := str(entry.get("text", ""))
		var scene: PackedScene = _npc_bubble_scene
		if author == "player":
			scene = _player_bubble_scene
		if scene == null:
			continue
		var bubble := scene.instantiate()

		# Create a horizontal row container to control alignment & eliminate opposite-side negative space
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_FILL  # Row spans width; bubble won't
		_messages_root.add_child(row)

		# Spacer logic: left-aligned (NPC) -> spacer AFTER bubble; right-aligned (player) -> spacer BEFORE bubble
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if author == "player":
			# Right aligned: push bubble to the right by putting expandable spacer first
			row.add_child(spacer)
			row.add_child(bubble)
		else:
			# Left aligned: bubble first, spacer after
			row.add_child(bubble)
			row.add_child(spacer)

		# Ensure bubble itself does NOT expand horizontally so it shrinks to its content
		if bubble is Control:
			bubble.size_flags_horizontal = 0

		# Populate text using helper if available
		if bubble.has_method("set_message_text"):
			bubble.set_message_text(text)
		else:
			var label := bubble.get_node_or_null("MarginContainer/message")
			if label is RichTextLabel:
				label.text = text

	# Add and cache a bottom separator so it's always the last child
	_bottom_sep = HSeparator.new()
	_bottom_sep.name = "BottomSeparator"
	_bottom_sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom_sep.custom_minimum_size = Vector2(0, 100)
	_bottom_sep.add_theme_stylebox_override("separator", StyleBoxEmpty.new())
	_messages_root.add_child(_bottom_sep)

func _defer_scroll_to_bottom() -> void:
	# Ensure layout updates settle over a couple of frames, then scroll
	call_deferred("_scroll_to_bottom_async")

func _scroll_to_bottom() -> void:
	if _scroll == null:
		return
	# Use scroll_vertical property directly instead of scrollbar value
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _scroll_to_bottom_async() -> void:
	# Wait two frames to allow fonts/layout to settle, then scroll
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll_to_bottom()

func _scroll_to_bottom_smooth(duration: float = 0.5) -> void:
	if _scroll == null:
		return
	# Run async to avoid blocking callers; fire-and-forget
	_call_deferred_scroll_smooth(duration)

func _call_deferred_scroll_smooth(duration: float) -> void:
	_scroll_smooth_async(duration)

func _scroll_smooth_async(duration: float) -> void:
	await get_tree().process_frame
	await get_tree().process_frame # two frames for font wrap/layout stability
	if _scroll == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	var target := int(bar.max_value)
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()
	var start := _scroll.scroll_vertical
	if target <= start:
		return
	_scroll_tween = create_tween()
	_scroll_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_scroll_tween.tween_property(_scroll, "scroll_vertical", target, duration)


func _on_message_text_submitted(new_text: String) -> void:
	var text := new_text.strip_edges()
	if text == "":
		return
	# Don’t allow sending if no contact is open
	if current_contact_path == "" or not _loaded_once:
		_show_no_contact_feedback()
		return
	var engine := get_node_or_null("/root/DialogueEngine")
	if engine == null:
		push_error("chat_handler: DialogueEngine autoload not found")
		return
	# Process via engine; contact_id is the current chat_json_path
	var res: Dictionary = engine.process_input(chat_json_path, text)
	var status := str(res.get("status", ""))
	match status:
		"rejected":
			_show_reject_feedback(res.get("unknown_words", []))
			return
		"success":
			_append_player_bubble(text)
			var lines_s: Array = res.get("npc_messages", [])
			await _append_npc_messages_with_delay(lines_s)
			_update_selected_contact_last_message(lines_s)
			# Clear only when accepted
			if _message_input:
				_message_input.clear()
			_scroll_to_bottom_smooth(scroll_ease_duration)
		"wrong":
			_append_player_bubble(text)
			var lines: Array = res.get("npc_messages", [])
			await _append_npc_messages_with_delay(lines)
			_update_selected_contact_last_message(lines)
			_scroll_to_bottom_smooth(scroll_ease_duration)
		_:
			# Fallback: treat as wrong
			_append_player_bubble(text)
			await _append_npc_messages_with_delay(["Huh?"])
			_update_selected_contact_last_message(["Huh?"])
			_scroll_to_bottom_smooth(scroll_ease_duration)

# _try_autoselect_template removed (legacy template loading)

func _append_player_bubble(text: String) -> void:
	send_audio.play()
	_append_bubble(text, true)

func _append_npc_bubble(text: String) -> void:
	recieve_audio.play()
	_append_bubble(text, false)

func _append_npc_messages_with_delay(lines: Array, delay: float = 0.3) -> void:
	for l in lines:
		await get_tree().create_timer(delay).timeout
		_append_npc_bubble(str(l))
		_scroll_to_bottom_smooth(scroll_ease_duration)

func _append_bubble(text: String, is_player: bool) -> void:
	if _messages_root == null:
		return
	var scene: PackedScene = _player_bubble_scene if is_player else _npc_bubble_scene
	if scene == null:
		return
	var bubble := scene.instantiate()
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_FILL
	# Ensure we insert above the bottom separator if it exists
	if _bottom_sep and _bottom_sep.get_parent() == _messages_root:
		_messages_root.add_child(row)
		_messages_root.move_child(row, _bottom_sep.get_index())
	else:
		_messages_root.add_child(row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_player:
		row.add_child(spacer)
		row.add_child(bubble)
	else:
		row.add_child(bubble)
		row.add_child(spacer)
	if bubble is Control:
		bubble.size_flags_horizontal = 0
	if bubble.has_method("set_message_text"):
		bubble.set_message_text(text)
	else:
		var label := bubble.get_node_or_null("MarginContainer/message")
		if label is RichTextLabel:
			label.text = text
	# Keep bottom separator as last child
	if _bottom_sep and _bottom_sep.get_parent() == _messages_root:
		_messages_root.move_child(_bottom_sep, _messages_root.get_child_count() - 1)

func _update_selected_contact_last_message(lines: Array) -> void:
	var contact_list := _get_contact_list()
	if contact_list == null:
		return
	# Find the selected card by matching its chat_json_path
	for child in contact_list.get_children():
		if child.has_method("refresh_last_message") and child is ChatJsonView and child.chat_json_path == chat_json_path:
			var last_text := str(lines.back()) if lines.size() > 0 else ""
			child.refresh_last_message(last_text)
			break

func _seed_vocabulary_from_history() -> void:
	var vocab := get_node_or_null("/root/Vocabulary")
	if vocab == null:
		return
	# Add tokens from contact-authored history entries so the player can reuse seen words
	for entry in chat_history:
		var author := str(entry.get("author", "contact"))
		if author == "contact":
			var text := str(entry.get("text", ""))
			vocab.add_words([text])

func _show_reject_feedback(_unknown_words: Array) -> void:
	# Minimal feedback: flash the input field red via a modulate tween
	var input := $VBoxContainer/Message as LineEdit
	if input == null:
		return
	var tween := create_tween()
	var orig := input.modulate
	input.modulate = Color(1, 0.7, 0.7)
	tween.tween_property(input, "modulate", orig, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _show_no_contact_feedback() -> void:
	var input := $VBoxContainer/Message as LineEdit
	if input == null:
		return
	var orig_placeholder := input.placeholder_text
	input.placeholder_text = "Select a contact first"
	var tween := create_tween()
	var orig_pos := input.position
	var shake := 6.0
	tween.tween_property(input, "position", orig_pos + Vector2(shake, 0), 0.05)
	tween.tween_property(input, "position", orig_pos - Vector2(shake, 0), 0.05)
	tween.tween_property(input, "position", orig_pos, 0.05)
	await tween.finished
	input.placeholder_text = orig_placeholder
