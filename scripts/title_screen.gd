extends Control

@onready var _start_game: MarginContainer = $CenterContainer/VBoxContainer/Start_game
@onready var _dialogue_creator: MarginContainer = $CenterContainer/VBoxContainer/Dialogue_creator

var _is_transitioning := false

func _ready() -> void:
	# Start cute idle animations
	_animate_idle(_start_game, 0.0)
	_animate_idle(_dialogue_creator, 0.5)

func _animate_idle(node: Node, delay: float) -> void:
	# Oscillating float animation
	var tween := create_tween().set_loops()
	tween.tween_interval(delay)
	tween.tween_property(node, "position:y", -10, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).as_relative()
	tween.tween_property(node, "position:y", 10, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).as_relative()

func _on_start_game_gui_input(event: InputEvent) -> void:
	if _is_transitioning:
		return
	
	# Handle both mouse click and touch
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_trigger_start_game()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_trigger_start_game()

func _on_dialogue_creator_gui_input(event: InputEvent) -> void:
	if _is_transitioning:
		return
	
	# Handle both mouse click and touch
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_trigger_dialogue_creator()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_trigger_dialogue_creator()

func _trigger_start_game() -> void:
	_is_transitioning = true
	_play_bounce_animation(_start_game)
	await get_tree().create_timer(0.3).timeout
	SceneManager.change_scene("main")

func _trigger_dialogue_creator() -> void:
	_is_transitioning = true
	_play_bounce_animation(_dialogue_creator)
	await get_tree().create_timer(0.3).timeout
	SceneManager.change_scene("import")

func _play_bounce_animation(node: Node) -> void:
	# Cute jump/bounce animation
	var tween := create_tween()
	tween.set_parallel(true)
	# Jump up
	tween.tween_property(node, "position:y", -30, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).as_relative()
	# Scale squeeze
	tween.tween_property(node, "scale", Vector2(1.1, 0.9), 0.1).set_trans(Tween.TRANS_QUAD)
	tween.chain()
	# Come back down
	tween.tween_property(node, "position:y", 30, 0.15).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT).as_relative()
	# Scale back
	tween.tween_property(node, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
