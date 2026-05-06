shader_type canvas_item;

uniform vec2 rect_size_px = vec2(200.0, 112.0);
uniform float corner_radius_px : hint_range(0.0, 64.0, 0.5) = 10.0;

float sd_rounded_box(vec2 p, vec2 b, vec4 radii) {
	vec4 rr = radii;
	rr.xy = (p.x > 0.0) ? rr.xy : rr.zw;
	rr.x = (p.y > 0.0) ? rr.x : rr.y;
	vec2 q = abs(p) - b + rr.x;
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rr.x;
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_size_px;
	vec2 half_sz = rect_size_px * 0.5;
	float cr = clamp(corner_radius_px, 0.0, min(half_sz.x, half_sz.y));
	vec2 b = half_sz - vec2(cr);
	float d = sd_rounded_box(p, b, vec4(cr));
	float alpha = 1.0 - smoothstep(-1.25, 1.25, d);
	vec4 tex_col = texture(TEXTURE, UV);
	COLOR.rgb = tex_col.rgb * COLOR.rgb;
	COLOR.a = tex_col.a * COLOR.a * alpha;
}
