extends MarginContainer

# Improved user message bubble logic: keeps bubble tightly fit around text,
# avoids extra padding, and ensures NinePatch matches content dimensions.

@onready var bubble: NinePatchRect = $bubble
@onready var content_box: MarginContainer = $MarginContainer
@onready var message_label: RichTextLabel = $MarginContainer/message

const MAX_WIDTH: int = 420   # Hard wrap ceiling (tweakable)
const SOFT_WIDTH: int = 380  # Preferred max before wrapping (iMessage feel)
const MIN_WIDTH: int = 48    # Allow very short words without forced wide bubble

var _pending_text: String = ""

func _ready():
	if message_label:
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message_label.fit_content = true
		message_label.selection_enabled = true
	# Run one sync in case scene has placeholder text
	call_deferred("_final_layout_sync")

func set_message_text(text: String):
	_pending_text = text
	if not is_inside_tree():
		await ready
	message_label.text = text
	call_deferred("_measure_and_resize")

func _measure_and_resize():
	if not message_label:
		return
	# Step 1: allow it to expand without wrap to measure natural width up to MAX_WIDTH
	message_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	message_label.custom_minimum_size.x = 0
	await get_tree().process_frame
	var natural: float = float(message_label.size.x)

	var target_width: float = clamp(natural, float(MIN_WIDTH), float(SOFT_WIDTH))
	var needs_wrap := natural > SOFT_WIDTH
	if needs_wrap:
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message_label.custom_minimum_size.x = SOFT_WIDTH
	else:
		message_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		message_label.custom_minimum_size.x = target_width

	await get_tree().process_frame
	_final_layout_sync()

func _final_layout_sync():
	# Ensure NinePatch bubble matches the content box size exactly.
	if bubble and content_box:
		bubble.size = content_box.size
		# Because root (this) is a MarginContainer containing both siblings, set its size to content.
		size = content_box.size

func _process(_delta):
	# Lightweight continuous sync in case of dynamic font fallback or selection expanding.
	if bubble and content_box:
		if bubble.size != content_box.size:
			bubble.size = content_box.size
			# Keep root tight as well
			size = content_box.size
