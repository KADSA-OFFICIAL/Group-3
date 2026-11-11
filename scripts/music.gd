extends Node
## 배경음 (오토로드 싱글턴 Music, 이슈 #454).
##
## **전투 화면** — `main.gd` 가 무기 선택을 열 때마다 `start()`, 화면을 떠날 때 `stop()` 을
## 부른다. **타이틀·선택 창**은 `start_menu()` 가 메뉴 곡(`MENU_TRACK`)을 반복해 튼다(#457) —
## 두 화면이 각자 `_ready()` 에서 부르고, 이미 도는 중이면 이어서 둔다(title → select 에서
## 끊기지 않는다). 전투 화면이 열리면 `main._ready()` 가 `stop()` 으로 끊는다.
##
## **곡은 무기 선택이 열릴 때마다 무작위로 바뀐다**(#463, 요청) — `TRACKS` 중 방금 틀던 곡을
## 뺀 나머지에서 고르므로 같은 곡이 두 번 연달아 나오지 않는다. 라운드 도중 곡이 끝나도
## 같은 규칙으로 넘어간다. 파일마다 반복(loop)을 켜지 않는 이유가 이것이다: 켜면
## `finished` 가 오지 않아 다음 곡으로 넘어가지 못한다.
##
## **무기 선택·포인트 획득 동안은 낮춘다**(`set_ducked()`) — 카드 설명을 읽고 점수를
## 확인하는 장면이라 음악이 앞에 나서면 안 된다. 툭 끊기지 않게 `FADE_TIME` 동안 옮긴다.
##
## 효과음(`Sfx`)과 달리 **게임 멈춤을 따른다**(일시정지 창 동안 같이 멈췄다가 이어진다) —
## 오토로드는 기본이 `PROCESS_MODE_INHERIT` 라 따로 할 일이 없다.

const DIR := "res://assets/music/"
## 전투 곡들. 여기서 무작위로 고른다 (#463 — 순서는 뜻이 없다).
const TRACKS := ["combat_loop", "arcade_battle", "face_off_groove"]
## 평소 음량(dB). 효과음(`Sfx.MASTER_DB` -8dB)보다 아래에 깔리게 둔다 — 세 곡 다 평균
## -17~-18dB 로 꽉 차게 녹음되어 있어 그대로 두면 무기 소리를 덮는다.
const NORMAL_DB := -12.0
## 무기 선택·포인트 획득 동안의 음량(dB).
const DUCKED_DB := -24.0
## 음량을 옮기는 데 걸리는 시간(초).
const FADE_TIME := 0.4

## 타이틀·선택 창 곡 (#457). **이것만 파일의 `loop` 를 켰다**(`.import`) — 한 곡을
## 끝없이 되풀이하므로 `finished` 로 다시 트는 것보다 이음매 없이 이어진다.
const MENU_TRACK := "menu"
## 메뉴 곡 음량(dB). 이 곡은 평균 -13dB 로 전투 곡보다 4~5dB 크게 녹음되어 있어
## 같은 `NORMAL_DB` 로 두면 화면을 넘어갈 때 음악만 갑자기 커진 것처럼 들린다.
const MENU_DB := -16.0

var _player: AudioStreamPlayer
## 지금(또는 마지막으로) 튼 전투 곡의 자리. -1 이면 아직 아무것도 안 틀었다.
## **`stop()` 이 지우지 않는다** — 경기를 나갔다 다시 들어와도 직전 경기의 마지막 곡이
## 새 경기의 첫 곡으로 연달아 나오지 않게 한다.
var _track := -1
## 지금 메뉴 곡을 트는 중인가. 전투 곡과 한 플레이어를 나눠 쓴다.
var _menu := false
var _ducked := false
var _fade: Tween


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_next_track)


## 게임을 끄는 순간에도 곡을 놓는다 — 전투 화면에서 바로 끄면 `main` 의 `stop()` 보다
## 이쪽이 먼저 사라져 "resources still in use at exit" 가 찍힌다.
func _exit_tree() -> void:
	stop()


## 방금 곡을 뺀 무작위 전투 곡을 처음부터 튼다 (#463). 무기 선택이 열릴 때마다 부른다.
##
## **낮춤 상태는 건드리지 않는다** — `main` 이 먼저 `set_ducked(true)` 를 걸고 부르면
## 곡이 처음부터 낮은 음량으로 나온다. 여기서 지우면 큰 소리로 시작했다가 줄어든다.
func start() -> void:
	_menu = false
	_track = _random_track()
	_play_track()


## 메뉴 곡을 반복해 튼다 (#457). 이미 메뉴 곡이 도는 중이면 그대로 둔다 — 타이틀에서
## 선택 창으로 넘어갈 때 곡이 처음으로 돌아가지 않는다.
func start_menu() -> void:
	if _player.playing and _menu:
		return
	stop()
	var path: String = DIR + MENU_TRACK + ".ogg"
	if not ResourceLoader.exists(path):
		return
	_menu = true
	_player.stream = load(path)
	_player.volume_db = MENU_DB
	_player.play()


func stop() -> void:
	_kill_fade()
	_player.stop()
	_player.stream = null
	_menu = false
	# 다음 경기는 평소 음량에서 시작한다 — 남겨 두면 결과 화면 전에 나간 경기의 낮춘
	# 상태가 다음 경기의 첫 전투까지 이어진다.
	_ducked = false


## 낮춘다(`true`) / 되돌린다(`false`). 같은 값이 거듭 와도 페이드를 새로 걸지 않는다.
func set_ducked(value: bool) -> void:
	if value == _ducked:
		return
	_ducked = value
	# 메뉴 곡은 낮추지 않는다 — 값만 적어 두고 다음 전투 곡이 그 값으로 시작한다.
	if _menu:
		return
	if not _player.playing:
		_player.volume_db = _target_db()
		return
	_kill_fade()
	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", _target_db(), FADE_TIME)


func is_playing() -> bool:
	return _player.playing


## 지금 트는 곡 이름 (검증용). 안 틀고 있으면 빈 문자열.
func current_track() -> String:
	if not _player.playing:
		return ""
	return MENU_TRACK if _menu else TRACKS[_track]


func is_ducked() -> bool:
	return _ducked


func _next_track() -> void:
	# 메뉴 곡은 파일이 스스로 반복해 여기로 오지 않는다 — 와도 전투 곡으로 넘기지 않는다.
	if _menu:
		_player.play()
		return
	_track = _random_track()
	_play_track()


## 방금 곡(`_track`)을 뺀 나머지 중 하나. 아직 아무것도 안 틀었으면 전부에서 고른다.
func _random_track() -> int:
	var pool: Array[int] = []
	for i in TRACKS.size():
		if i != _track:
			pool.append(i)
	return pool.pick_random() if not pool.is_empty() else 0


func _play_track() -> void:
	var path: String = DIR + TRACKS[_track] + ".ogg"
	if not ResourceLoader.exists(path):
		return
	_kill_fade()
	_player.stream = load(path)
	_player.volume_db = _target_db()
	_player.play()


func _target_db() -> float:
	return DUCKED_DB if _ducked else NORMAL_DB


func _kill_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
