shader_type sky;

uniform vec3 sun_direction = vec3(0.85, 0.30, -0.44);
uniform float daylight : hint_range(0.0, 1.0) = 0.85;

float hash_cell(vec2 point) {
	vec3 p = fract(vec3(point.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float soft_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 f = fract(point);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), f.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void sky() {
	float height = max(EYEDIR.y, 0.0);
	float gradient = pow(height, 0.43);
	vec3 horizon = mix(vec3(0.035, 0.055, 0.12), vec3(0.62, 0.75, 0.86), daylight);
	vec3 zenith = mix(vec3(0.005, 0.012, 0.038), vec3(0.13, 0.31, 0.57), daylight);
	vec3 color = mix(horizon, zenith, gradient);
	float sun_alignment = max(dot(EYEDIR, sun_direction), 0.0);
	float twilight = 1.0 - smoothstep(0.02, 0.27, abs(sun_direction.y));
	color += vec3(0.70, 0.23, 0.10) * twilight * pow(sun_alignment, 3.0)
		* exp(-height * 4.5);
	color = mix(vec3(0.13, 0.17, 0.25) * (0.45 + 0.55 * daylight), color,
		smoothstep(-0.22, 0.025, EYEDIR.y));

	if (!AT_CUBEMAP_PASS) {
		float disk = smoothstep(0.99965, 0.99985, sun_alignment);
		color += vec3(1.7, 1.35, 0.86) * (disk + 0.26 * pow(sun_alignment, 24.0))
			* smoothstep(-0.08, 0.10, sun_direction.y);
		float moon_alignment = max(dot(EYEDIR, -sun_direction), 0.0);
		float moon = smoothstep(0.99950, 0.99970, moon_alignment);
		color += vec3(0.53, 0.67, 0.91) * (moon + 0.1 * pow(moon_alignment, 27.0))
			* (1.0 - daylight);

		vec2 star_grid = SKY_COORDS * vec2(460.0, 230.0);
		vec2 cell = floor(star_grid);
		float seed = hash_cell(cell);
		vec2 center = vec2(hash_cell(cell + 4.8), hash_cell(cell + 19.2)) * 0.48 + 0.26;
		float star = 1.0 - smoothstep(0.035, 0.20, length(fract(star_grid) - center));
		color += star * step(0.970, seed) * vec3(0.53, 0.64, 0.83)
			* (1.0 - daylight) * smoothstep(0.02, 0.35, height);

		vec2 cloud_plane = EYEDIR.xz / (height + 0.26);
		float clouds = soft_noise(cloud_plane * vec2(2.8, 5.4)) * 0.68
			+ soft_noise(cloud_plane * vec2(7.3, 13.3)) * 0.32;
		float veil = smoothstep(0.49, 0.81, clouds) * smoothstep(0.015, 0.18, height);
		vec3 cloud_color = mix(vec3(0.065, 0.083, 0.135), vec3(0.73, 0.79, 0.85), daylight);
		cloud_color += vec3(0.22, 0.09, 0.055) * twilight * sun_alignment;
		color = mix(color, cloud_color, veil * 0.55);
	}
	COLOR = color;
}
