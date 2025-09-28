extends Control

signal notification_clicked(chat_path: String)

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var timer: Timer = $Timer
@onready var audio: AudioStreamPlayer = $AudioStreamPlayer

var showing: bool = false
var _target_chat_path: String = ""

func notification_in(profile_path: String, contact_name: String, message_preview: String, chat_path: String = "") -> void:
	var tex := load(profile_path)
	if tex is Texture2D:
		$PanelContainer/HBoxContainer/TextureRect.texture = tex
	$PanelContainer/HBoxContainer/VBoxContainer/Name.text = contact_name
	$PanelContainer/HBoxContainer/VBoxContainer/Message_preview.text = message_preview
	_target_chat_path = chat_path
	showing = true
	if timer:
		timer.stop()
		timer.start()
	if audio:
		audio.stop()
		audio.play()
	anim.play("in")

func notification_out() -> void:
	if not showing:
		return
	showing = false
	_target_chat_path = ""
	anim.play("out")
	if timer:
		timer.stop()

func _on_panel_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _target_chat_path != "":
			notification_clicked.emit(_target_chat_path)
		notification_out()

func _on_timer_timeout() -> void:
	if showing:
		notification_out()

func get_target_chat_path() -> String:
	return _target_chat_path
