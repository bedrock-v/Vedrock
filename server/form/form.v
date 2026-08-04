module form

pub interface Form {
	// request_body returns the JSON payload sent to the client inside a ModalFormRequestPacket.
	request_body() string
	// submit is called with the raw form_data of the client's response.
	// A `none` value means the player closed the form without submitting it.
	submit(raw ?string) !
}
