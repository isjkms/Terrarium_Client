extends Control

## CL-024: 메뉴/설정 화면. 게임 오버레이(1280×240, main.tscn)와 분리된 더 큰 창.
## 앱 시작 시 이 씬이 먼저 뜨고, "시작"을 누르면 게임 오버레이 씬으로 전환한다.
const MENU_SIZE := Vector2i(1280, 720)

@onready var _room_edit: LineEdit = $Center/VBox/RoomEdit
@onready var _nick_edit: LineEdit = $Center/VBox/NickEdit
@onready var _error_label: Label = $Center/VBox/ErrorLabel

func _ready() -> void:
	_configure_menu_window()
	# CL-022: 게임 씬에서 join 실패로 되돌아온 경우 서버 error를 표시.
	_error_label.text = Session.last_error
	Session.last_error = ""

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
	# CL-022: 입력한 room/nickname을 공유 상태에 저장 후 게임 오버레이 씬으로 전환.
	# roomId는 프로토콜상 영숫자 대문자라 대문자로 정규화. 빈 값은 기본값 유지.
	var room := _room_edit.text.strip_edges().to_upper()
	var nick := _nick_edit.text.strip_edges()
	Session.room_id = room if room != "" else "ROOM01"
	Session.nickname = nick if nick != "" else "player"
	# 창 재설정은 main.gd가 담당한다.
	get_tree().change_scene_to_file("res://main.tscn")
