module chat

// Translation is a message the client renders in its own language. The key
// names an entry in the client's language files and the parameters fill in its
// placeholders.
pub struct Translation {
pub:
	key        string
	parameters []string
}

// translate returns a Translation for the key passed, with the parameters
// filled in in the order the key expects them.
pub fn translate(key string, parameters []string) Translation {
	return Translation{
		key:        key
		parameters: parameters
	}
}

// with returns a copy of the Translation with the parameters passed, leaving
// the original alone so a key may be declared once and reused.
pub fn (t Translation) with(parameters []string) Translation {
	return Translation{
		key:        t.key
		parameters: parameters
	}
}

// announcement_key is the translation key the client renders as an
// announcement, naming the player the message came from.
pub const announcement_key = '%chat.type.announcement'
