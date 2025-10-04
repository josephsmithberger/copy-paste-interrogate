extends Control

const CHATS_DIR := "res://scripts/chats"

@onready var _file_dialog: FileDialog = $FileDialog
@onready var _select_button: Button = $CenterContainer/VBoxContainer/SelectButton
@onready var _import_button: Button = $CenterContainer/VBoxContainer/ImportButton
@onready var _back_button: Button = $CenterContainer/VBoxContainer/BackButton
@onready var _status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

var _selected_files: PackedStringArray = []
var _is_web := OS.has_feature("web")

func _ready() -> void:
	_select_button.pressed.connect(_on_select_button_pressed)
	_import_button.pressed.connect(_on_import_button_pressed)
	_back_button.pressed.connect(_on_back_button_pressed)
	
	if not _is_web:
		_file_dialog.files_selected.connect(_on_files_selected)
	else:
		# For web builds, we'll use JavaScript file input
		_setup_web_file_input()

func _setup_web_file_input() -> void:
	if not _is_web:
		return
	
	# Create a hidden HTML file input element
	JavaScriptBridge.eval("""
		if (!window.godotFileInput) {
			var input = document.createElement('input');
			input.type = 'file';
			input.accept = '.json';
			input.multiple = true;
			input.style.display = 'none';
			document.body.appendChild(input);
			window.godotFileInput = input;
			
			input.addEventListener('change', function(e) {
				var files = e.target.files;
				if (files.length > 0) {
					var fileData = [];
					var loadedCount = 0;
					
					for (var i = 0; i < files.length; i++) {
						(function(file) {
							var reader = new FileReader();
							reader.onload = function(event) {
								fileData.push({
									name: file.name,
									content: event.target.result
								});
								loadedCount++;
								
								if (loadedCount === files.length) {
									window.godotDialogueFiles = fileData;
									// Signal Godot that files are ready
									if (window.godotOnFilesLoaded) {
										window.godotOnFilesLoaded();
									}
								}
							};
							reader.readAsText(file);
						})(files[i]);
					}
				}
			});
		}
	""")

func _on_select_button_pressed() -> void:
	if _is_web:
		# Set up callback for when files are loaded
		JavaScriptBridge.eval("""
			window.godotOnFilesLoaded = function() {
				// Will be handled by _process polling
			};
			window.godotFileInput.click();
		""")
		# Start polling for file data
		set_process(true)
	else:
		_file_dialog.popup_centered()

func _process(_delta: float) -> void:
	if _is_web:
		# Check if files have been loaded
		var has_files = JavaScriptBridge.eval("window.godotDialogueFiles && window.godotDialogueFiles.length > 0")
		if has_files:
			_on_web_files_selected()
			set_process(false)

func _on_web_files_selected() -> void:
	var file_count = JavaScriptBridge.eval("window.godotDialogueFiles.length")
	var file_names: Array[String] = []
	
	for i in range(file_count):
		var file_name = JavaScriptBridge.eval("window.godotDialogueFiles[%d].name" % i)
		file_names.append(file_name)
	
	_status_label.text = "Selected: " + ", ".join(file_names)
	_import_button.disabled = false
	
	# Store that we have web files ready
	_selected_files = PackedStringArray(file_names)

func _on_files_selected(paths: PackedStringArray) -> void:
	_selected_files = paths
	_status_label.text = "Selected %d file(s)" % paths.size()
	_import_button.disabled = paths.size() == 0
	
	# Update status label with filenames
	if paths.size() > 0:
		var file_names: Array[String] = []
		for path in paths:
			file_names.append(path.get_file())
		_status_label.text = "Selected: " + ", ".join(file_names)

func _on_import_button_pressed() -> void:
	if _selected_files.size() == 0:
		_status_label.text = "No files selected!"
		return
	
	_status_label.text = "Importing..."
	_import_button.disabled = true
	_select_button.disabled = true
	
	# Delete all existing dialogue files
	var delete_success := _delete_existing_dialogues()
	if not delete_success:
		_status_label.text = "Failed to delete existing dialogues!"
		_import_button.disabled = false
		_select_button.disabled = false
		return
	
	# Import new files
	var imported_count := 0
	if _is_web:
		imported_count = _import_web_files()
	else:
		for file_path in _selected_files:
			if _import_dialogue_file(file_path):
				imported_count += 1
	
	if imported_count == _selected_files.size():
		_status_label.text = "Successfully imported %d dialogue(s)!" % imported_count
		# Wait a moment before returning to game
		await get_tree().create_timer(1.5).timeout
		_return_to_game()
	else:
		_status_label.text = "Imported %d/%d files (some failed)" % [imported_count, _selected_files.size()]
		_import_button.disabled = false
		_select_button.disabled = false

func _delete_existing_dialogues() -> bool:
	var target_dir := CHATS_DIR
	
	# In web builds, use user:// directory
	if _is_web:
		target_dir = "user://chats"
		# Create directory if it doesn't exist
		DirAccess.make_dir_recursive_absolute(target_dir)
	
	var dir := DirAccess.open(target_dir)
	if dir == null:
		push_error("Failed to open directory: " + target_dir)
		return false
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path := target_dir + "/" + file_name
			var result := dir.remove(file_name)
			if result != OK:
				push_error("Failed to delete file: " + full_path)
				dir.list_dir_end()
				return false
			print("Deleted: " + full_path)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return true

func _import_web_files() -> int:
	var file_count = JavaScriptBridge.eval("window.godotDialogueFiles.length")
	var imported_count := 0
	
	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute("user://chats")
	
	for i in range(file_count):
		var file_name: String = JavaScriptBridge.eval("window.godotDialogueFiles[%d].name" % i)
		var content: String = JavaScriptBridge.eval("window.godotDialogueFiles[%d].content" % i)
		
		# Validate JSON
		var json := JSON.new()
		var parse_result := json.parse(content)
		if parse_result != OK:
			push_error("Invalid JSON in file: " + file_name)
			continue
		
		# Write to user:// directory (writable in web builds)
		var dest_path: String = "user://chats/" + file_name
		
		var dest_file := FileAccess.open(dest_path, FileAccess.WRITE)
		if dest_file == null:
			push_error("Failed to create destination file: " + dest_path)
			continue
		
		dest_file.store_string(content)
		dest_file.close()
		
		print("Imported (web): " + file_name + " -> " + dest_path)
		imported_count += 1
	
	# Clear the JavaScript file data
	JavaScriptBridge.eval("window.godotDialogueFiles = [];")
	
	return imported_count

func _import_dialogue_file(source_path: String) -> bool:
	# Read the source file (native builds only)
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open source file: " + source_path)
		return false
	
	var content := file.get_as_text()
	file.close()
	
	# Validate JSON
	var json := JSON.new()
	var parse_result := json.parse(content)
	if parse_result != OK:
		push_error("Invalid JSON in file: " + source_path)
		return false
	
	# Get the filename and create destination path
	var file_name := source_path.get_file()
	var dest_path := CHATS_DIR + "/" + file_name
	
	# Write to destination
	var dest_file := FileAccess.open(dest_path, FileAccess.WRITE)
	if dest_file == null:
		push_error("Failed to create destination file: " + dest_path)
		return false
	
	dest_file.store_string(content)
	dest_file.close()
	
	print("Imported: " + file_name + " -> " + dest_path)
	return true

func _on_back_button_pressed() -> void:
	_return_to_game()

func _return_to_game() -> void:
	# Reset vocabulary and return to main scene
	Vocabulary.clear_all()
	SceneManager.change_scene("main")
