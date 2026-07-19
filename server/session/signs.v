module session

import nbt
import protocol
import protocol.types
import server.block

fn (mut s NetworkSession) handle_block_actor_data(p protocol.BlockActorDataPacket) ! {
	pos := p.block_position
	if s.dead || !s.can_interact() {
		return
	}
	if !s.within_place_reach(pos) {
		return
	}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	b := s.hub.blocks.get(old_id) or { return }
	if b !is block.SignBlock {
		return
	}
	if p.nbt.tag !is nbt.Compound {
		return
	}
	compound := p.nbt.tag as nbt.Compound
	text := extract_sign_text(compound) or { return }
	mut wld := s.current_world()
	if isnil(wld) {
		return
	}
	wld.set_tile_text(pos.x, pos.y, pos.z, text)
	s.hub.broadcast(&protocol.BlockActorDataPacket{
		block_position: pos
		nbt:            build_sign_nbt(pos.x, pos.y, pos.z, text)
	})
}

// extract_sign_text pulls FrontText.Text out of a sign's block-entity NBT
// compound. Uses `is` checks rather than blind `as` casts since this parses
// untrusted client input, malformed NBT must be rejected.
fn extract_sign_text(compound nbt.Compound) ?string {
	front_tag := compound.get('FrontText') or { return none }
	if front_tag is nbt.Compound {
		text_tag := front_tag.get('Text') or { return none }
		if text_tag is string {
			return text_tag
		}
	}
	return none
}

// sign_text_side builds one FrontText/BackText compound.
fn sign_text_side(text string) nbt.Compound {
	mut side := nbt.new_compound()
	side.set('Text', nbt.Tag(text))
	side.set('TextOwner', nbt.Tag(''))
	side.set('SignTextColor', nbt.Tag(i32(-16777216))) // opaque black, 0xff000000
	side.set('IgnoreLighting', nbt.Tag(i8(0)))
	side.set('PersistFormatting', nbt.Tag(i8(1)))
	return side
}

fn build_sign_nbt(x int, y int, z int, text string) nbt.RootTag {
	mut root := nbt.new_compound()
	root.set('id', nbt.Tag('Sign'))
	root.set('x', nbt.Tag(i32(x)))
	root.set('y', nbt.Tag(i32(y)))
	root.set('z', nbt.Tag(i32(z)))
	root.set('IsWaxed', nbt.Tag(i8(0)))
	root.set('FrontText', nbt.Tag(sign_text_side(text)))
	root.set('BackText', nbt.Tag(sign_text_side('')))
	return nbt.RootTag{
		name: ''
		tag:  nbt.Tag(root)
	}
}

fn (mut s NetworkSession) create_sign_tile(pos types.BlockPosition, runtime_id int) {
	b := s.hub.blocks.get(runtime_id) or { return }
	if b !is block.SignBlock {
		return
	}
	mut wld := s.current_world()
	if isnil(wld) {
		return
	}
	wld.set_tile_text(pos.x, pos.y, pos.z, '')
	s.hub.broadcast(&protocol.BlockActorDataPacket{
		block_position: pos
		nbt:            build_sign_nbt(pos.x, pos.y, pos.z, '')
	})
}

fn (mut s NetworkSession) maybe_open_sign_editor(pos types.BlockPosition, runtime_id int) {
	b := s.hub.blocks.get(runtime_id) or { return }
	if b !is block.SignBlock {
		return
	}
	s.transport.send(&protocol.OpenSignPacket{
		block_position: pos
		front:          true
	}) or {}
}
