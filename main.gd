extends Node2D

## 월드 기준값 (protocol.md: world.width=1280, world.floorY=220)
const WORLD_WIDTH := 1280.0
const FLOOR_Y := 220.0

## 캐릭터 도형 크기
const CHAR_WIDTH := 24.0
const CHAR_HEIGHT := 40.0

## 내 캐릭터 (서버 연결 전 고정값). floor_x는 0.0~1.0 비율.
var my_floor_x := 0.5
const MY_COLOR := Color(0.2, 0.4, 0.9)  # p1 = 파랑

## 이동 속도 (픽셀/초). floorX는 비율이라 WORLD_WIDTH로 나눠 비율 증분으로 변환.
const MOVE_SPEED := 220.0

## 입력 상태 (실제 이동 적용은 CL-006)
var _left_held := false
var _right_held := false
var move_dir := 0          # -1=왼, 0=정지, +1=오른
var facing := "right"      # protocol.md move의 facing 필드

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
	# delta 기반 이동으로 FPS와 무관하게 일정 속도.
	if move_dir != 0:
		my_floor_x += move_dir * (MOVE_SPEED / WORLD_WIDTH) * delta
		my_floor_x = clampf(my_floor_x, 0.0, 1.0)
		queue_redraw()

func _draw() -> void:
	# floorY 아래쪽을 바닥 영역으로 채운다. 윗변(y=FLOOR_Y)이 캐릭터가 서는 기준선.
	draw_rect(Rect2(0, FLOOR_Y, WORLD_WIDTH, 240.0 - FLOOR_Y), Color(0.36, 0.27, 0.18))

	# 내 캐릭터: 밑변이 바닥선(FLOOR_Y)에 닿도록 세운다.
	var px := my_floor_x * WORLD_WIDTH
	draw_rect(Rect2(px - CHAR_WIDTH / 2.0, FLOOR_Y - CHAR_HEIGHT, CHAR_WIDTH, CHAR_HEIGHT), MY_COLOR)
