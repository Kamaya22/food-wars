class_name InMemoryTransport
extends ITransport

var local_id: String = ""
var _peers: Dictionary = {}   # peer_id -> InMemoryTransport

# Crée deux transports déjà reliés. Index 0 = hôte, 1 = invité.
static func pair(host_id: String, guest_id: String) -> Array:
    var a := InMemoryTransport.new()
    a.local_id = host_id
    var b := InMemoryTransport.new()
    b.local_id = guest_id
    a._peers[guest_id] = b
    b._peers[host_id] = a
    return [a, b]

func send(peer_id: String, msg: Dictionary) -> void:
    var target: InMemoryTransport = _peers.get(peer_id, null)
    if target == null:
        return
    target.message_received.emit(local_id, msg)

func announce_connected() -> void:
    for pid in _peers.keys():
        peer_connected.emit(pid)

func drop() -> void:
    for pid in _peers.keys():
        var other: InMemoryTransport = _peers[pid]
        other.peer_disconnected.emit(local_id)
        other._peers.erase(local_id)
    _peers.clear()

# Helpers de test : simulent une suspension/reprise de pair (fenêtre de reconnexion).
func emit_suspended(peer_id: String) -> void:
    peer_suspended.emit(peer_id)

func emit_resumed(peer_id: String) -> void:
    peer_resumed.emit(peer_id)
