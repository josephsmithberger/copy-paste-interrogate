extends MarginContainer

# Improved user message bubble logic: keeps bubble tightly fit around text,
# avoids extra padding, and ensures NinePatch matches content dimensions.

@onready var bubble: NinePatchRect = $bubble
@onready var content_box: MarginContainer = $MarginContainer
@onready var message_label: RichTextLabel = $MarginContainer/message

const MIN_WIDTH: int = 48    # Allow very short words without forced wide bubble
const DEFAULT_SOFT_WIDTH: float = 380.0

var _pending_text: String = ""
var _max_content_width: float = DEFAULT_SOFT_WIDTH

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
	_measure_and_resize()

func set_max_content_width(width: float) -> void:
	var clamped: float = max(float(MIN_WIDTH), width)
	if absf(clamped - _max_content_width) < 0.5:
		return
	_max_content_width = clamped
	if is_inside_tree():
		_measure_and_resize()

func _measure_and_resize():
	if not message_label:
		return
	var font := message_label.get_theme_font("normal_font")
	if font == null:
		font = message_label.get_theme_font("font")
	var font_size: int = message_label.get_theme_font_size("normal_font")
	if font_size == -1:
		font_size = message_label.get_theme_font_size("font_size")
	if font_size <= 0:
		font_size = 16
	var text := message_label.text
	var lines: PackedStringArray = text.split("\n")
	if lines.is_empty():
		lines.append(text)
	var natural: float = float(MIN_WIDTH)
	if font:
		var max_width: float = 0.0
		for line in lines:
			var line_width := font.get_string_size(line, font_size).x
			if line_width > max_width:
				max_width = line_width
		natural = max_width
	else:
		natural = float(text.length()) * float(font_size) * 0.5
	var soft_width: float = max(float(MIN_WIDTH), _max_content_width)
	var padding: float = _get_horizontal_padding()
	var label_min: float = max(12.0, float(MIN_WIDTH) - padding)
	var label_soft: float = max(label_min, soft_width - padding)
	var target_width: float = clamp(natural, label_min, label_soft)
	var needs_wrap: bool = natural > label_soft
	if needs_wrap:
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message_label.custom_minimum_size.x = label_soft
	else:
		message_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		message_label.custom_minimum_size.x = target_width
	message_label.reset_size()
	_final_layout_sync()

func _get_horizontal_padding() -> float:
	if content_box == null:
		return 0.0
	var left := float(content_box.get_theme_constant("margin_left", "MarginContainer"))
	var right := float(content_box.get_theme_constant("margin_right", "MarginContainer"))
	return max(0.0, left + right)

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
