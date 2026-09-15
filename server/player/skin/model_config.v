module skin

import json2

// default_geometry is the geometry a skin falls back to when it carries no
// model of its own.
pub const default_geometry = 'geometry.humanoid.custom'

// ModelConfig points at the geometry inside a Skin's model that each state of
// the skin uses. The names refer to models present in the JSON of that model.
pub struct ModelConfig {
pub mut:
	// default_model is the geometry the skin is drawn with at all times, unless
	// an animation replaces it.
	default_model string = default_geometry
	// animated_face is the geometry of an animation played over the face,
	// empty if the skin has none.
	animated_face string
}

// new_model_config returns a ModelConfig pointing at the standard humanoid
// geometry.
pub fn new_model_config() ModelConfig {
	return ModelConfig{}
}

// encode returns the resource patch of the ModelConfig, which is the form the
// client expects it in.
pub fn (cfg &ModelConfig) encode() string {
	mut geometry := map[string]json2.Any{}
	geometry['default'] = cfg.default_model
	if cfg.animated_face != '' {
		geometry['animated_face'] = cfg.animated_face
	}
	return json2.encode({
		'geometry': geometry
	})
}

// decode_model_config reads a ModelConfig back from a resource patch. It fails
// if the patch is not valid JSON.
pub fn decode_model_config(patch string) !ModelConfig {
	raw := json2.decode[json2.Any](patch)!
	geometry := raw.as_map()['geometry'] or { return ModelConfig{} }
	fields := geometry.as_map()
	mut cfg := ModelConfig{}
	if value := fields['default'] {
		cfg.default_model = value.str()
	}
	if value := fields['animated_face'] {
		cfg.animated_face = value.str()
	}
	return cfg
}
