shader_type canvas_item;
render_mode unshaded;

// 이미 렌더된 3D 장면을 샘플링
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// 색 수차 강도 — 사람 눈의 RGB 채널 굴절 차이 재현
// 실제 눈은 중심와(fovea) 내 CA를 뇌가 보정 → 주변부에서만 발생
uniform float ca_strength : hint_range(0.0, 0.01) = 0.0015;
// 주변부 밝기 감소 강도 — 중심와 외 영역 민감도 저하 재현.
// 0.45는 너무 강해 균일 지면(특히 땅뷰)에 '카메라 따라다니는 그림자'처럼 보였음
// (검수 확인) → 은은하게 0.16으로 낮추고 falloff 시작도 바깥으로(중심부 더 넓게 유지).
uniform float vignette_str : hint_range(0.0, 1.0) = 0.16;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 from_center = uv - 0.5;
	float dist = length(from_center);
	vec2 dir = from_center / (dist + 0.0001);

	// 색 수차: 중앙 25% 이내는 0, 그 밖으로만 부드럽게 증가
	// (중앙부는 뇌가 CA 보정 — 비/눈 입자 무지개화 방지)
	float ca = smoothstep(0.25, 0.52, dist) * ca_strength;
	float r = texture(screen_texture, uv + dir * ca).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv - dir * ca).b;
	COLOR = vec4(r, g, b, 1.0);

	// 비네트: 주변부 밝기 감소
	// falloff 시작을 0.35→0.55로 밀어 중심부 넓게 균일 유지, 먼 모서리만 은은히 감광.
	float vign = 1.0 - smoothstep(0.55, 0.92, dist) * vignette_str;
	COLOR.rgb *= vign;
}
