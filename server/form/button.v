module form

// ButtonImage is the optional icon shown next to a Button on a SimpleForm or ModalForm.
// typ is path for a builtin game asset or url for a remote image.
pub struct ButtonImage {
pub:
	typ  string @[json: 'type']
	data string
}

pub struct Button {
pub:
	typ   string = 'button' @[json: 'type']
	text  string
	image ?ButtonImage
}

pub fn (b Button) has_network_image() bool {
	if img := b.image {
		return img.typ == 'url'
	}
	return false
}

pub fn button(text string) Button {
	return Button{
		text: text
	}
}

pub fn image_button(text string, image string) Button {
	typ := if image.starts_with('http://') || image.starts_with('https://') {
		'url'
	} else {
		'path'
	}
	return Button{
		text:  text
		image: ButtonImage{
			typ:  typ
			data: image
		}
	}
}
