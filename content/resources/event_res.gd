class_name EventRes
extends Resource

var id: String
var display_name: String
var trigger_window: String
var effect: Dictionary

static func from_dict(d: Dictionary) -> EventRes:
    var r := EventRes.new()
    r.id = String(d.get("id", ""))
    r.display_name = String(d.get("name", r.id))
    r.trigger_window = String(d.get("trigger_window", ""))
    r.effect = d.get("effect", {})
    return r
