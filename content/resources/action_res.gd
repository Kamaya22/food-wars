class_name ActionRes
extends Resource

var id: String
var display_name: String
var base_duration_sec: int
var effect: Dictionary

static func from_dict(d: Dictionary) -> ActionRes:
    var r := ActionRes.new()
    r.id = String(d.get("id", ""))
    r.display_name = String(d.get("name", r.id))
    r.base_duration_sec = int(d.get("base_duration_sec", 0))
    r.effect = d.get("effect", {})
    return r
