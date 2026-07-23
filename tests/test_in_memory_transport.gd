extends GutTest

var _rx: Array

func before_each():
    _rx = []

func _on_message(from_peer: String, msg: Dictionary):
    _rx.append({"from": from_peer, "msg": msg})

func test_send_routes_to_peer():
    var pair := InMemoryTransport.pair("p0", "p1")
    var host: InMemoryTransport = pair[0]
    var guest: InMemoryTransport = pair[1]
    guest.message_received.connect(_on_message)
    host.send("p1", {"kind": "hello"})
    assert_eq(_rx.size(), 1)
    assert_eq(_rx[0].from, "p0")
    assert_eq(_rx[0].msg, {"kind": "hello"})

func test_send_to_unknown_peer_is_noop():
    var pair := InMemoryTransport.pair("p0", "p1")
    var host: InMemoryTransport = pair[0]
    host.send("ghost", {"kind": "hello"})  # ne doit pas planter
    assert_true(true)

func test_drop_emits_peer_disconnected_on_other_side():
    var pair := InMemoryTransport.pair("p0", "p1")
    var host: InMemoryTransport = pair[0]
    var guest: InMemoryTransport = pair[1]
    var gone: Array = []
    host.peer_disconnected.connect(func(pid): gone.append(pid))
    guest.drop()
    assert_eq(gone, ["p1"])

func test_announce_connected_fires_for_each_peer():
    var pair := InMemoryTransport.pair("p0", "p1")
    var host: InMemoryTransport = pair[0]
    var seen: Array = []
    host.peer_connected.connect(func(pid): seen.append(pid))
    host.announce_connected()
    assert_eq(seen, ["p1"])

func test_poll_is_noop():
    var pair := InMemoryTransport.pair("p0", "p1")
    var host: InMemoryTransport = pair[0]
    host.message_received.connect(_on_message)
    host.poll(0.016)   # ne doit rien émettre ni planter
    assert_eq(_rx.size(), 0)

func test_emit_suspended_and_resumed():
    var pair := InMemoryTransport.pair("p0", "p1")
    var host: InMemoryTransport = pair[0]
    var suspended: Array = []
    var resumed: Array = []
    host.peer_suspended.connect(func(pid): suspended.append(pid))
    host.peer_resumed.connect(func(pid): resumed.append(pid))
    host.emit_suspended("p1")
    host.emit_resumed("p1")
    assert_eq(suspended, ["p1"])
    assert_eq(resumed, ["p1"])
