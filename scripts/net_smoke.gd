extends SceneTree

# Usage :
#   Hôte   : godot --headless -s scripts/net_smoke.gd -- host ws://localhost:8080
#   Invité : godot --headless -s scripts/net_smoke.gd -- join ws://localhost:8080 <CODE>

var _db: ContentDB
var _transport: WebSocketTransport
var _session: NetSession
var _mode: String = ""
var _did_plan: bool = false
var _elapsed: float = 0.0

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() < 2:
        print("args: host|join <url> [code]")
        quit(1)
        return
    _mode = args[0]
    var url: String = args[1]
    _db = MatchContent.db()
    _transport = WebSocketTransport.new()
    _transport.room_created.connect(_on_room_created)
    _transport.room_ready.connect(_on_room_ready)
    _transport.relay_error.connect(func(r): print("ERREUR RELAIS: ", r); quit(1))
    if _mode == "host":
        _transport.connect_create(url)
    else:
        _transport.connect_join(url, args[2])
    print("[%s] connexion à %s…" % [_mode, url])

func _on_room_created(code: String) -> void:
    print("[host] CODE DE ROOM = ", code, "  (lancez l'invité avec ce code)")

func _on_room_ready(role: int, seed_value: int, opponent_id: String) -> void:
    print("[%s] room prête (role=%d, seed=%d, adversaire=%s)" % [_mode, role, seed_value, opponent_id])
    if role == WebSocketTransport.ROLE_HOST:
        var state := GameCore.start_match(_db, _db.match_config, seed_value, ["host", "guest"])
        _session = NetSession.create_host(_db, state, _transport, "host", ["guest"])
    else:
        _session = NetSession.create_guest(_db, _transport, "guest", "host")

func _process(delta: float) -> bool:
    if _transport != null:
        _transport.poll(delta)
    if _session == null:
        return false
    if _mode == "host":
        _host_step(delta)
    else:
        _guest_step()
    return false

func _host_step(delta: float) -> void:
    if not _did_plan:
        _did_plan = true
        _session.host_apply_local({"type": Intents.ADD_INGREDIENT, "ingredient_id": "boeuf"})
        _session.host_apply_local({"type": Intents.ADD_ACTION, "action_id": "cuire"})
        _session.host_apply_local({"type": Intents.SET_READY, "ready": true})
    if _session.host_state().phase == GameState.Phase.EXECUTION:
        _session.host_tick(delta)
    if _session.host_state().phase == GameState.Phase.FINISHED:
        print("[host] MATCH TERMINÉ — résultat: ", _session.host_state().result)
        quit(0)

var _guest_ready: bool = false
func _guest_step() -> void:
    if not _guest_ready:
        _guest_ready = true
        _session.send_intent({"type": Intents.SET_READY, "ready": true})
    var v := _session.reconciler.current_view()
    if not v.is_empty() and int(v.get("phase", 0)) == GameState.Phase.FINISHED:
        print("[guest] vue finale reçue — phase FINISHED, tick=", _session.reconciler.current_tick_id())
        quit(0)
