class_name Characters
extends RefCounted
## 젤리곰 캐릭터 표. 이름과 그림 경로의 유일한 출처.
##
## **캐릭터를 추가·변경하려면 이 LIST만 고친다** — 대기실 선택지(`GameState.CHARACTERS`),
## 서버 검증(`Lobby._sanitize`), 전투 화면 그림(`Player`)이 모두 여기서 나온다.
##
## 필드
##   name   대기실에 보이는 이름이자 네트워크로 오가는 id
##   file   DIR 아래의 그림 파일 이름
##   color  그림 파일이 아직 없을 때 대신 쓰는 색 (원화의 몸통 색에 맞춘 근사값)

const DIR := "res://assets/characters/"

const LIST: Array[Dictionary] = [
	{"name": "분홍", "file": "bear_pink.png", "color": Color(0.96, 0.68, 0.86)},
	{"name": "파랑", "file": "bear_blue.png", "color": Color(0.51, 0.53, 0.85)},
	{"name": "초록", "file": "bear_green.png", "color": Color(0.40, 0.75, 0.40)},
	{"name": "노랑", "file": "bear_yellow.png", "color": Color(0.98, 0.94, 0.63)},
	{"name": "빨강", "file": "bear_red.png", "color": Color(0.88, 0.44, 0.49)},
]


static func names() -> Array[String]:
	var out: Array[String] = []
	for character in LIST:
		out.append(character["name"])
	return out


## 이름으로 캐릭터를 찾는다. 없으면 빈 사전을 돌려준다.
static func get_character(name: String) -> Dictionary:
	for character in LIST:
		if character["name"] == name:
			return character
	return {}


static func has(name: String) -> bool:
	return not get_character(name).is_empty()


## 슬롯 번호로 기본 캐릭터를 고른다 — 1P·2P가 서로 다른 캐릭터로 시작한다.
static func id_at(index: int) -> String:
	return LIST[index % LIST.size()]["name"]


static func default_id() -> String:
	return id_at(0)


## 캐릭터 그림. 파일이 아직 없으면 몸통 색 단색으로 대신한다 —
## 그림을 넣기 전에도 게임이 그대로 돌아가고, 빠진 것이 눈에 보이게 하기 위함이다.
static func texture(name: String) -> Texture2D:
	var character := get_character(name)
	if character.is_empty():
		return null
	var path: String = DIR + character["file"]
	if ResourceLoader.exists(path):
		return load(path)
	return _placeholder(character["color"])


## 그림이 없을 때 쓰는 단색 텍스처. 크기는 플레이어 충돌 상자와 같다.
static func _placeholder(color: Color) -> ImageTexture:
	var image := Image.create_empty(48, 56, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
