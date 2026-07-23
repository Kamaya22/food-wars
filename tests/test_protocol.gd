extends GutTest

func test_intent_round_trip():
    var intent := {"type": "add_ingredient", "ingredient_id": "boeuf"}
    var msg := Protocol.build_intent(7, intent)
    assert_eq(Protocol.kind_of(msg), Protocol.KIND_INTENT)
    var r := Protocol.read_intent(msg)
    assert_eq(r.seq, 7)
    assert_eq(r.intent, intent)

func test_snapshot_round_trip():
    var view := {"phase": 1, "you": {"budget_left": 4}}
    var msg := Protocol.build_snapshot(view, 12, 3)
    assert_eq(Protocol.kind_of(msg), Protocol.KIND_SNAPSHOT)
    var r := Protocol.read_snapshot(msg)
    assert_eq(r.view, view)
    assert_eq(r.tick_id, 12)
    assert_eq(r.ack_seq, 3)

func test_events_round_trip():
    var events := [{"type": "ready_changed", "player": "p0"}]
    var msg := Protocol.build_events(events)
    assert_eq(Protocol.kind_of(msg), Protocol.KIND_EVENTS)
    assert_eq(Protocol.read_events(msg), events)

func test_room_round_trip():
    var msg := Protocol.build_room(0, 2024, "p1")
    assert_eq(Protocol.kind_of(msg), Protocol.KIND_ROOM)
    var r := Protocol.read_room(msg)
    assert_eq(r.role, 0)
    assert_eq(r.seed, 2024)
    assert_eq(r.opponent_id, "p1")

func test_kind_of_unknown_message_is_empty():
    assert_eq(Protocol.kind_of({}), "")

func test_serialize_deserialize_intent_round_trip():
    var intent := {"type": "add_ingredient", "ingredient_id": "boeuf"}
    var msg := Protocol.build_intent(7, intent)
    var text := Protocol.serialize(msg)
    assert_eq(typeof(text), TYPE_STRING)
    var back := Protocol.deserialize(text)
    assert_eq(Protocol.kind_of(back), Protocol.KIND_INTENT)
    var r := Protocol.read_intent(back)
    assert_eq(r.seq, 7)
    assert_eq(r.intent, intent)

func test_serialize_deserialize_snapshot_preserves_ints():
    # JSON coerce les nombres en float ; read_snapshot recaste via int().
    var view := {"phase": 1, "you": {"name": "p0"}}
    var msg := Protocol.build_snapshot(view, 12, 3)
    var back := Protocol.deserialize(Protocol.serialize(msg))
    var r := Protocol.read_snapshot(back)
    assert_eq(r.tick_id, 12)
    assert_eq(r.ack_seq, 3)
    assert_eq(String(r.view.get("you", {}).get("name", "")), "p0")

func test_deserialize_invalid_text_returns_empty():
    assert_eq(Protocol.deserialize("pas du json"), {})
    assert_eq(Protocol.deserialize("[1,2,3]"), {}, "un tableau JSON n'est pas un message")
