class_name CriterionRes
extends Resource

var id: String
var weight: float
var note: String

static func from_dict(d: Dictionary) -> CriterionRes:
    var r := CriterionRes.new()
    r.id = String(d.get("id", ""))
    r.weight = float(d.get("weight", 1.0))
    r.note = String(d.get("note", ""))
    return r
