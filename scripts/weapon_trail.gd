class_name WeaponTrail
extends Node2D
## 무기 날이 지나간 자리에 남는 미세한 잔상 (광선검, #253).
##
## **왜 Player의 `_draw()`가 아니라 별도 노드인가**: 씬 루트(`player.tscn`)에는 관통
## 빛무리용 가산 혼합이 걸려 있어서 거기서 그리면 잔상이 빛이 된다. 가산은 밝게만 만들 수
## 있어서 평지 하늘(0.82, 0.93, 0.99)처럼 밝은 배경 위에서는 아무것도 안 보인다(#112·#146).
## 밝은 맵에서도 어두운 맵에서도 보이려면 배경을 **덮는** 보통 알파로 그려야 하고, 그러려면
## 혼합이 걸리지 않은 자식이어야 한다 — 연기(`weapon_smoke.gd`)와 같은 이유다.
##
## 노드 순서상 `WeaponSprite` **앞**에 있어서 잔상이 날 밑에 깔린다. 위에 그리면 지금 든
## 날이 옛 자리에 가려서 어느 것이 지금인지 읽히지 않는다.
##
## **`z_index`를 내려서 뒤로 보내지 않는다** — z를 내리면 맵이 z 0에 깔아 둔 불투명
## 배경보다 먼저 그려져 통째로 사라진다(#146). 형제 순서로만 정한다.
##
## 켜고 끄는 것·날 자리·잔상 수는 부모(`Player._update_weapon_trail()`)가 정한다.
## 여기는 모아 두고 그리는 일만 한다.
##
## 잔상은 **전역 좌표로** 들고 있다가 그릴 때 지역 좌표로 되돌린다. 이 노드는 젤리에
## 붙어 함께 움직이므로, 지역 좌표로 들고 있으면 잔상이 젤리를 따라와서 지나간 자리에
## 남지 않는다.
##
## 복제할 것이 없다 — 자리는 이미 복제되는 `position`·`facing`에서 나오므로 각 피어가
## 자기 화면 값으로 알아서 그린다(젤리 찌그러짐·연기와 같은 방식).

## 한 번에 남아 있을 수 있는 잔상 수의 상한. `ghost_count`가 이 값을 넘길 수 없다.
const MAX_GHOSTS := 12
## 잔상 하나가 남아 있는 시간(초). 이보다 길게 두면 멈춰 선 뒤에도 옛 자리가 남아
## "지금 어디 있나"가 흐려진다.
const LIFETIME := 0.18
## 새 잔상을 남기기까지 날이 움직여야 하는 거리(px). 서 있으면 하나도 안 남는다 —
## 잔상은 "움직였다"는 표시이므로 가만히 있는 동안 쌓이면 뜻이 뒤집힌다.
const MIN_STEP := 7.0
## 이보다 멀리 튀면 순간이동으로 보고 들고 있던 것을 버린다(px). 빨간 표창의 위치
## 교환이 그렇다 — 안 버리면 맵을 가로지르는 줄이 한 번 그려진다.
const MAX_STEP := 220.0
## 가장 진한 잔상의 옅기. **"미세한"이 요점이다** — 진하게 남으면 잔상이 무기처럼 보인다.
const ALPHA := 0.3
## 가장 진한 잔상의 굵기(px). 날(광선검은 화면에서 약 12 x 56px)보다 가늘게 잡는다.
const WIDTH := 5.0

## 부모가 넣어 준다. 기본값은 광선검 날의 민트빛이다 — 날과 다른 색이면 무엇의
## 잔상인지 안 읽힌다.
var color := Color(0.55, 0.95, 0.85)
## 한 번에 남아 있는 잔상 수 (무기 표의 `trail_ghosts`). 늘리면 꼬리가 길어진다.
## `MAX_GHOSTS`를 넘길 수 없다.
var ghost_count := 5

## 남아 있는 잔상. 오래된 것이 앞이다. 각 항목은 날의 양끝(전역 좌표)과 나이(초)다.
var _ghosts: Array[Dictionary] = []


## 지금 날 자리를 잔상으로 남긴다 (전역 좌표). 부모가 매 물리 프레임 부른다.
##
## 움직인 거리를 보고 **남길지 말지 여기서** 정한다 — 부모가 정하면 문턱값이 두 곳으로
## 갈라진다. 문턱을 넘지 않았으면 아무것도 하지 않고, 들고 있던 것은 나이만 먹는다.
func sample(tip: Vector2, hilt: Vector2) -> void:
	if not _ghosts.is_empty():
		# 딕셔너리에서 꺼낸 값은 Variant다 — `:=`로 받으면 타입 추론이 실패한다.
		var last: Dictionary = _ghosts[-1]
		var last_tip: Vector2 = last["tip"]
		var moved := tip.distance_to(last_tip)
		if moved > MAX_STEP:
			# 순간이동 — 옛 자리와 새 자리를 잇는 줄이 되므로 통째로 버린다.
			_ghosts.clear()
		elif moved < MIN_STEP:
			return
	_ghosts.append({"tip": tip, "hilt": hilt, "age": 0.0})
	# 상한을 넘으면 가장 오래된 것부터 지운다.
	while _ghosts.size() > clampi(ghost_count, 0, MAX_GHOSTS):
		_ghosts.remove_at(0)


## 들고 있는 잔상을 통째로 버린다. 순간이동·라운드 초기화·무기 교체에서 부모가 부른다.
func clear() -> void:
	if _ghosts.is_empty():
		return
	_ghosts.clear()
	queue_redraw()


## 나이를 먹이고 다 된 것을 지운다.
##
## 숨어 있으면 시간도 멈춘다 — 어차피 부모가 숨기기 전에 `clear()`로 비운다.
## 젤리가 움직이면 같은 잔상도 화면에서는 자리가 달라지므로(전역 좌표를 지역으로
## 되돌려 그린다) 남아 있는 동안에는 매 프레임 다시 그린다.
func _process(delta: float) -> void:
	if not visible or _ghosts.is_empty():
		return
	var kept: Array[Dictionary] = []
	for ghost in _ghosts:
		ghost["age"] = float(ghost["age"]) + delta
		if float(ghost["age"]) < LIFETIME:
			kept.append(ghost)
	_ghosts = kept
	queue_redraw()


func _draw() -> void:
	for ghost in _ghosts:
		# 오래된 것일수록 옅고 가늘다. 이것이 없으면 잔상 다섯 개가 아니라
		# 날이 다섯 개인 것으로 보인다.
		var fade := 1.0 - float(ghost["age"]) / LIFETIME
		var stored_tip: Vector2 = ghost["tip"]
		var stored_hilt: Vector2 = ghost["hilt"]
		var tip := to_local(stored_tip)
		var hilt := to_local(stored_hilt)
		# 옅고 넓은 것 위에 진한 심을 겹쳐 빛나는 날의 잔상으로 읽히게 한다
		# (연기가 덩어리져 보이게 하는 것과 같은 방식).
		draw_line(hilt, tip, Color(color, ALPHA * fade * 0.4), WIDTH * 1.8 * fade, true)
		draw_line(hilt, tip, Color(color, ALPHA * fade), WIDTH * fade, true)
