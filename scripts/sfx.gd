extends Node
## 효과음 (오토로드 싱글턴 Sfx, 이슈 #373).
##
## **무기 소리만 난다** (#379, 사용자 요청) — 젤리 몸(걸음·점프·피격·사망 …), 판 진행·화면
## (카운트다운·포인트·승리·카드·버튼), 무기끼리 부딪침 소리는 들어 본 뒤 뺐다. 되살리려면
## #373~#376 이력의 `tools/gen_sfx.py` 와 호출부를 본다.
## 예외로 경기의 큰 마디 넷은 사용자 요청으로 다시 붙였다(#400, 예전 소리가 아니라 새로 만든 것):
## `match_start`(경기 표지, `main._play_match_intro`) · `weapon_pick`(카드를 고른 기기,
## `WeaponPick._on_card_pressed`) · `victory`/`defeat`(결과 화면, `main._show_match_result` —
## 온라인에서 진 기기만 `defeat`, 오프라인 한 화면은 늘 `victory`). 모두 `play()` 다.
##
## 소리는 `assets/sfx/<이름>.wav` 이고 `tools/gen_sfx.py` 가 합성해서 만든다 — 소리를
## 고치려면 그 스크립트의 숫자를 바꿔 다시 돌린다. 파일이 없는 이름은 **조용히** 넘어간다
## (무기 그림이 없을 때 막대로 대신하는 것과 같은 태도다 — 소리 하나 빠졌다고 게임이 멈추지
## 않는다).
##
## **부르는 길이 둘이다.**
##   `play()` — 이 기기에서만 낸다. 모든 기기에서 도는 자리(`_receive_*`·`_play_*` RPC)에서
##              부른다. 온라인 서버는 아무것도 내지 않는다.
##   `cue()`  — **판정하는 쪽에서만 도는 자리**(`main.gd` 의 판정, `Projectile._on_body_entered`)에서 부른다. 오프라인이면 그 자리에서 내고,
##              온라인 서버면 전투 화면을 연 피어(`Lobby.viewers`)에게 보낸다 — 대기실 피어에게
##              보내지 않는 것은 `Player._send_state()` 와 같은 이유다. 클라이언트에서는 무시한다.
## 같은 자리에서 둘을 섞어 부르면 온라인 클라이언트에서 두 번 들린다 — 그 자리가 어느
## 기기에서 도는지 먼저 본다.

## 소리가 실제로 났다 (검증용 — 사람 손 없는 경기에서 무엇이 났는지 센다).
signal played(sound: String)

const DIR := "res://assets/sfx/"
## 동시에 낼 수 있는 소리 수. 넘치면 가장 오래 전에 시작한 것을 끊는다.
const VOICES := 20
## 같은 소리가 이 간격 안에 또 오면 버린다 — 지속 데미지(0.2초 틱)·연사가 겹쳐
## 한 소리가 쌓여 커지는 것을 막는다.
const MIN_GAP := 0.045
## 같은 소리를 되풀이해도 기계음처럼 안 들리게 음높이를 조금씩 흔든다.
const PITCH_JITTER := 0.06
## 모든 효과음에 더하는 일괄 음량(dB, 이슈 #391·#394 — 사용자 요청으로 -4 → -8 로 낮췄다). 호출부가 정한
## 소리 사이의 상대 음량(지속 데미지 틱 -9dB 등)은 그대로 두고 전체만 내린다.
const MASTER_DB := -8.0

## 무기 이름 → 소리 이름 앞부분. `<키>_hit`(근접 타격)·`<키>_fire`(발사)·`<키>_special`
## (특수 발동)이 붙는다. 무기 표(`Weapons.LIST`)에 칸을 늘리지 않고 여기 두는 것은
## 소리가 무기 동작과 따로 고쳐지기 때문이다 — 무기를 더하면 여기 한 줄과
## `tools/gen_sfx.py` 의 소리를 더한다. 표에 없는 무기는 소리 없이 지나간다.
const WEAPON_KEYS := {
	"검": "sword",
	"단검": "dagger",
	"광선검": "saber",
	"전기톱": "chainsaw",
	"망치": "hammer",
	"대포 총": "cannon",
	"폭탄": "bomb",
	"활": "bow",
	"삼지창": "trident",
	"글러브": "glove",
	"표창": "shuriken",
	"너클": "knuckle",
	"양날 도끼": "axe",
	"샷건": "shotgun",
	"장대": "pole",
	"소총": "rifle",
	"방패": "shield",
}

## 길게 눌렀을 때 특수가 다른 기술이 되는 무기 (방패: 짧게 던지기 · 길게 크기 증가).
const LONG_PRESS_SPECIALS := {
	"방패": "shield_grow",
}

var _streams := {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _last_played := {}


func _ready() -> void:
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	# 처음 나는 순간 디스크를 읽지 않게 미리 올려 둔다. `list_directory()` 는 내보낸
	# 빌드에서도 원래 이름(`.wav`)을 돌려준다 — `DirAccess` 는 `.import` 를 보여준다.
	if not Network.is_server():
		for file in ResourceLoader.list_directory(DIR):
			if file.get_extension() == "wav":
				_stream(file.get_basename())


## 이 기기에서 소리를 낸다. `vary` 가 거짓이면 음높이를 흔들지 않는다 (음계가 있는 소리).
func play(sound: String, volume_db := 0.0, vary := true) -> void:
	if sound.is_empty() or Network.is_server():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sound, -1.0)) < MIN_GAP:
		return
	var stream := _stream(sound)
	if stream == null:
		return
	_last_played[sound] = now
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.volume_db = volume_db + MASTER_DB
	voice.pitch_scale = randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER) if vary else 1.0
	voice.play()
	played.emit(sound)


## 판정하는 쪽이 낸 소리를 전투 화면에 있는 모든 기기에 낸다.
func cue(sound: String, volume_db := 0.0) -> void:
	if sound.is_empty() or not Network.has_authority():
		return
	if Network.is_server():
		for peer in Lobby.viewers:
			_receive_cue.rpc_id(peer, sound, volume_db)
		return
	play(sound, volume_db)


## 소리 이름은 RPC 로 짧은 문자열 하나다. 놓쳐도 다음 소리가 오므로 unreliable 이다.
@rpc("authority", "call_remote", "unreliable")
func _receive_cue(sound: String, volume_db: float) -> void:
	play(sound, volume_db)


## 무기의 소리 이름 (`kind`: "hit"·"fire"·"special"). 표에 없는 무기면 빈 문자열이다.
func weapon_sound(weapon_name: String, kind: String) -> String:
	var key: String = WEAPON_KEYS.get(weapon_name, "")
	if key.is_empty():
		return ""
	return "%s_%s" % [key, kind]


## 특수 발동음. 길게 누른 것이 다른 기술인 무기는 그쪽 소리를 준다.
func special_sound(weapon_name: String, long_press: bool) -> String:
	if long_press and LONG_PRESS_SPECIALS.has(weapon_name):
		return LONG_PRESS_SPECIALS[weapon_name]
	return weapon_sound(weapon_name, "special")


func _stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var path := DIR + sound + ".wav"
	var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_streams[sound] = stream
	return stream
