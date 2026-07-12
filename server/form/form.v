module form

pub interface Form {
	// request_body returns the JSON payload sent to the client inside a ModalFormRequestPacket.
	request_body() string
	// submit is called with the raw form_data of the client's response.
	// A `none` value means the player closed the form without submitting it.
	submit(raw ?string) !
	// has_network_image reports whether this form has a button image fetched
	// over the network (type url), as opposed to a bundled resource pack
	// asset (type path). The Bedrock client can get stuck showing a loading 
	// spinner on that image well after it has actually finished loading; 
	// assending the player an attribute update afterwards clears it. (see https://github.com/muqsit/FormImagesFix)
	has_network_image() bool
}
