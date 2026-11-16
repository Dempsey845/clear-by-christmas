shader_type spatial;

uniform vec3 snow_color : source_color = vec3(0.90, 0.95, 1.0);
uniform vec3 cut_color : source_color = vec3(0.60, 0.75, 0.90);

void fragment() {
	if (COLOR.r < 0.012) {
		discard;
	}
	float grain = fract(sin(dot(floor(UV * 95.0), vec2(12.9898, 78.233))) * 43758.5453);
	float top = smoothstep(0.45, 0.95, COLOR.g);
	ALBEDO = mix(cut_color, snow_color, top) * mix(0.95, 1.0, grain);
	ALBEDO *= mix(1.0, 0.78, COLOR.b);
	ROUGHNESS = 0.91;
}
