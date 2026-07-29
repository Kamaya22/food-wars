extends GutTest

func _make() -> WebSocketTransport:
    return WebSocketTransport.new()

func test_dispatch_room_ready_sets_state_and_emits():
    var t := _make()
    var ready: Array = []
    var connected: Array = []
    t.room_ready.connect(func(role, seed_value, opp): ready.append([role, seed_value, opp]))
    t.peer_connected.connect(func(pid): connected.append(pid))
    t._dispatch('{"t":"room_ready","role":"host","seed":4242,"opponent_id":"guest"}')
    assert_eq(t.role, WebSocketTransport.ROLE_HOST)
    assert_eq(t.seed_value, 4242)
    assert_eq(t.opponent_id, "guest")
    assert_eq(ready, [[WebSocketTransport.ROLE_HOST, 4242, "guest"]])
    assert_eq(connected, ["guest"])

func test_dispatch_created_emits_room_code():
    var t := _make()
    var codes: Array = []
    t.room_created.connect(func(c): codes.append(c))
    t._dispatch('{"t":"created","code":"WOK7"}')
    assert_eq(codes, ["WOK7"])

func test_dispatch_game_message_emits_message_received_from_opponent():
    var t := _make()
    t._dispatch('{"t":"room_ready","role":"guest","seed":1,"opponent_id":"host"}')
    var rx: Array = []
    t.message_received.connect(func(from, msg): rx.append([from, msg]))
    t._dispatch('{"kind":"snapshot","view":{},"tick_id":5,"ack_seq":2}')
    assert_eq(rx.size(), 1)
    assert_eq(rx[0][0], "host", "from_peer = adversaire")
    assert_eq(Protocol.kind_of(rx[0][1]), Protocol.KIND_SNAPSHOT)

func test_dispatch_reconnect_control_maps_to_signals():
    var t := _make()
    t._dispatch('{"t":"room_ready","role":"host","seed":1,"opponent_id":"guest"}')
    var suspended: Array = []
    var resumed: Array = []
    var disconnected: Array = []
    t.peer_suspended.connect(func(pid): suspended.append(pid))
    t.peer_resumed.connect(func(pid): resumed.append(pid))
    t.peer_disconnected.connect(func(pid): disconnected.append(pid))
    t._dispatch('{"t":"peer_left"}')
    t._dispatch('{"t":"peer_rejoined"}')
    t._dispatch('{"t":"room_closed"}')
    assert_eq(suspended, ["guest"])
    assert_eq(resumed, ["guest"])
    assert_eq(disconnected, ["guest"])

func test_dispatch_error_emits_relay_error():
    var t := _make()
    var errs: Array = []
    t.relay_error.connect(func(reason): errs.append(reason))
    t._dispatch('{"t":"error","reason":"unknown_code"}')
    assert_eq(errs, ["unknown_code"])

func test_send_without_connection_is_noop():
    var t := _make()
    t.send("guest", {"kind": "intent"})   # pas de socket ouvert → ne doit pas planter
    assert_true(true)

func test_poll_without_connection_is_noop():
    var t := _make()
    t.poll(0.016)
    assert_true(true)
