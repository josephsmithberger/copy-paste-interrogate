extends Control

@onready var _video_player: VideoStreamPlayer = $VideoStreamPlayer

func _ready() -> void:
	# Connect to the finished signal to transition when video ends
	_video_player.finished.connect(_on_video_finished)
	
	# Load video with threaded loading for better web performance
	_load_video_threaded()

func _load_video_threaded() -> void:
	var video_path := "res://assets/getCroppedImage.ogv"
	
	# Request threaded load
	ResourceLoader.load_threaded_request(video_path)
	
	# Wait for loading to complete
	while true:
		var status = ResourceLoader.load_threaded_get_status(video_path)
		
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var video_stream = ResourceLoader.load_threaded_get(video_path)
			_video_player.stream = video_stream
			_video_player.play()
			break
		elif status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE or status == ResourceLoader.THREAD_LOAD_FAILED:
			push_error("Failed to load intro video")
			# Skip to main scene if video fails to load
			SceneManager.change_scene("main")
			break
		
		# Wait a frame before checking again
		await get_tree().process_frame

func _on_video_finished() -> void:
	# Switch to main scene when video is done
	SceneManager.change_scene("main")
