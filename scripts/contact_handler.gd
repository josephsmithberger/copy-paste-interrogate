extends VBoxContainer


const CONTACT_CARD_SCENE_PATH := "res://scenes/contact_card.tscn"
const CHATS_DIR := "res://scripts/chats"
const USER_CHATS_DIR := "user://chats"

@onready var _anchor: Node = $Search_padding2
@onready var _search: LineEdit = $search

var _is_web := OS.has_feature("web")

func _ready() -> void:
	# Populate list after the scene tree settles
	call_deferred("_populate_contact_list")
	# Connect search box
	if _search:
		_search.text_changed.connect(_on_search_text_changed)

func _populate_contact_list() -> void:
	if _anchor == null:
		push_error("contact_handler: 'Search_padding2' node not found.")
		return

	# Clear any previously added items below the anchor
	var anchor_index := _anchor.get_index()
	while get_child_count() > anchor_index + 1:
		var to_remove := get_child(anchor_index + 1)
		to_remove.queue_free()

	var card_scene := load(CONTACT_CARD_SCENE_PATH)
	if not (card_scene is PackedScene):
		push_error("contact_handler: Failed to load contact card scene: %s" % CONTACT_CARD_SCENE_PATH)
		return

	# Determine which directory to use
	var chat_dir := CHATS_DIR
	if _is_web:
		# Check if user has imported custom dialogues
		var user_dir := DirAccess.open(USER_CHATS_DIR)
		if user_dir != null:
			var user_files := DirAccess.get_files_at(USER_CHATS_DIR)
			if not user_files.is_empty():
				chat_dir = USER_CHATS_DIR
	
	var files := DirAccess.get_files_at(chat_dir)
	if files.is_empty():
		push_warning("contact_handler: No files found in %s" % chat_dir)
	files.sort() # Stable order

	# NOTE: Cards add themselves to the 'contact_cards' group in their _ready().
	# We rely on that for single-selection logic managed by ChatHandler.

	var insert_after: Node = _anchor
	var added := 0
	var file_count := 0
	
	# Count valid JSON files first
	for f in files:
		if not f.begins_with(".") and f.get_extension().to_lower() == "json":
			file_count += 1
	
	for f in files:
		if f.begins_with("."):
			continue
		if f.get_extension().to_lower() != "json":
			continue

		var card := (card_scene as PackedScene).instantiate()
		var json_path := chat_dir + "/" + f

		# Set exported json path on the card's script
		card.chat_json_path = json_path

		add_child(card)
		move_child(card, insert_after.get_index() + 1)

		added += 1
		
		# Add a separator between entries (but not after the last one)
		if added < file_count:
			var sep := HSeparator.new()
			add_child(sep)
			move_child(sep, card.get_index() + 1)
			insert_after = sep
		else:
			insert_after = card

	if added == 0:
		push_warning("contact_handler: No JSON chats found in %s" % chat_dir)

	# Apply any existing search text (e.g., if user typed early or restored state)
	_filter_contacts()


# Called whenever the search text changes
func _on_search_text_changed(_new_text: String) -> void:
	_filter_contacts()

func _filter_contacts() -> void:
	var query := ""
	if _search:
		query = _search.text.strip_edges().to_lower()

	var anchor_index := _anchor.get_index()
	# Collect cards for filtering; they were added as: Card, HSeparator, Card, HSeparator, ...
	for i in range(anchor_index + 1, get_child_count()):
		var node := get_child(i)
		if node is ChatJsonView:
			var card: ChatJsonView = node
			var contact_name := card.get_contact_display_name().to_lower()
			var match := query == "" or contact_name.find(query) != -1
			card.visible = match
			# Hide/show the separator immediately following the card (if any)
			if card.get_index() + 1 < get_child_count():
				var maybe_sep := get_child(card.get_index() + 1)
				if maybe_sep is HSeparator:
					maybe_sep.visible = match

	# Optional: could collapse double separators / leading / trailing, but simple visibility pairing is fine.
