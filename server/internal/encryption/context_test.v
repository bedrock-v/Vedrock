module encryption

fn test_key_wrong_size_rejected() {
	if _ := new_context([]u8{len: 16}) {
		assert false, 'expected error for 16-byte key'
	}
}

fn make_key() []u8 {
	mut key := []u8{len: 32}
	for i in 0 .. 32 {
		key[i] = u8(i + 1)
	}
	return key
}

fn test_round_trip_returns_original() {
	key := make_key()
	mut enc := new_context(key)!
	mut dec := new_context(key)!
	payload := 'hello bedrock world'.bytes()
	cipher := enc.encrypt(payload)
	assert cipher.len == payload.len + checksum_len
	assert cipher != payload
	plain := dec.decrypt(cipher)!
	assert plain == payload
}

fn test_multiple_packets_advance_counters() {
	key := make_key()
	mut enc := new_context(key)!
	mut dec := new_context(key)!
	messages := [
		'first packet'.bytes(),
		'second packet is longer than the first'.bytes(),
		'four'.bytes(),
	]
	for m in messages {
		c := enc.encrypt(m)
		p := dec.decrypt(c)!
		assert p == m
	}
	assert enc.encrypt_counter == u64(messages.len)
	assert dec.decrypt_counter == u64(messages.len)
}

fn test_checksum_mismatch_detected() {
	key := make_key()
	mut enc := new_context(key)!
	mut dec := new_context(key)!
	mut cipher := enc.encrypt('tamper me'.bytes())
	cipher[0] ^= 0xff
	if _ := dec.decrypt(cipher) {
		assert false, 'expected checksum mismatch error'
	}
}

fn test_out_of_order_counter_fails() {
	key := make_key()
	mut enc := new_context(key)!
	mut dec := new_context(key)!
	c0 := enc.encrypt('packet zero'.bytes())
	c1 := enc.encrypt('packet one'.bytes())
	// Decrypting the second packet first breaks the CTR stream alignment and the
	// counter used in the checksum, so it must be rejected.
	if _ := dec.decrypt(c1) {
		assert false, 'expected failure decrypting out of order'
	}
	_ := c0
}

fn test_der_to_raw_pads_components() {
	// SEQUENCE(len=6){ INTEGER 0x01, INTEGER 0x02 } -> two 48-byte components.
	der := [u8(0x30), 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02]
	raw := der_ecdsa_to_raw(der, 48)!
	assert raw.len == 96
	assert raw[47] == 0x01
	assert raw[95] == 0x02
	for i in 0 .. 47 {
		assert raw[i] == 0
	}
}
