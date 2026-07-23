class_name NetSession
extends RefCounted

enum Role { HOST, GUEST }

signal session_paused(peer_id: String)
signal session_aborted(reason: String)

var role: int = Role.HOST
var local_id: String = ""
var reconciler: Reconciler = null      # invité uniquement
var last_events: Array = []            # invité uniquement

var _db: ContentDB = null
var _transport: ITransport = null

# --- état HÔTE ---
var _state: GameState = null
var _peers: Array = []                 # ids des autres joueurs (invités)
var _tick_id: int = 0
var _last_seq: Dictionary = {}         # peer_id -> dernier seq d'intent traité

# --- état INVITÉ ---
var _host_id: String = ""
var _seq: int = 0

static func create_host(db: ContentDB, state: GameState, transport: ITransport, host_id: String, peer_ids: Array) -> NetSession:
    var s := NetSession.new()
    s.role = Role.HOST
    s._db = db
    s._transport = transport
    s.local_id = host_id
    s._state = state
    s._peers = peer_ids.duplicate()
    for pid in s._peers:
        s._last_seq[pid] = 0
    transport.message_received.connect(s._on_host_message)
    transport.peer_disconnected.connect(s._on_peer_disconnected)
    return s

static func create_guest(db: ContentDB, transport: ITransport, guest_id: String, host_id: String) -> NetSession:
    var s := NetSession.new()
    s.role = Role.GUEST
    s._db = db
    s._transport = transport
    s.local_id = guest_id
    s._host_id = host_id
    s.reconciler = Reconciler.new()
    transport.message_received.connect(s._on_guest_message)
    transport.peer_disconnected.connect(s._on_peer_disconnected)
    return s

func transport() -> ITransport:
    return _transport

# --- API HÔTE ---
func host_apply_local(intent: Dictionary) -> void:
    var res := GameCore.apply_intent(_db, _state, local_id, intent)
    _broadcast(res.events)

func host_tick(delta: float) -> void:
    var res := GameCore.tick(_db, _state, delta)
    _broadcast(res.events)

func host_view() -> Dictionary:
    return GameCore.get_view(_db, _state, local_id)

func host_view_for(viewer_id: String) -> Dictionary:
    return GameCore.get_view(_db, _state, viewer_id)

func host_state() -> GameState:
    return _state

func _on_host_message(from_peer: String, msg: Dictionary) -> void:
    if Protocol.kind_of(msg) != Protocol.KIND_INTENT:
        return
    var r := Protocol.read_intent(msg)
    _last_seq[from_peer] = r.seq
    var res := GameCore.apply_intent(_db, _state, from_peer, r.intent)
    _broadcast(res.events)

func _broadcast(events: Array) -> void:
    _tick_id += 1
    for pid in _peers:
        _transport.send(pid, Protocol.build_events(events))
        var view := GameCore.get_view(_db, _state, pid)
        _transport.send(pid, Protocol.build_snapshot(view, _tick_id, int(_last_seq.get(pid, 0))))

# --- API INVITÉ ---
func send_intent(intent: Dictionary) -> int:
    _seq += 1
    reconciler.add_pending_intent(_seq)
    _transport.send(_host_id, Protocol.build_intent(_seq, intent))
    return _seq

func _on_guest_message(_from_peer: String, msg: Dictionary) -> void:
    match Protocol.kind_of(msg):
        Protocol.KIND_SNAPSHOT:
            var r := Protocol.read_snapshot(msg)
            reconciler.apply_snapshot(r.view, r.tick_id, r.ack_seq)
        Protocol.KIND_EVENTS:
            last_events = Protocol.read_events(msg)

# --- pannes ---
func _on_peer_disconnected(peer_id: String) -> void:
    if role == Role.GUEST and peer_id == _host_id:
        session_aborted.emit("host_disconnected")
    elif role == Role.HOST:
        session_paused.emit(peer_id)
