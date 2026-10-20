shader_type spatial;
// P5 boat search light: additive volume cone parented to the bow lamp.
// Mesh is a fan whose apex sits at the lamp lens and whose rim is at local
// z = beam_length, so fading along local z gives a beam that dies out ahead.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 0.87, 0.64, 1.0);
uniform float beam_intensity : hint_range(0.0, 4.0) = 0.85;
uniform float beam_length : hint_range(0.5, 40.0) = 9.0;
uniform float core_sharpness : hint_range(0.5, 6.0) = 1.8;

varying float v_beam_z;

void vertex() {
	v_beam_z = VERTEX.z;
}

void fragment() {
	float axial = clamp(1.0 - v_beam_z / beam_length, 0.0, 1.0);
	axial = axial * axial;
	float facing = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), core_sharpness);
	ALBEDO = beam_color.rgb;
	ALPHA = clamp(beam_intensity * axial * (0.22 + 0.78 * facing), 0.0, 1.0);
}
