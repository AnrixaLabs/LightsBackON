extends RefCounted
## Transport selection (CLAUDE.md section 4): offline (solo, host-local calls), ENet development transport, Steam peer.
## ENet on localhost is a development transport only and never satisfies a network gate. The Steam peer is refused
## until F02 qualifies a tuple on two real PCs on separate networks.
##
## Compatibility baseline: one reliable ordered channel (channel 0); no ENet channel assumptions leak upward.
## Sender identity is read from the transport (get_packet_peer) and handed to session_host.gd with the bytes.

const MODE_OFFLINE: String = "offline"
const MODE_ENET_DEV: String = "enet_dev"
const MODE_STEAM: String = "steam"
const CHANNEL: int = 0
const MAX_PEERS: int = 3  # four players including the host


## Returns {"ok": true, "peer": MultiplayerPeer} or {"ok": false, "code", "message"}.
static func create_host(mode: String, port: int) -> Dictionary:
	match mode:
		MODE_OFFLINE:
			return {"ok": true, "peer": OfflineMultiplayerPeer.new()}
		MODE_ENET_DEV:
			var p: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
			var err: Error = p.create_server(port, MAX_PEERS, 1)
			if err != OK:
				return _fail("TRANSPORT_FAILED", "could not open the development host port")
			return {"ok": true, "peer": p}
		MODE_STEAM:
			return _fail("STEAM_NOT_QUALIFIED", "the Steam transport is not qualified yet (task F02)")
	return _fail("UNKNOWN_TRANSPORT", "unknown transport mode")


static func create_client(mode: String, address: String, port: int) -> Dictionary:
	match mode:
		MODE_ENET_DEV:
			var p: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
			if p.create_client(address, port, 1) != OK:
				return _fail("TRANSPORT_FAILED", "could not start the development client")
			return {"ok": true, "peer": p}
		MODE_STEAM:
			return _fail("STEAM_NOT_QUALIFIED", "the Steam transport is not qualified yet (task F02)")
	return _fail("UNKNOWN_TRANSPORT", "clients need a network transport")


## Durable messages: reliable, ordered, single channel.
static func send(peer: MultiplayerPeer, to_peer: int, bytes: PackedByteArray) -> Error:
	peer.transfer_channel = CHANNEL
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.set_target_peer(to_peer)
	return peer.put_packet(bytes)


## Polls and returns every waiting packet as {"peer": sender id from the transport, "bytes"}.
static func receive_all(peer: MultiplayerPeer) -> Array[Dictionary]:
	peer.poll()
	var out: Array[Dictionary] = []
	while peer.get_available_packet_count() > 0:
		var from: int = peer.get_packet_peer()  # must be read before get_packet()
		out.append({"peer": from, "bytes": peer.get_packet()})
	return out


static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "key": "network.error." + code.to_lower(), "message": message}
