class_name Session
extends RefCounted

## CL-022: 메뉴에서 입력한 room/nickname을 게임 씬으로 전달하는 공유 상태.
## 동일 창 씬 전환(CL-024) 구조라 인스턴스 없이 static으로 공유한다.
static var room_id := "ROOM01"
static var nickname := "player"

## join 실패 등 서버 error를 메뉴로 되돌릴 때 전달 (CL-022). 메뉴가 표시 후 비운다.
static var last_error := ""
