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

@onready var _profile_icon: TextureRect = $VBoxContainer/Profile_icon
@onready var _scroll: ScrollContainer = $ScrollContainer
@onready var _messages_root: VBoxContainer = $ScrollContainer/VBoxContainer

func _ready() -> void:
	# Do not call super._ready(); we only load when a contact is clicked.
	_npc_bubble_scene = load(NPC_BUBBLE_SCENE_PATH)
	_player_bubble_scene = load(PLAYER_BUBBLE_SCENE_PATH)
	_connect_existing_contact_cards()
	_watch_for_new_contact_cards()

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
	if chat_path == chat_json_path and _loaded_once:
		return
	reload_with_path(chat_path)

	# Visual selection: mark the card that emitted the signal as selected, others unselected
	var contact_list := _get_contact_list()
	if contact_list:
		for child in contact_list.get_children():
			if child.has_method("set_selected"):
				child.set_selected(child == card)

func _apply_to_ui() -> void:
	# Called after a successful load in reload_with_path().
	_apply_profile_icon()
	_rebuild_message_bubbles()
	_defer_scroll_to_bottom()
	_loaded_once = true

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
	_messages_root.add_child(top_sep)

	for entry in chat_history:
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

func _defer_scroll_to_bottom() -> void:
	# Ensure layout updated before scrolling
	call_deferred("_scroll_to_bottom")

func _scroll_to_bottom() -> void:
	if _scroll == null:
		return
	# Use scroll_vertical property directly instead of scrollbar value
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
