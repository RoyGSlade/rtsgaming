@tool
extends EditorPlugin

const MainScreen := preload("res://addons/world_forge/world_forge_main.gd")

var _main: Control


func _enter_tree() -> void:
	_main = MainScreen.new()
	_main.name = "WorldForge"
	_main.setup(self)
	EditorInterface.get_editor_main_screen().add_child(_main)
	_make_visible(false)


func _exit_tree() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	_main = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_main):
		_main.visible = visible


func _get_plugin_name() -> String:
	return "World Forge"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("GridMap", "EditorIcons")
