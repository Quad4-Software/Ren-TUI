// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Quad4

/*
Local identity load generate hash and sign helpers.
*/

package lxmf

import "core:crypto"
import "core:crypto/ed25519"
import "core:crypto/hash"
import "core:crypto/x25519"
import "core:os"
import "core:strings"

Identity_Material :: struct {
	enc_priv:  [32]u8,
	sign_seed: [32]u8,
	enc_pub:   [32]u8,
	sign_pub:  [32]u8,
	hash:      [HASH_LEN]u8,
	priv:      ed25519.Private_Key,
	loaded:    bool,
}

full_hash :: proc(data: []u8) -> [MESSAGE_ID_LEN]u8 {
	out: [MESSAGE_ID_LEN]u8
	hash.hash_bytes_to_buffer(.SHA256, data, out[:])
	return out
}

truncated_hash :: proc(data: []u8) -> [HASH_LEN]u8 {
	full := full_hash(data)
	out: [HASH_LEN]u8
	copy(out[:], full[:HASH_LEN])
	return out
}

identity_public_key :: proc(m: ^Identity_Material) -> [64]u8 {
	out: [64]u8
	copy(out[:32], m.enc_pub[:])
	copy(out[32:], m.sign_pub[:])
	return out
}

identity_derive :: proc(m: ^Identity_Material) {
	x25519.scalarmult_basepoint(m.enc_pub[:], m.enc_priv[:])
	ed25519.private_key_set_bytes(&m.priv, m.sign_seed[:])
	ed25519.private_key_public_bytes(&m.priv, m.sign_pub[:])
	pub := identity_public_key(m)
	m.hash = truncated_hash(pub[:])
	m.loaded = true
}

identity_from_blob :: proc(blob: []u8) -> (Identity_Material, bool) {
	if len(blob) != 64 {
		return {}, false
	}
	m: Identity_Material
	copy(m.enc_priv[:], blob[:32])
	copy(m.sign_seed[:], blob[32:64])
	identity_derive(&m)
	return m, true
}

identity_load_file :: proc(path: string) -> (Identity_Material, bool) {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		return {}, false
	}
	defer delete(data)
	return identity_from_blob(data)
}

identity_save_file :: proc(m: ^Identity_Material, path: string) -> bool {
	if !m.loaded {
		return false
	}
	blob: [64]u8
	copy(blob[:32], m.enc_priv[:])
	copy(blob[32:], m.sign_seed[:])
	perm := os.Permissions{.Read_User, .Write_User}
	if os.write_entire_file(path, blob[:], perm) != nil {
		return false
	}
	_ = os.chmod(path, perm)
	return true
}

identity_generate :: proc() -> (Identity_Material, bool) {
	m: Identity_Material
	if !ed25519.private_key_generate(&m.priv) {
		return {}, false
	}
	ed25519.private_key_bytes(&m.priv, m.sign_seed[:])
	if !crypto.HAS_RAND_BYTES {
		return {}, false
	}
	crypto.rand_bytes(m.enc_priv[:])
	identity_derive(&m)
	return m, true
}

identity_sign :: proc(m: ^Identity_Material, data: []u8) -> ([SIGNATURE_LEN]u8, bool) {
	if !m.loaded {
		return {}, false
	}
	sig: [SIGNATURE_LEN]u8
	ed25519.sign(&m.priv, data, sig[:])
	return sig, true
}

identity_verify :: proc(sign_pub: []u8, data: []u8, signature: []u8) -> bool {
	if len(sign_pub) != 32 || len(signature) != SIGNATURE_LEN {
		return false
	}
	pub: ed25519.Public_Key
	if !ed25519.public_key_set_bytes(&pub, sign_pub) {
		return false
	}
	return ed25519.verify(&pub, data, signature)
}

destination_name :: proc(app: string, aspects: []string, allocator := context.allocator) -> string {
	parts := make([dynamic]string, 0, 1 + len(aspects), context.temp_allocator)
	append(&parts, app)
	for a in aspects {
		append(&parts, a)
	}
	return strings.join(parts[:], ".", allocator)
}

destination_hash :: proc(identity_hash: []u8, app: string, aspects: []string) -> [HASH_LEN]u8 {
	name := destination_name(app, aspects, context.temp_allocator)
	name_full := full_hash(transmute([]u8)name)
	material: [NAME_HASH_LEN + HASH_LEN]u8
	copy(material[:NAME_HASH_LEN], name_full[:NAME_HASH_LEN])
	n := NAME_HASH_LEN
	if len(identity_hash) >= HASH_LEN {
		copy(material[n:], identity_hash[:HASH_LEN])
		n += HASH_LEN
	}
	final := full_hash(material[:n])
	out: [HASH_LEN]u8
	copy(out[:], final[:HASH_LEN])
	return out
}

delivery_hash :: proc(identity_hash: []u8) -> [HASH_LEN]u8 {
	return destination_hash(identity_hash, APP_NAME, {ASPECT_DELIVERY})
}

nomad_node_hash :: proc(identity_hash: []u8) -> [HASH_LEN]u8 {
	return destination_hash(identity_hash, "nomadnetwork", {"node"})
}

propagation_hash :: proc(identity_hash: []u8) -> [HASH_LEN]u8 {
	return destination_hash(identity_hash, APP_NAME, {ASPECT_PROPAGATION})
}

Announce_Kind :: enum {
	Unknown,
	Lxmf_Delivery,
	Nomad_Node,
	Lxmf_Propagation,
}

classify_announce :: proc(dest_hash: []u8, identity_hash: []u8) -> Announce_Kind {
	if len(dest_hash) != HASH_LEN || len(identity_hash) != HASH_LEN {
		return .Unknown
	}
	id: [HASH_LEN]u8
	copy(id[:], identity_hash)
	d: [HASH_LEN]u8
	copy(d[:], dest_hash)
	if delivery_hash(id[:]) == d {
		return .Lxmf_Delivery
	}
	if nomad_node_hash(id[:]) == d {
		return .Nomad_Node
	}
	if propagation_hash(id[:]) == d {
		return .Lxmf_Propagation
	}
	return .Unknown
}

