class_name Protocol
extends RefCounted

const KIND_ROOM := "room"
const KIND_INTENT := "intent"
const KIND_SNAPSHOT := "snapshot"
const KIND_EVENTS := "events"

static func build_room(role: int, seed_value: int, opponent_id: String) -> Dictionary:
    return {"kind": KIND_ROOM, "role": role, "seed": seed_value, "opponent_id": opponent_id}

static func build_intent(seq: int, intent: Dictionary) -> Dictionary:
    return {"kind": KIND_INTENT, "seq": seq, "intent": intent}

static func build_snapshot(view: Dictionary, tick_id: int, ack_seq: int) -> Dictionary:
    return {"kind": KIND_SNAPSHOT, "view": view, "tick_id": tick_id, "ack_seq": ack_seq}

static func build_events(events: Array) -> Dictionary:
    return {"kind": KIND_EVENTS, "events": events}

static func kind_of(msg: Dictionary) -> String:
    return String(msg.get("kind", ""))

static func read_room(msg: Dictionary) -> Dictionary:
    return {
        "role": int(msg.get("role", 0)),
        "seed": int(msg.get("seed", 0)),
        "opponent_id": String(msg.get("opponent_id", "")),
    }

static func read_intent(msg: Dictionary) -> Dictionary:
    return {"seq": int(msg.get("seq", 0)), "intent": msg.get("intent", {})}

static func read_snapshot(msg: Dictionary) -> Dictionary:
    return {
        "view": msg.get("view", {}),
        "tick_id": int(msg.get("tick_id", 0)),
        "ack_seq": int(msg.get("ack_seq", 0)),
    }

static func read_events(msg: Dictionary) -> Array:
    return msg.get("events", [])

static func serialize(msg: Dictionary) -> String:
    return JSON.stringify(msg)

static func deserialize(text: String) -> Dictionary:
    var json = JSON.new()
    var error = json.parse(text)
    if error != OK:
        return {}
    if typeof(json.data) != TYPE_DICTIONARY:
        return {}
    return json.data
