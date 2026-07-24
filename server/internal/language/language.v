module language

import nepinhum.i18n

@[heap]
pub struct Lang {
	tag string
mut:
	localizer i18n.Localizer
}

pub fn load(tag string) !&Lang {
	mut bundle := i18n.new_bundle(tag)!
	bundle.load_message_file('lang/${tag}.toml') or {
		bundle.load_message_file('lang/en.toml')! // fallback
	}
	localizer := i18n.new_localizer(bundle, [tag])!
	return &Lang{tag, localizer}
}

// no data
pub fn (l &Lang) t(id string) string {
	return l.localizer.localize(i18n.LocalizeConfig{ message_id: id }) or { id }
}

// with template data, e.g: tf('player.join', {'Name': 'scher'})
pub fn (l &Lang) tf(id string, data map[string]string) string {
	return l.localizer.localize(i18n.LocalizeConfig{
		message_id:    id
		template_data: data
	}) or { id }
}
