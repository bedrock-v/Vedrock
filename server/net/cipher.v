module net

import crypto.aes
import crypto.cipher
import crypto.sha256

const checksum_len = 8
const aes_block_size = 16

// CtrStream is an AES-CTR keystream. vlib's crypto.cipher.Ctr is a private type
// and can't be held in a struct field, so the same state is kept here by hand.
// The counter block and the keystream buffer carry over from one call to the
// next, and one stream covers a whole session in one direction.
struct CtrStream {
mut:
	block     cipher.Block
	counter   []u8
	keystream []u8
	used      int
}

fn new_ctr_stream(block cipher.Block, iv []u8) CtrStream {
	return CtrStream{
		block:     block
		counter:   iv.clone()
		keystream: []u8{len: aes_block_size}
		used:      aes_block_size
	}
}

// xor consumes src against the keystream, refilling and advancing the counter
// block one AES block at a time.
fn (mut s CtrStream) xor(src []u8) []u8 {
	mut out := []u8{len: src.len}
	for i in 0 .. src.len {
		if s.used == aes_block_size {
			s.block.encrypt(mut s.keystream, s.counter)
			s.used = 0
			for j := s.counter.len - 1; j >= 0; j-- {
				s.counter[j]++
				if s.counter[j] != 0 {
					break
				}
			}
		}
		out[i] = src[i] ^ s.keystream[s.used]
		s.used++
	}
	return out
}

// Cipher is the game's own encryption for one session, used when the transport
// does not encrypt on its own.
@[heap]
struct Cipher {
mut:
	key             []u8
	encrypt_stream  CtrStream
	decrypt_stream  CtrStream
	encrypt_counter u64
	decrypt_counter u64
}

// new_cipher builds the cipher from the key the handshake derived.
fn new_cipher(key []u8) !&Cipher {
	if key.len != 32 {
		return error('encryption key must be 32 bytes, got ${key.len}')
	}
	mut iv := []u8{len: aes_block_size}
	copy(mut iv[..12], key[..12])
	iv[15] = 0x02
	return &Cipher{
		key:            key.clone()
		encrypt_stream: new_ctr_stream(aes.new_cipher(key)!, iv)
		decrypt_stream: new_ctr_stream(aes.new_cipher(key)!, iv)
	}
}

// encrypt appends the message's checksum and encrypts both with the send
// keystream. Both the keystream and the counter carry over to the next message,
// which is why messages have to be encrypted in the order they go out.
fn (mut c Cipher) encrypt(payload []u8) []u8 {
	checksum := c.calculate_checksum(c.encrypt_counter, payload)
	c.encrypt_counter++
	mut plain := []u8{cap: payload.len + checksum_len}
	plain << payload
	plain << checksum
	return c.encrypt_stream.xor(plain)
}

// decrypt reverses encrypt. It decrypts with the receive keystream, splits off
// the trailing checksum and checks it against the receive counter. A mismatch
// means the message was tampered with or arrived out of order, and the
// connection has to go.
fn (mut c Cipher) decrypt(encrypted []u8) ![]u8 {
	if encrypted.len < checksum_len + 1 {
		return error('encrypted payload too short')
	}
	decrypted := c.decrypt_stream.xor(encrypted)
	payload := decrypted[..decrypted.len - checksum_len].clone()
	actual := decrypted[decrypted.len - checksum_len..].clone()
	expected := c.calculate_checksum(c.decrypt_counter, payload)
	c.decrypt_counter++
	if actual != expected {
		return error('encrypted packet checksum mismatch')
	}
	return payload
}

// calculate_checksum is the first eight bytes of
// sha256(counter_le_u64 || payload || key), the game's integrity tag.
fn (c &Cipher) calculate_checksum(counter u64, payload []u8) []u8 {
	mut buf := []u8{cap: 8 + payload.len + c.key.len}
	mut counter_le := []u8{len: 8}
	mut v := counter
	for i in 0 .. 8 {
		counter_le[i] = u8(v & 0xff)
		v >>= 8
	}
	buf << counter_le
	buf << payload
	buf << c.key
	hash := sha256.sum256(buf)
	return hash[..checksum_len]
}
