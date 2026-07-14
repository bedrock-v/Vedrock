module encryption

import crypto.aes
import crypto.cipher
import crypto.sha256

const checksum_len = 8
const aes_block_size = 16

// ctrStream is a minimal AES-CTR keystream. vlib's crypto.cipher.Ctr is a
// private type so it cannot be held as a struct field - we replicate its
// stateful behaviour here: a persistent counter block and a keystream buffer
// consumed across calls, so one stream spans the whole session in one
// direction exactly like PocketMine's persistent cipher.
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

// Context is the per-session Bedrock cipher. MCPE uses "GCM without the auth
// tag", which is just AES-256-CTR with the GCM initial counter block as IV:
// the first 12 bytes of the key followed by 00 00 00 02. Each direction keeps
// its own persistent CTR keystream and a monotonic counter that feeds a
// per-packet SHA-256 checksum, matching PocketMine's EncryptionContext.
@[heap]
pub struct Context {
mut:
	key             []u8
	encrypt_stream  CtrStream
	decrypt_stream  CtrStream
	encrypt_counter u64
	decrypt_counter u64
}

// new_context builds a Context from the 32-byte AES-256 key derived during the
// handshake. It returns an error on a wrong-sized key rather than panicking.
pub fn new_context(key []u8) !&Context {
	if key.len != 32 {
		return error('encryption key must be 32 bytes, got ${key.len}')
	}
	mut iv := []u8{len: aes_block_size}
	copy(mut iv[..12], key[..12])
	iv[15] = 0x02
	return &Context{
		key:            key.clone()
		encrypt_stream: new_ctr_stream(aes.new_cipher(key), iv)
		decrypt_stream: new_ctr_stream(aes.new_cipher(key), iv)
	}
}

// encrypt appends the per-packet checksum to the plaintext, then encrypts the
// combined buffer with the send-direction CTR keystream.
pub fn (mut c Context) encrypt(payload []u8) []u8 {
	checksum := c.calculate_checksum(c.encrypt_counter, payload)
	c.encrypt_counter++
	mut plain := []u8{cap: payload.len + checksum_len}
	plain << payload
	plain << checksum
	return c.encrypt_stream.xor(plain)
}

// decrypt reverses encrypt: it decrypts with the receive-direction keystream,
// splits off the trailing checksum, and verifies it against the monotonic
// receive counter. A mismatch returns an error - the caller must disconnect.
pub fn (mut c Context) decrypt(encrypted []u8) ![]u8 {
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

// calculate_checksum returns the first 8 bytes of
// sha256(counter_LE_u64 || payload || key), the MCPE packet integrity tag.
fn (c &Context) calculate_checksum(counter u64, payload []u8) []u8 {
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
