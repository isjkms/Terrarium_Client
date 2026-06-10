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

## 서버 연결 (protocol.md). roomId/name은 P0 고정값 (룸/닉네임 UI는 P1).
const WS_URL := "ws://13.209.96.232:8080/ws"
const ROOM_ID := "ROOM01"
const PLAYER_NAME := "player"
var _ws := WebSocketPeer.new()
var _ws_state := WebSocketPeer.STATE_CLOSED
var _joined := false       # STATE_OPEN 첫 프레임 join 중복 전송 방지

## move 송신 (20Hz throttle + 값 변화 감지)
const MOVE_SEND_INTERVAL := 0.05
var _send_accum := 0.0
var _last_sent_floor_x := -1.0
var _last_sent_facing := ""

func _ready() -> void:
	var err := _ws.connect_to_url(WS_URL)
	if err != OK:
		push_error("[WS] 연결 시도 실패: %s" % error_string(err))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
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

func _poll_ws() -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	if state != _ws_state:
		match state:
			WebSocketPeer.STATE_OPEN:
				print("[WS] 연결 성공: ", WS_URL)
			WebSocketPeer.STATE_CLOSED:
				print("[WS] 연결 종료/실패")
		_ws_state = state

	if state == WebSocketPeer.STATE_OPEN:
		if not _joined:
			# STATE_OPEN 첫 프레임에 한 번만 전송 (protocol.md: 첫 메시지는 반드시 join)
			_send({ "type": "join", "roomId": ROOM_ID, "name": PLAYER_NAME })
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

func _draw() -> void:
	# floorY 아래쪽을 바닥 영역으로 채운다. 윗변(y=floor_y)이 캐릭터가 서는 기준선.
	draw_rect(Rect2(0, floor_y, world_width, 240.0 - floor_y), Color(0.36, 0.27, 0.18))

	# 원격 캐릭터(친구)
	for id in remote_players:
		_draw_character(remote_players[id]["floor_x"], PLAYER_COLORS[id])

	# 내 캐릭터
	_draw_character(my_floor_x, PLAYER_COLORS[my_player_id])

func _draw_character(floor_x: float, color: Color) -> void:
	# 밑변이 바닥선(floor_y)에 닿도록 도형을 세운다.
	var px := floor_x * world_width
	draw_rect(Rect2(px - CHAR_WIDTH / 2.0, floor_y - CHAR_HEIGHT, CHAR_WIDTH, CHAR_HEIGHT), color)
