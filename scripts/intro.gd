extends Control

@onready var _video_player: VideoStreamPlayer = $VideoStreamPlayer

func _ready() -> void:
	# Connect to the finished signal to transition when video ends
	_video_player.finished.connect(_on_video_finished)

func _on_video_finished() -> void:
	# Switch to main scene when video is done
	SceneManager.change_scene("main")
