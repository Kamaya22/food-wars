class_name WebSocketTransport
extends ITransport

signal room_created(code: String)
signal room_ready(role: int, seed_value: int, opponent_id: String)
signal relay_error(reason: String)

const ROLE_HOST := 0
const ROLE_GUEST := 1

var role: int = -1
var seed_value: int = 0
var opponent_id: String = ""

var _peer: WebSocketPeer = null
var _url: String = ""
var _pending_control: Dictionary = {}
var _control_sent: bool = false
var _ready: bool = false

func connect_create(url: String) -> void:
    _pending_control = {"t": "create"}
    _open(url)

func connect_join(url: String, code: String) -> void:
    _pending_control = {"t": "join", "code": code}
    _open(url)

func _open(url: String) -> void:
    _url = url
    _peer = WebSocketPeer.new()
    _peer.connect_to_url(_url)
    _control_sent = false
    _ready = false

func send(_peer_id: String, msg: Dictionary) -> void:
    if _peer == null:
        return
    _peer.send_text(Protocol.serialize(msg))

func poll(_delta: float) -> void:
    if _peer == null:
        return
    _peer.poll()
    var state := _peer.get_ready_state()
    if state == WebSocketPeer.STATE_OPEN:
        if not _control_sent and not _pending_control.is_empty():
            _peer.send_text(JSON.stringify(_pending_control))
            _control_sent = true
        while _peer.get_available_packet_count() > 0:
            _dispatch(_peer.get_packet().get_string_from_utf8())
    elif state == WebSocketPeer.STATE_CLOSED:
        if _ready and opponent_id != "":
            peer_disconnected.emit(opponent_id)
        _peer = null

# Traite un message texte reçu (contrôle relais OU message de jeu). Testable sans socket.
func _dispatch(text: String) -> void:
    var msg := Protocol.deserialize(text)
    if msg.is_empty():
        return
    if msg.has("t"):
        _dispatch_control(msg)
    else:
        message_received.emit(opponent_id, msg)

func _dispatch_control(msg: Dictionary) -> void:
    match String(msg.get("t", "")):
        "created":
            room_created.emit(String(msg.get("code", "")))
        "room_ready":
            role = ROLE_HOST if String(msg.get("role", "")) == "host" else ROLE_GUEST
            seed_value = int(msg.get("seed", 0))
            opponent_id = String(msg.get("opponent_id", ""))
            _ready = true
            room_ready.emit(role, seed_value, opponent_id)
            peer_connected.emit(opponent_id)
        "peer_left":
            peer_suspended.emit(opponent_id)
        "peer_rejoined":
            peer_resumed.emit(opponent_id)
        "host_left", "room_closed":
            peer_disconnected.emit(opponent_id)
        "error":
            relay_error.emit(String(msg.get("reason", "")))
