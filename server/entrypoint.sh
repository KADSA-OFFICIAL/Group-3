#!/bin/sh
# 젤리 워즈 전용 서버 실행.
# JELLY_PORT 는 필수다 — 팀에서 정한 포트 번호가 없으므로 기본값을 두지 않는다.
set -e

if [ -z "$JELLY_PORT" ]; then
	echo "오류: JELLY_PORT 가 설정되지 않았습니다." >&2
	echo "      server/.env 에 JELLY_PORT=<포트번호> 를 적거나," >&2
	echo "      docker run 에 -e JELLY_PORT=<포트번호> 를 넘기세요." >&2
	exit 1
fi

if [ ! -f /src/project.godot ]; then
	echo "오류: /src 에 project.godot 이 없습니다. 프로젝트 폴더를 마운트했는지 확인하세요." >&2
	exit 1
fi

# 호스트 폴더는 읽기 전용으로 두고 컨테이너 안으로 복사해서 쓴다.
# Godot 은 실행할 때 .godot/ 에 임포트 결과를 써야 하는데, 호스트 폴더에
# 직접 쓰면 윈도우 쪽 에디터가 쓰는 캐시와 충돌한다.
# .godot 은 윈도우에서 임포트된 것이라 가져가지 않고 여기서 새로 만든다.
echo "프로젝트 복사 중..."
rm -rf /game
mkdir -p /game
tar -C /src --exclude=./.godot --exclude=./.git -cf - . | tar -C /game -xf -

echo "리소스 임포트 중..."
godot --headless --path /game --import

echo "젤리 워즈 전용 서버 시작 — UDP 포트 ${JELLY_PORT}"
exec godot --headless --path /game -- --server --port="${JELLY_PORT}"
