extends Node
## 오토로드 `Preloader` (#501). 게임 중에 처음 읽으면 멈칫하는 **그림과 곡**을 타이틀이 뜨자마자
## 뒤쪽 스레드에서 미리 읽어 끝까지 들고 있는다.
##
## ## 왜
##
## 판이 넘어가는 순간마다 메인 스레드가 디스크를 읽었다 — 무기 카드가 뜨는 프레임에 맵 배경·카드
## 그림·전투 곡을, 카운트다운 첫 프레임에 고른 무기의 그림과 젤리 포즈를. PC 에서 한 프레임에
## 300ms·100ms 가 몰렸고 폰은 그 몇 배라 눈에 보이게 멈췄다.
##
## ## 어떻게
##
## `ResourceLoader.load_threaded_request()` 로 읽기를 걸어 두면 일꾼 스레드가 읽는다. 다 읽힌
## 것은 `_held` 에 넣어 **놓지 않는다** — 아무도 들고 있지 않은 리소스는 캐시에서 빠져 다음
## `load()` 가 디스크를 다시 읽는다(젤리 포즈 그림이 그랬다: 포즈가 바뀔 때마다 새로 읽었다).
## 들고 있으면 게임 곳곳의 `load()` 는 **고치지 않아도** 캐시에서 바로 나온다. 아직 읽는 중인
## 것을 `load()` 하면 그 읽기가 끝나기를 기다릴 뿐 두 번 읽지 않는다.
##
## ## 씬은 미리 읽지 않는다
##
## **스크립트가 든 것(`.tscn`)을 일꾼 스레드에 걸면 안 된다.** 해 봤더니 `main.gd` 의 `preload()`
## 가 같은 씬을 동시에 읽는 다른 스레드와 부딪혀 `Could not preload resource file` 로 컴파일이
## 깨졌다. 그림·소리는 스크립트가 없는 끝 리소스라 안전하다. 씬이 무거웠던 것은 대부분 그 안의
## 그림 때문이라, 그림을 들고 있으면 씬 읽기도 같이 가벼워진다.
##
## 들고 있는 양: 무기 23장(512px)·젤리 15장(768px)·맵 배경 7장·전투 곡 3곡. 경기 중 언제든 나올
## 수 있는 것들이라 놓을 때가 없다.

const MAP_ART_DIR := "res://assets/maps/"

## 경로 → 다 읽은 리소스. 들고 있는 것이 목적이다.
var _held := {}
## 아직 읽는 중인 경로.
var _pending: Array[String] = []


func _ready() -> void:
	for path in _paths():
		if path in _pending or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending.append(path)
	set_process(not _pending.is_empty())


func _process(_delta: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		var path := _pending[i]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_held[path] = ResourceLoader.load_threaded_get(path)
		_pending.remove_at(i)
	if _pending.is_empty():
		set_process(false)


## 게임을 끌 때는 놓는다 — 들고 있는 채로 나가면 "resources still in use at exit" 가 찍힌다
## (`music.gd` 의 `_exit_tree()` 와 같은 이유). 읽는 중인 것은 끝까지 받아서 버린다.
func _exit_tree() -> void:
	for path in _pending:
		ResourceLoader.load_threaded_get(path)
	_pending.clear()
	_held.clear()


## 씬 하나를 뒤에서 읽기 시작한다. **선택 창이 전투 화면(`main.tscn`)에만 쓴다.**
##
## 위 "씬은 미리 읽지 않는다"의 예외다. 전투 화면은 큰 스크립트(`main.gd`·`player.gd` …)를
## 컴파일하느라 그림을 빼고도 PC 에서 570ms 가 걸려 `시작` 을 누른 순간 화면이 굳었다.
## 깨졌던 것은 **씬 여럿을 한꺼번에** 걸어 같은 하위 씬을 두 스레드가 동시에 읽은 경우였다 —
## 선택 창이 다 뜬 뒤에 이것 **하나만** 걸면 겹쳐 읽을 씬이 없다. 다 읽기 전에 `시작` 을
## 누르면 `change_scene_to_file()` 의 `load()` 가 이 읽기를 기다린다(두 번 읽지 않는다).
func request_scene(path: String) -> void:
	if _held.has(path) or path in _pending or not ResourceLoader.exists(path):
		return
	if ResourceLoader.load_threaded_request(path) == OK:
		_pending.append(path)
		set_process(true)


## 다 읽었는가. 측정·확인용.
func is_done() -> bool:
	return _pending.is_empty()


func _paths() -> Array[String]:
	var out: Array[String] = []
	# 무기 표에서 이름이 `file` 로 끝나는 칸 전부 — 손에 든 그림·선택창·강화·탄
	# (`Weapons.all_textures()` 와 같은 기준이다).
	for weapon: Dictionary in Weapons.LIST:
		for key: String in weapon:
			if key.ends_with("file") and weapon[key] is String and weapon[key] != "":
				var file: String = weapon[key]
				out.append(Weapons.ART_DIR + file)
	for character: Dictionary in Characters.LIST:
		for key: String in ["file", "win_file", "lose_file"]:
			var file: String = character.get(key, "")
			if file != "":
				out.append(Characters.DIR + file)
	# 맵 배경 그림. 내보낸 빌드에서는 원본 PNG 가 없으므로 `DirAccess` 가 아니라
	# `ResourceLoader.list_directory()` 로 훑는다(가져온 리소스 이름을 돌려준다).
	for file in ResourceLoader.list_directory(MAP_ART_DIR):
		if file.get_extension() == "png":
			out.append(MAP_ART_DIR + file)
	for track: String in Music.TRACKS:
		out.append(Music.DIR + track + ".ogg")
	return out
