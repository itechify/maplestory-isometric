class_name OccluderDither
extends RefCounted
## Dithered see-through stand-ins for the world's occluder materials (OcclusionFader).
##
## The exported world materials are simple StandardMaterial3Ds: a baked vertex-colour albedo, roughness, specular,
## optional emission, double-sided bodies and an unshaded single-sided ink shell (docs/runtime/blender_export.md
## "Materials"). clone_for() rebuilds one as a ShaderMaterial that renders the same and adds a screen-door cut: inside
## the holes around the player and nearby monsters (view-space circles, OcclusionMath.hole), fragments nearer than the
## hole's depth and above its target's feet (OcclusionMath.hole_floor) are discarded against an
## interleaved-gradient-noise threshold, scaled by the mesh's `occlusion_fade` instance uniform. Discarding against
## one screen-space pattern is order independent: a canopy's front faces, back faces and ink shell drop the same
## pixels, so stacked layers cannot add up to an opaque blob the way alpha-blended fades do, and the remaining dots
## still write depth (the player's stencil X-ray reads through them). The cut is skipped in the sun's shadow pass
## (its view direction differs from the gameplay camera's), so shadows never change.
##
## A material that is not a plain opaque StandardMaterial3D (textures, transparency, a next pass, grow) is not
## convertible: clone_for() returns null and the fader falls back to GeometryInstance3D.transparency.

## Most holes the shader evaluates (the player and up to 7 monsters).
const MAX_HOLES := 8
## The instance uniform that fades one mesh's cut (0 = solid, 1 = full strength).
const FADE_PARAM := &"occlusion_fade"

const _CODE := """shader_type spatial;
render_mode %s;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = true;
uniform bool vertex_color_srgb = false;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform vec4 holes[%d];
uniform float hole_floor[%d];
uniform int hole_count = 0;
uniform float strength = 0.9;
uniform float edge = 0.35;
uniform vec3 view_forward = vec3(0.0, 0.0, -1.0);
instance uniform float occlusion_fade = 0.0;

void vertex() {
	if (vertex_color_srgb) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
}

void fragment() {
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
%s
	if (occlusion_fade > 0.0 && hole_count > 0 && dot(-INV_VIEW_MATRIX[2].xyz, view_forward) > 0.99) {
		float cut = 0.0;
		float world_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
		for (int i = 0; i < hole_count; i++) {
			vec4 h = holes[i];
			if (-VERTEX.z > h.w || h.z <= 0.0 || world_y < hole_floor[i]) {
				continue;
			}
			float d = length(VERTEX.xy - h.xy) / h.z;
			cut = max(cut, 1.0 - smoothstep(1.0 - edge, 1.0, d));
		}
		cut *= occlusion_fade * strength;
		float noise = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (noise < cut) {
			discard;
		}
	}
}
"""

const _LIT := """	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	EMISSION = emission * emission_energy;"""

const _CULL := {
	BaseMaterial3D.CULL_BACK: "cull_back",
	BaseMaterial3D.CULL_FRONT: "cull_front",
	BaseMaterial3D.CULL_DISABLED: "cull_disabled",
}

## Fraction of the pixels removed at a hole's centre at full fade (camera.json occluder_dither_strength).
var strength: float = 0.9
## Soft rim of a hole, as a fraction of its radius (camera.json occluder_hole_edge).
var edge: float = 0.35

## Original material -> its ShaderMaterial stand-in (null when not convertible).
var _clones: Dictionary = {}
## Variant key ("lit|cull_disabled") -> Shader, shared by every OccluderDither.
static var _shaders: Dictionary = {}


## True for the materials clone_for() can reproduce exactly: opaque StandardMaterial3D / ORMMaterial3D without
## textures, a next pass or grow, and with the default diffuse and specular models.
static func convertible(m: Material) -> bool:
	var b := m as BaseMaterial3D
	if b == null or m.next_pass != null:
		return false
	if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or b.grow or b.albedo_texture != null:
		return false
	if b.normal_enabled or b.emission_texture != null or b.roughness_texture != null or b.metallic_texture != null:
		return false
	if b.diffuse_mode != BaseMaterial3D.DIFFUSE_BURLEY or b.specular_mode != BaseMaterial3D.SPECULAR_SCHLICK_GGX:
		return false
	if b.stencil_mode != BaseMaterial3D.STENCIL_MODE_DISABLED or b.depth_test != BaseMaterial3D.DEPTH_TEST_DEFAULT:
		return false
	if b.no_depth_test or b.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or b.use_point_size:
		return false
	if b.uv1_triplanar or b.detail_enabled or b.clearcoat_enabled or b.rim_enabled or b.ao_enabled or b.heightmap_enabled:
		return false
	if b.shading_mode == BaseMaterial3D.SHADING_MODE_PER_VERTEX or b.disable_receive_shadows or b.shadow_to_opacity:
		return false
	if b.disable_ambient_light or b.disable_fog or b.fixed_size or b.backlight_enabled or b.subsurf_scatter_enabled:
		return false
	return b.cull_mode in _CULL


## The dithered stand-in of `m` (cached per material), or null when `m` is not convertible.
func clone_for(m: Material) -> ShaderMaterial:
	if m == null:
		return null
	if _clones.has(m):
		return _clones[m]
	var out: ShaderMaterial = null
	if convertible(m):
		var b := m as BaseMaterial3D
		out = ShaderMaterial.new()
		out.resource_name = b.resource_name + "_occluder_dither"
		out.shader = shader_for(b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, b.cull_mode)
		out.render_priority = b.render_priority
		out.set_shader_parameter(&"albedo", b.albedo_color)
		out.set_shader_parameter(&"use_vertex_color", b.vertex_color_use_as_albedo)
		out.set_shader_parameter(&"vertex_color_srgb", b.vertex_color_is_srgb)
		out.set_shader_parameter(&"roughness", b.roughness)
		out.set_shader_parameter(&"metallic", b.metallic)
		out.set_shader_parameter(&"specular", b.metallic_specular)
		var em := b.emission if b.emission_enabled else Color.BLACK
		out.set_shader_parameter(&"emission", Vector3(em.r, em.g, em.b))
		out.set_shader_parameter(&"emission_energy", b.emission_energy_multiplier if b.emission_enabled else 0.0)
		out.set_shader_parameter(&"strength", strength)
		out.set_shader_parameter(&"edge", edge)
	_clones[m] = out
	return out


## Hands every stand-in this frame's holes (view space, OcclusionMath.hole), the gameplay camera's forward
## direction (the shadow-pass gate) and each hole's floor: the world height below which that hole cuts nothing
## (its target's feet, OcclusionMath.hole_floor), so the deck or floor a target stands on never gets a hole. A hole
## without a floor value cuts at every height.
func update(holes: PackedVector4Array, view_forward: Vector3, floors: PackedFloat32Array = PackedFloat32Array()) -> void:
	var arr := PackedVector4Array()
	arr.resize(MAX_HOLES)
	var fl := PackedFloat32Array()
	fl.resize(MAX_HOLES)
	fl.fill(-1.0e9)
	var n := mini(holes.size(), MAX_HOLES)
	for i in n:
		arr[i] = holes[i]
		if i < floors.size():
			fl[i] = floors[i]
	for m in _clones.values():
		var sm := m as ShaderMaterial
		if sm == null:
			continue
		sm.set_shader_parameter(&"holes", arr)
		sm.set_shader_parameter(&"hole_floor", fl)
		sm.set_shader_parameter(&"hole_count", n)
		sm.set_shader_parameter(&"view_forward", view_forward)


## Number of materials converted so far.
func clone_count() -> int:
	var n := 0
	for m in _clones.values():
		if m != null:
			n += 1
	return n


## The shared shader of one variant (unshaded or lit, a BaseMaterial3D cull mode).
static func shader_for(unshaded: bool, cull: int) -> Shader:
	var key := "%s|%d" % ["unshaded" if unshaded else "lit", cull]
	if _shaders.has(key):
		return _shaders[key]
	var modes := PackedStringArray([String(_CULL.get(cull, "cull_back"))])
	if unshaded:
		modes.append("unshaded")
	else:
		modes.append_array(["blend_mix", "depth_draw_opaque", "diffuse_burley", "specular_schlick_ggx"])
	var sh := Shader.new()
	sh.code = _CODE % [", ".join(modes), MAX_HOLES, MAX_HOLES, "" if unshaded else _LIT]
	_shaders[key] = sh
	return sh
