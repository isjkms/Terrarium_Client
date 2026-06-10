extends Node2D

## 월드 기준값 (protocol.md 기본값. welcome 수신 시 서버 값으로 갱신)
var world_width := 1280.0
var floor_y := 220.0

## 캐릭터 도형 크기
const CHAR_WIDTH := 24.0
const CHAR_HEIGHT := 40.0

## playerId → 색상 (protocol.md 캐릭터 색상)
const PLAYER_COLORS := {
	"p1": Color(0.2, 0.4, 0.9),    # 파랑
	"p2": Color(0.9, 0.25, 0.25),  # 빨강
	"p3": Color(0.3, 0.75, 0.3),   # 초록
	"p4": Color(0.95, 0.85, 0.2),  # 노랑
}

## 내 캐릭터 (서버 연결 전 고정값). floor_x는 0.0~1.0 비율.
var my_player_id := "p1"
var my_floor_x := 0.5

## 원격 캐릭터 (서버 연결 전 더미. CL-012에서 state 데이터로 교체)
var remote_players := {
	"p2": { "floor_x": 0.75 },
}

## 이동 속도 (픽셀/초). floorX는 비율이라 world_width로 나눠 비율 증분으로 변환.
const MOVE_SPEED := 220.0

## 입력 상태 (실제 이동 적용은 CL-006)
var _left_held := false
var _right_held := false
var move_dir := 0          # -1=왼, 0=정지, +1=오른
var facing := "right"      # protocol.md move의 facing 필드

## 서버 연결 (protocol.md). roomId/name은 메뉴 입력값(Session) 사용 (CL-022).
const WS_URL := "ws://13.209.96.232:8080/ws"
var _ws := WebSocketPeer.new()
var _ws_state := WebSocketPeer.STATE_CLOSED
var _joined := false       # STATE_OPEN 첫 프레임 join 중복 전송 방지

## CL-023: 끊김(STATE_CLOSED) 감지 시 일정 간격으로 자동 재연결
const RECONNECT_DELAY := 3.0
var _reconnecting := false
var _reconnect_accum := 0.0

## move 송신 (20Hz throttle + 값 변화 감지)
const MOVE_SEND_INTERVAL := 0.05
var _send_accum := 0.0
var _last_sent_floor_x := -1.0
var _last_sent_facing := ""

## CL-024: 게임 오버레이 창 크기 (project.godot viewport와 일치)
const GAME_SIZE := Vector2i(1280, 240)

func _ready() -> void:
	_configure_game_window()
	_setup_tray()
	_setup_chat_input()

	# CL-017 실험: 캐릭터/바닥 외 영역을 투명하게. project.godot의 transparent 설정과 함께 동작.
	get_viewport().transparent_bg = true

	var err := _ws.connect_to_url(WS_URL)
	if err != OK:
		push_error("[WS] 연결 시도 실패: %s" % error_string(err))

func _configure_game_window() -> void:
	# CL-024: 메뉴 씬에서 변경된 창 설정을 게임 오버레이용으로 되돌린다.
	DisplayServer.window_set_size(GAME_SIZE)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, _always_on_top)
	_position_window_bottom()

func _position_window_bottom() -> void:
	# CL-018: 주 모니터 하단(작업표시줄 제외 usable rect)에 가로 중앙으로 창 배치.
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var win_size := DisplayServer.window_get_size()
	var pos_x := usable.position.x + (usable.size.x - win_size.x) / 2
	var pos_y := usable.position.y + usable.size.y - win_size.y
	DisplayServer.window_set_position(Vector2i(pos_x, pos_y))

func _setup_tray() -> void:
	# CL-026: 시스템 트레이에 아이콘을 등록하고 '종료' 메뉴를 단다.
	# 트레이 미지원 플랫폼에서는 조용히 건너뛴다(ESC 종료는 그대로 유효).
	if not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		print("[CL-026] 트레이 아이콘 미지원 플랫폼")
		return
	var icon: Texture2D = load("res://icon.svg")
	_tray_id = DisplayServer.create_status_indicator(icon, "Monitor Terrarium", Callable(self, "_on_tray_clicked"))
	_tray_menu = NativeMenu.create_menu()
	NativeMenu.add_item(_tray_menu, "종료", Callable(self, "_on_tray_quit"))
	DisplayServer.status_indicator_set_menu(_tray_id, _tray_menu)

func _on_tray_clicked(_mouse_button: int, _mouse_position: Vector2i) -> void:
	# 메뉴가 연결돼 있으면 클릭 시 네이티브 메뉴가 자동으로 열리므로 별도 처리는 없다.
	pass

func _on_tray_quit(_tag: Variant = null) -> void:
	get_tree().quit()

func _exit_tree() -> void:
	# CL-026: 트레이 아이콘/메뉴 정리.
	if _tray_id != -1:
		DisplayServer.delete_status_indicator(_tray_id)
	if _tray_menu.is_valid():
		NativeMenu.free_menu(_tray_menu)

func _setup_chat_input() -> void:
	# CL-031: 말풍선 입력용 LineEdit. 평소엔 숨겨두고 Enter로 진입한다.
	# 영문 유효성 검증은 06_수정요약 결정에 따라 넣지 않는다(한글 IME는 CL-032).
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "메시지 입력 (Enter 전송 / Esc 취소)"
	_chat_input.max_length = CHAT_MAX_LENGTH
	_chat_input.add_theme_font_size_override("font_size", CHAT_FONT_SIZE)
	_chat_input.custom_minimum_size = Vector2(CHAT_INPUT_WIDTH, 44)
	_chat_input.size = Vector2(CHAT_INPUT_WIDTH, 44)
	_chat_input.visible = false
	add_child(_chat_input)
	_chat_input.text_submitted.connect(_on_chat_submitted)

func _open_chat() -> void:
	# 4.1.1: 입력 진입 시 캐릭터 이동을 멈춘다(LineEdit 포커스로 방향키도 소비됨).
	move_dir = 0
	_left_held = false
	_right_held = false
	_chat_active = true
	# 내 캐릭터 머리 위로 입력창 위치. 화면(1280) 밖으로 안 나가게 clamp.
	var px := my_floor_x * world_width
	var box_w := _chat_input.size.x
	_chat_input.position = Vector2(clampf(px - box_w / 2.0, 0.0, world_width - box_w), 120.0)
	_chat_input.text = ""
	_chat_input.visible = true
	_chat_input.grab_focus()

func _close_chat() -> void:
	# 4.1.1: 입력 UI를 닫고 포커스를 게임 화면으로 되돌린다.
	_chat_active = false
	_chat_input.visible = false
	_chat_input.release_focus()

func _on_chat_submitted(text: String) -> void:
	# 4.3.1: 빈 문자열은 전송하지 않는다.
	var trimmed := text.strip_edges()
	if trimmed != "":
		_send({ "type": "chat", "text": trimmed })
		# 서버 에코 여부와 무관하게 내 말풍선을 즉시 표시(낙관적).
		_set_bubble(my_player_id, trimmed)
	_close_chat()

func _set_bubble(player_id: String, text: String) -> void:
	# 4.3.1: 새 메시지는 기존 말풍선을 즉시 교체하고 타이머를 리셋한다.
	_chat_bubbles[player_id] = { "text": text, "ttl": CHAT_BUBBLE_TTL }
	queue_redraw()

func _tick_bubbles(delta: float) -> void:
	# 4.3.1: TTL 경과한 말풍선 제거.
	if _chat_bubbles.is_empty():
		return
	var expired := []
	for id in _chat_bubbles:
		_chat_bubbles[id]["ttl"] -= delta
		if _chat_bubbles[id]["ttl"] <= 0.0:
			expired.append(id)
	for id in expired:
		_chat_bubbles.erase(id)
	if not expired.is_empty():
		queue_redraw()

## CL-021: always-on-top 현재 상태 (project.godot window/size/always_on_top=true 기본값과 일치)
var _always_on_top := true

## CL-025: click-through(감상 모드) 현재 상태. 활성 시 창 아래 다른 앱을 클릭할 수 있다.
## 마우스 입력은 통과하지만 키보드 입력은 유지되므로 C키로 다시 해제할 수 있다.
var _click_through := false

## CL-026: 시스템 트레이 아이콘/메뉴. click-through 등으로 창 조작이 어려워도 종료할 수 있는 보조 경로.
var _tray_id := -1
var _tray_menu := RID()

## CL-031: 말풍선 채팅 (protocol.md chat 타입)
const CHAT_BUBBLE_TTL := 5.0      # 4.3.1: 전송 시점부터 5초 표시
const CHAT_MAX_LENGTH := 100
const CHAT_FONT_SIZE := 22
const CHAT_INPUT_WIDTH := 480.0
var _chat_input: LineEdit
var _chat_active := false
var _chat_bubbles := {}           # playerId -> { "text": String, "ttl": float }

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):  # ESC
		# CL-031: 채팅 입력 중이면 ESC는 취소(전송 안 함), 아니면 기존대로 종료.
		if _chat_active:
			_close_chat()
		else:
			get_tree().quit()
	elif event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		# CL-031: Enter로 채팅 입력 진입 (입력 중 Enter는 LineEdit이 소비해 전송됨)
		if not _chat_active:
			_open_chat()
			# 진입에 쓴 Enter가 방금 포커스 받은 LineEdit으로 새어들어가 두 번 입력되는 것을 막는다.
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		# CL-021: T 키로 always-on-top 토글
		_always_on_top = not _always_on_top
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, _always_on_top)
		print("[CL-021] always-on-top: ", _always_on_top)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		# CL-025: C 키로 click-through(감상 모드) 토글
		_click_through = not _click_through
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, _click_through)
		print("[CL-025] click-through: ", _click_through)
		queue_redraw()
	elif event.is_action_pressed("ui_left"):
		_left_held = true
		_set_dir(-1)
	elif event.is_action_released("ui_left"):
		_left_held = false
		_recompute_dir()
	elif event.is_action_pressed("ui_right"):
		_right_held = true
		_set_dir(1)
	elif event.is_action_released("ui_right"):
		_right_held = false
		_recompute_dir()

func _set_dir(dir: int) -> void:
	move_dir = dir
	facing = "left" if dir < 0 else "right"

func _recompute_dir() -> void:
	# 키업 후 아직 눌린 키 기준으로 방향 재계산. 둘 다 떼면 정지.
	if _right_held:
		_set_dir(1)
	elif _left_held:
		_set_dir(-1)
	else:
		move_dir = 0

func _process(delta: float) -> void:
	_poll_ws()
	_tick_reconnect(delta)
	_tick_bubbles(delta)

	# delta 기반 이동으로 FPS와 무관하게 일정 속도.
	if move_dir != 0:
		my_floor_x += move_dir * (MOVE_SPEED / world_width) * delta
		my_floor_x = clampf(my_floor_x, 0.0, 1.0)
		queue_redraw()

	_send_move(delta)

func _send_move(delta: float) -> void:
	# 20Hz 주기로 체크하고, 직전 전송값과 달라졌을 때만 move 전송.
	_send_accum += delta
	if not _joined or _send_accum < MOVE_SEND_INTERVAL:
		return
	_send_accum = 0.0
	if my_floor_x != _last_sent_floor_x or facing != _last_sent_facing:
		_send({ "type": "move", "floorX": my_floor_x, "facing": facing })
		_last_sent_floor_x = my_floor_x
		_last_sent_facing = facing

func _tick_reconnect(delta: float) -> void:
	# CL-023: 끊긴 상태에서 RECONNECT_DELAY 경과 시 재연결 시도. 성공하면 STATE_OPEN에서 join 재전송.
	if not _reconnecting:
		return
	_reconnect_accum += delta
	if _reconnect_accum < RECONNECT_DELAY:
		return
	_reconnect_accum = 0.0
	_reconnecting = false
	_joined = false  # 재연결 후 join을 다시 보내도록 초기화
	print("[CL-023] 재연결 시도: ", WS_URL)
	var err := _ws.connect_to_url(WS_URL)
	if err != OK:
		# 시도 자체가 실패하면 다시 대기 후 재시도.
		push_error("[WS] 재연결 시도 실패: %s" % error_string(err))
		_reconnecting = true

func _poll_ws() -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	if state != _ws_state:
		match state:
			WebSocketPeer.STATE_OPEN:
				print("[WS] 연결 성공: ", WS_URL)
			WebSocketPeer.STATE_CLOSED:
				print("[WS] 연결 종료/실패")
				# CL-023: 끊김 감지 시 자동 재연결 대기 시작.
				_reconnecting = true
				_reconnect_accum = 0.0
		_ws_state = state
		queue_redraw()  # CL-020: 연결 상태 텍스트 갱신

	if state == WebSocketPeer.STATE_OPEN:
		if not _joined:
			# STATE_OPEN 첫 프레임에 한 번만 전송 (protocol.md: 첫 메시지는 반드시 join)
			# CL-022: 메뉴에서 입력한 room/nickname 사용.
			_send({ "type": "join", "roomId": Session.room_id, "name": Session.nickname })
			_joined = true
		while _ws.get_available_packet_count() > 0:
			var msg = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
			if msg != null:
				_handle(msg)

func _send(data: Dictionary) -> void:
	_ws.send_text(JSON.stringify(data))

func _handle(msg: Dictionary) -> void:
	match msg.get("type"):
		"welcome":
			my_player_id = msg["playerId"]
			world_width = msg["world"]["width"]
			floor_y = msg["world"]["floorY"]
			print("[WS] welcome: playerId=%s world.width=%s floorY=%s" % [my_player_id, world_width, floor_y])
			queue_redraw()
		"state":
			# players 전체 스냅샷으로 원격 캐릭터 재구성. 내 캐릭터는 로컬 입력이 권위라 제외.
			remote_players.clear()
			for p in msg["players"]:
				if p["id"] == my_player_id:
					continue
				remote_players[p["id"]] = { "floor_x": p["floorX"], "facing": p["facing"] }
			queue_redraw()
		"chat":
			# protocol.md: 수신 chat은 playerId/name/text. 말풍선은 text만 사용.
			_set_bubble(msg["playerId"], msg["text"])
		"player_left":
			remote_players.erase(msg["playerId"])
			_chat_bubbles.erase(msg["playerId"])
			queue_redraw()
		"error":
			# CL-022: ROOM_FULL 등 서버 error 수신 시 메시지를 들고 메뉴로 복귀.
			var code: String = msg.get("code", "ERROR")
			var detail: String = msg.get("message", "")
			Session.last_error = "%s: %s" % [code, detail] if detail != "" else code
			print("[WS] error: ", Session.last_error)
			get_tree().change_scene_to_file("res://menu.tscn")

func _draw() -> void:
	# floorY 아래쪽을 바닥 영역으로 채운다. 윗변(y=floor_y)이 캐릭터가 서는 기준선.
	draw_rect(Rect2(0, floor_y, world_width, 240.0 - floor_y), Color(0.36, 0.27, 0.18))

	_draw_connection_status()

	# 원격 캐릭터(친구)
	for id in remote_players:
		_draw_character(remote_players[id]["floor_x"], PLAYER_COLORS[id])

	# 내 캐릭터
	_draw_character(my_floor_x, PLAYER_COLORS[my_player_id])

	# CL-031: 말풍선 (캐릭터 위)
	_draw_bubbles()

func _draw_connection_status() -> void:
	# CL-020: 현재 WebSocket 연결 상태를 좌상단에 표시. latency는 서버 heartbeat 준비 후(보류).
	var label := ""
	var color := Color.WHITE
	match _ws_state:
		WebSocketPeer.STATE_OPEN:
			label = "연결됨"
			color = Color(0.3, 0.85, 0.3)
		WebSocketPeer.STATE_CONNECTING:
			label = "연결 중…"
			color = Color(0.95, 0.85, 0.2)
		WebSocketPeer.STATE_CLOSING:
			label = "종료 중…"
			color = Color(0.95, 0.85, 0.2)
		_:
			label = "끊김"
			color = Color(0.9, 0.3, 0.3)
	draw_string(ThemeDB.fallback_font, Vector2(10, 28), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, color)

	# CL-025: 감상 모드(click-through) 활성 시 안내 표시. C키로 해제 가능함을 함께 알린다.
	if _click_through:
		draw_string(ThemeDB.fallback_font, Vector2(10, 52), "감상 모드 (C키 해제)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 0.8, 1.0))

func _draw_character(floor_x: float, color: Color) -> void:
	# 밑변이 바닥선(floor_y)에 닿도록 도형을 세운다.
	var px := floor_x * world_width
	draw_rect(Rect2(px - CHAR_WIDTH / 2.0, floor_y - CHAR_HEIGHT, CHAR_WIDTH, CHAR_HEIGHT), color)

func _draw_bubbles() -> void:
	# CL-031: 말풍선이 있는 플레이어의 현재 위치 위에 그린다.
	for id in _chat_bubbles:
		var fx: float
		if id == my_player_id:
			fx = my_floor_x
		elif remote_players.has(id):
			fx = remote_players[id]["floor_x"]
		else:
			continue  # 이미 퇴장한 플레이어 등은 건너뛴다.
		_draw_bubble(fx, _chat_bubbles[id]["text"])

func _draw_bubble(floor_x: float, text: String) -> void:
	var font := ThemeDB.fallback_font
	var fs := CHAT_FONT_SIZE
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pad := Vector2(14, 9)
	var box_w := ts.x + pad.x * 2.0
	var box_h := ts.y + pad.y * 2.0
	var px := floor_x * world_width
	# 캐릭터 머리 위. 화면(world_width) 밖으로 안 나가게 x를 clamp.
	var box_x := clampf(px - box_w / 2.0, 0.0, world_width - box_w)
	var box_y := floor_y - CHAR_HEIGHT - box_h - 8.0
	draw_rect(Rect2(box_x, box_y, box_w, box_h), Color(1, 1, 1, 0.92), true)
	draw_rect(Rect2(box_x, box_y, box_w, box_h), Color(0.2, 0.2, 0.2, 0.9), false, 1.0)
	draw_string(font, Vector2(box_x + pad.x, box_y + pad.y + font.get_ascent(fs)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
