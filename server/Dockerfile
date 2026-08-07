# 젤리 워즈 전용 서버.
#
# 프로젝트 파일은 이미지에 굽지 않고 실행할 때 /game 으로 마운트한다.
# 코드를 고쳐도 재빌드 없이 컨테이너만 재시작하면 된다.

FROM debian:bookworm-slim

ARG GODOT_VERSION=4.5.1-stable

# --headless 로 띄워도 Godot 리눅스 바이너리는 X11/GL 공유 라이브러리에
# 동적 링크되어 있어서, 실제로 쓰지 않아도 로드 시점에 파일이 있어야 한다.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
        libx11-6 \
        libxcursor1 \
        libxinerama1 \
        libxi6 \
        libxrandr2 \
        libxext6 \
        libgl1 \
        libglu1-mesa \
        libasound2 \
        libpulse0 \
        libudev1 \
        libdbus-1-3 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/godot.zip \
        "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
    && unzip -j /tmp/godot.zip -d /usr/local/bin \
    && rm /tmp/godot.zip \
    && mv /usr/local/bin/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && godot --version

# Godot 이 홈 디렉터리에 설정을 쓰려고 하므로 쓸 수 있는 곳을 준다.
ENV HOME=/tmp
WORKDIR /

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
