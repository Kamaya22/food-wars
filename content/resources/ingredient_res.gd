class_name IngredientRes
extends Resource

var id: String
var display_name: String
var cost: int
var stats: Dictionary
var tags: PackedStringArray

static func from_dict(d: Dictionary) -> IngredientRes:
    var r := IngredientRes.new()
    r.id = String(d.get("id", ""))
    r.display_name = String(d.get("name", r.id))
    r.cost = int(d.get("cost", 0))
    r.stats = Stats.clamp_stats(d.get("stats", {}), -99, 99)
    r.tags = PackedStringArray(d.get("tags", []))
    return r
