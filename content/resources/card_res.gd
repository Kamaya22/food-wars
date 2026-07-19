class_name CardRes
extends Resource

enum Type { GLOBAL, CONTEXTUAL }
enum Target { SELF, OPPONENT }

var id: String
var display_name: String
var type: Type
var target: Target
var linked_action: String
var effect: Dictionary

static func from_dict(d: Dictionary) -> CardRes:
    var r := CardRes.new()
    r.id = String(d.get("id", ""))
    r.display_name = String(d.get("name", r.id))
    r.type = Type.CONTEXTUAL if String(d.get("type", "global")) == "contextual" else Type.GLOBAL
    r.target = Target.OPPONENT if String(d.get("target", "self")) == "opponent" else Target.SELF
    r.linked_action = String(d.get("linked_action", ""))
    r.effect = d.get("effect", {})
    return r
