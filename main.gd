extends Node2D

## 월드 기준값 (protocol.md: world.width=1280, world.floorY=220)
const WORLD_WIDTH := 1280.0
const FLOOR_Y := 220.0

func _draw() -> void:
	# floorY 아래쪽을 바닥 영역으로 채운다. 윗변(y=FLOOR_Y)이 캐릭터가 서는 기준선.
	draw_rect(Rect2(0, FLOOR_Y, WORLD_WIDTH, 240.0 - FLOOR_Y), Color(0.36, 0.27, 0.18))
