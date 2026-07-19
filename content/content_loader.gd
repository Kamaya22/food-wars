class_name ContentLoader
extends RefCounted

class LoadResult:
    var ok: bool = false
    var db: ContentDB = null
    var errors: PackedStringArray = PackedStringArray()

static func load_from_json_file(path: String) -> LoadResult:
    if not FileAccess.file_exists(path):
        var r := LoadResult.new()
        r.db = ContentDB.new()
        r.errors.append("fichier introuvable : %s" % path)
        return r
    var text := FileAccess.get_file_as_string(path)
    var json := JSON.new()
    var parse_err := json.parse(text)
    var parsed = json.get_data() if parse_err == OK else null
    if parse_err != OK or typeof(parsed) != TYPE_DICTIONARY:
        var r := LoadResult.new()
        r.db = ContentDB.new()
        r.errors.append("JSON invalide dans : %s" % path)
        return r
    return load_from_dict(parsed)

static func load_from_dict(raw: Dictionary) -> LoadResult:
    var result := LoadResult.new()
    var db := ContentDB.new()
    var errors := PackedStringArray()

    _load_list(raw.get("ingredients", []), db.ingredients,
        func(d): return IngredientRes.from_dict(d), "ingredient", errors)
    _load_list(raw.get("actions", []), db.actions,
        func(d): return ActionRes.from_dict(d), "action", errors)
    _load_list(raw.get("cards", []), db.cards,
        func(d): return CardRes.from_dict(d), "card", errors)
    _load_list(raw.get("events", []), db.events,
        func(d): return EventRes.from_dict(d), "event", errors)
    _load_list(raw.get("criteria", []), db.criteria,
        func(d): return CriterionRes.from_dict(d), "criterion", errors)

    if raw.has("match_config"):
        db.match_config = MatchConfigRes.from_dict(raw["match_config"])
    else:
        errors.append("match_config manquant")

    _validate(db, errors)

    result.db = db
    result.errors = errors
    result.ok = errors.is_empty()
    return result

static func _load_list(items: Array, out: Dictionary, factory: Callable, kind: String, errors: PackedStringArray) -> void:
    for d in items:
        var id := String(d.get("id", ""))
        if id == "":
            errors.append("%s sans id" % kind)
            continue
        if out.has(id):
            errors.append("%s : id dupliqué '%s'" % [kind, id])
            continue
        out[id] = factory.call(d)

static func _validate(db: ContentDB, errors: PackedStringArray) -> void:
    # Coût des ingrédients >= 0
    for id in db.ingredients:
        var ing: IngredientRes = db.ingredients[id]
        if ing.cost < 0:
            errors.append("ingredient '%s' : cost negatif (%d)" % [id, ing.cost])

    # Cartes contextuelles : linked_action doit exister
    for id in db.cards:
        var c: CardRes = db.cards[id]
        if c.type == CardRes.Type.CONTEXTUAL:
            if c.linked_action == "" or not db.actions.has(c.linked_action):
                errors.append("card '%s' : linked_action '%s' introuvable" % [id, c.linked_action])

    # Fenêtre de déclenchement des événements
    var valid_windows := ["planning", "execution", "judgment"]
    for id in db.events:
        var e: EventRes = db.events[id]
        if not valid_windows.has(e.trigger_window):
            errors.append("event '%s' : trigger_window invalide '%s'" % [id, e.trigger_window])

    # deck_size.min <= nombre de cartes définies
    if db.match_config != null:
        if db.match_config.deck_size_min > db.cards.size():
            errors.append("match_config : deck_size.min (%d) > cartes definies (%d)" % [db.match_config.deck_size_min, db.cards.size()])
