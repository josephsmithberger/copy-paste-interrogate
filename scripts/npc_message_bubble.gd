extends MarginContainer

# NPC version of bubble script with same sizing logic as user bubble.

@onready var bubble: NinePatchRect = $bubble
@onready var content_box: MarginContainer = $MarginContainer
@onready var message_label: RichTextLabel = $MarginContainer/message

const MAX_WIDTH: int = 420
const SOFT_WIDTH: int = 380
const MIN_WIDTH: int = 48

func _ready():
	if message_label:
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message_label.fit_content = true
	call_deferred("_final_layout_sync")

func set_message_text(text: String):
	if not is_inside_tree():
		await ready
	message_label.text = text
	call_deferred("_measure_and_resize")

func _measure_and_resize():
	if not message_label:
		return
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
	if bubble and content_box:
		bubble.size = content_box.size
		size = content_box.size

func _process(_delta):
	if bubble and content_box and bubble.size != content_box.size:
		bubble.size = content_box.size
		size = content_box.size
