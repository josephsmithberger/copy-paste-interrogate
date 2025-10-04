extends Node

# Scene paths - preload these for web builds
const SCENES := {
	"title": "res://scenes/title_screen.tscn",
	"main": "res://scenes/main_window.tscn",
	"import": "res://scenes/dialogue_import.tscn"
}

var _is_changing := false

func change_scene(scene_key: String) -> void:
	if _is_changing:
		return
	
	if not scene_key in SCENES:
		push_error("SceneManager: Unknown scene key: " + scene_key)
		return
	
	var scene_path: String = SCENES[scene_key]
	
	_is_changing = true
	
	# Verify scene exists
	if not ResourceLoader.exists(scene_path):
		push_error("SceneManager: Scene file not found: " + scene_path)
		_is_changing = false
		return
	
	# Change scene
	var error := get_tree().change_scene_to_file(scene_path)
	
	if error != OK:
		push_error("SceneManager: Failed to change scene. Error code: " + str(error))
		_is_changing = false
	else:
		# Reset flag after a frame to allow the new scene to load
		await get_tree().process_frame
		_is_changing = false

func change_scene_to_path(scene_path: String) -> void:
	if _is_changing:
		return
	
	_is_changing = true
	
	# Verify scene exists
	if not ResourceLoader.exists(scene_path):
		push_error("SceneManager: Scene file not found: " + scene_path)
		_is_changing = false
		return
	
	# Change scene
	var error := get_tree().change_scene_to_file(scene_path)
	
	if error != OK:
		push_error("SceneManager: Failed to change scene. Error code: " + str(error))
		_is_changing = false
	else:
		# Reset flag after a frame
		await get_tree().process_frame
		_is_changing = false
