class_name ITransport
extends RefCounted

signal message_received(from_peer: String, msg: Dictionary)
signal peer_connected(peer_id: String)
signal peer_disconnected(peer_id: String)
signal peer_suspended(peer_id: String)
signal peer_resumed(peer_id: String)

# Interface : les implémentations concrètes doivent surcharger send().
func send(_peer_id: String, _msg: Dictionary) -> void:
    push_error("ITransport.send() non implémenté")

# Sonde le transport (draine le socket). No-op par défaut ; l'appelant l'invoque
# à chaque frame via NetSession.poll(delta).
func poll(_delta: float) -> void:
    pass
