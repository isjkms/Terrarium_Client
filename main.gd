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

func _draw() -> void:
	# floorY 아래쪽을 바닥 영역으로 채운다. 윗변(y=FLOOR_Y)이 캐릭터가 서는 기준선.
	draw_rect(Rect2(0, FLOOR_Y, WORLD_WIDTH, 240.0 - FLOOR_Y), Color(0.36, 0.27, 0.18))

	# 내 캐릭터: 밑변이 바닥선(FLOOR_Y)에 닿도록 세운다.
	var px := my_floor_x * WORLD_WIDTH
	draw_rect(Rect2(px - CHAR_WIDTH / 2.0, FLOOR_Y - CHAR_HEIGHT, CHAR_WIDTH, CHAR_HEIGHT), MY_COLOR)
