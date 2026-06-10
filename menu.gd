extends Control

## CL-024: 메뉴/설정 화면. 게임 오버레이(1280×240, main.tscn)와 분리된 더 큰 창.
## 앱 시작 시 이 씬이 먼저 뜨고, "시작"을 누르면 게임 오버레이 씬으로 전환한다.
const MENU_SIZE := Vector2i(800, 500)

func _ready() -> void:
	_configure_menu_window()

func _configure_menu_window() -> void:
	# 게임 오버레이용 창 플래그(투명/borderless/항상위)를 일반 창으로 되돌린다.
	# project.godot 기본값이 오버레이용이므로 메뉴 진입 시 명시적으로 해제한다.
	get_viewport().transparent_bg = false
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	DisplayServer.window_set_size(MENU_SIZE)
	_center_window()

func _center_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var win_size := DisplayServer.window_get_size()
	var pos := usable.position + (usable.size - win_size) / 2
	DisplayServer.window_set_position(pos)

func _on_start_pressed() -> void:
	# 게임 오버레이 씬으로 전환. 창 재설정은 main.gd가 담당한다.
	get_tree().change_scene_to_file("res://main.tscn")
