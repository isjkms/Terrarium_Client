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

## CL-021: always-on-top 현재 상태 (project.godot window/size/always_on_top=true 기본값과 일치)
var _always_on_top := true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):  # ESC
		get_tree().quit()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		# CL-021: T 키로 always-on-top 토글
		_always_on_top = not _always_on_top
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, _always_on_top)
		print("[CL-021] always-on-top: ", _always_on_top)
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
		"player_left":
			remote_players.erase(msg["playerId"])
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

func _draw_character(floor_x: float, color: Color) -> void:
	# 밑변이 바닥선(floor_y)에 닿도록 도형을 세운다.
	var px := floor_x * world_width
	draw_rect(Rect2(px - CHAR_WIDTH / 2.0, floor_y - CHAR_HEIGHT, CHAR_WIDTH, CHAR_HEIGHT), color)
