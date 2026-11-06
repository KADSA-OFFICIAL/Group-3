shader_type canvas_item;
// 원화 위로 비는 띠를 채운다 (#433 맵, #448·#451 타이틀·경기 표지). 원화 맨 윗줄을 위로 늘리고, 이음선에서 멀어질수록
// 가로로 흐리게 한다 — `cover_side.gdshader`(#357)를 위아래로 돌린 것이다.
//
// 그냥 늘리기만 하면(Sprite2D 의 region 1px) 윗줄에서 색이 갈리는 자리가 세로로 곧은 선이
// 되어, 띠가 두꺼워질수록 붙여 넣은 티가 난다. 이음선(맨 아래)에서는 반경이 0이라 원화와
// 정확히 이어진다.
//
// 이 노드(ColorRect)는 원화와 **같은 폭**이어야 하고(UV.x 가 곧 원화의 u 다), 원화 바로 위에
// 붙인다. 높이는 자유다.

uniform sampler2D art : source_color, filter_linear, repeat_disable;
uniform float art_width = 1152.0;
// 가장 먼 곳(맨 위)에서의 가로 번짐 반경(픽셀, 화면 기준).
uniform float max_blur_px = 220.0;
// 맨 위에서 몇 줄 아래를 읽을지(원화 픽셀 비율). 맨 끝 한 줄은 안티앨리어싱 찌꺼기가 있을 수 있다.
uniform float inset_v = 0.002;
// 번짐을 노드 높이가 아니라 **이음선에서의 픽셀 거리**로 재고 싶을 때 둘 다 넣는다 (#451).
// band_px = 이 노드의 높이, blur_reach_px = 번짐이 max_blur_px 에 닿는 거리. 폴더블·분할 화면을
// 덮으려고 노드를 크게 잡아도 이음선 가까이의 모양은 그대로다. 0이면 예전처럼 노드 맨 위에서 닿는다.
uniform float band_px = 0.0;
uniform float blur_reach_px = 0.0;

const int TAPS = 20;

void fragment() {
	float dist = 1.0 - UV.y; // 0 = 이음선(맨 아래), 1 = 맨 위
	if (band_px > 0.0 && blur_reach_px > 0.0) {
		dist = min(dist * band_px / blur_reach_px, 1.0);
	}
	// 이음선 가까이에서 빨리 퍼지게 한다(제곱근 꼴) — cover_side 와 같은 이유.
	float radius = max_blur_px / art_width * pow(dist, 0.55);
	vec4 sum = vec4(0.0);
	float weight_sum = 0.0;
	for (int i = -TAPS; i <= TAPS; i++) {
		float t = float(i) / float(TAPS);
		float w = exp(-t * t * 2.5);
		float u = clamp(UV.x + t * radius, 0.0, 1.0);
		sum += texture(art, vec2(u, inset_v)) * w;
		weight_sum += w;
	}
	COLOR *= sum / weight_sum;
}
