shader_type canvas_item;
// 표지 원화(1152 폭) 양옆 채움 (#357). 원화 맨 가장자리 픽셀 띠를 옆으로 늘리고, 이음선에서
// 멀어질수록 세로로 흐리게 한다 — 좌우 반전은 해·젤리가 이음선 양쪽에 두 번 나타났다.
//
// 이 노드(ColorRect)는 원화와 **같은 높이**여야 한다(UV.y가 곧 원화의 v다). 이음선에서는 반경이
// 0이라 원화와 정확히 이어진다. COLOR 에 곱해서 내보내므로 부모의 modulate(경기 표지의 옅기
// 연출)가 그대로 먹는다.

uniform sampler2D art : source_color, filter_linear, repeat_disable;
// 오른쪽 띠이면 true. 왼쪽 띠는 UV.x 가 클수록(이음선 쪽) 가까운 쪽이다.
uniform bool right_side = false;
uniform float art_width = 1152.0;
uniform float art_height = 768.0;
// 가장 먼 곳에서의 세로 번짐 반경(픽셀).
uniform float max_blur_px = 190.0;
// 가장자리에서 몇 픽셀 안쪽을 읽을지. 맨 끝 한 줄은 안티앨리어싱 찌꺼기가 있을 수 있다.
uniform float inset_px = 2.0;

const int TAPS = 20;

void fragment() {
	float dist = right_side ? UV.x : 1.0 - UV.x; // 0 = 이음선, 1 = 가장 먼 곳
	float edge_u = right_side ? 1.0 - inset_px / art_width : inset_px / art_width;
	// 이음선 가까이에서 빨리 퍼지게 한다(제곱근 꼴) — 직선으로 퍼지면 가장자리의 선명한 색
	// (성의 주황)이 한참 동안 줄무늬로 남는다.
	float radius = max_blur_px / art_height * pow(dist, 0.55);
	vec4 sum = vec4(0.0);
	float weight_sum = 0.0;
	for (int i = -TAPS; i <= TAPS; i++) {
		float t = float(i) / float(TAPS);
		float w = exp(-t * t * 2.5);
		float v = clamp(UV.y + t * radius, 0.0, 1.0);
		sum += texture(art, vec2(edge_u, v)) * w;
		weight_sum += w;
	}
	COLOR *= sum / weight_sum;
}
