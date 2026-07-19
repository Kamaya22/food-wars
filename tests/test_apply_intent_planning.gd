extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

func _fresh() -> GameState:
    return GameCore.start_match(_db, _db.match_config, 5, ["p0", "p1"])

func _events_of(res: Dictionary, type: String) -> Array:
    var out := []
    for e in res.events:
        if e.type == type:
            out.append(e)
    return out

func test_add_ingredient_deducts_budget():
    var s := _fresh()
    var before: int = s.players["p0"].budget_left
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "tomate"})
    assert_eq(s.players["p0"].ingredients, ["tomate"])
    assert_eq(s.players["p0"].budget_left, before - _db.ingredients["tomate"].cost)
    assert_eq(_events_of(res, "ingredient_added").size(), 1)

func test_add_ingredient_unknown_rejected():
    var s := _fresh()
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "licorne"})
    assert_eq(s.players["p0"].ingredients.size(), 0)
    assert_eq(_events_of(res, "intent_rejected").size(), 1)

func test_add_ingredient_over_budget_rejected():
    var s := _fresh()
    s.players["p0"].budget_left = 0
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "tomate"})
    assert_eq(s.players["p0"].ingredients.size(), 0)
    assert_eq(_events_of(res, "intent_rejected").size(), 1)

func test_remove_ingredient_refunds():
    var s := _fresh()
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "tomate"})
    var mid: int = s.players["p0"].budget_left
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.REMOVE_INGREDIENT, "index": 0})
    assert_eq(s.players["p0"].ingredients.size(), 0)
    assert_eq(s.players["p0"].budget_left, mid + _db.ingredients["tomate"].cost)

func test_add_action_respects_limit():
    var s := _fresh()
    var maxn: int = int(s.config["timeline_max"])
    for i in range(maxn):
        GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_ACTION, "action_id": "cuire"})
    assert_eq(s.players["p0"].timeline.size(), maxn)
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_ACTION, "action_id": "cuire"})
    assert_eq(s.players["p0"].timeline.size(), maxn)
    assert_eq(_events_of(res, "intent_rejected").size(), 1)

func test_set_ready():
    var s := _fresh()
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.SET_READY, "ready": true})
    assert_true(s.players["p0"].ready)

func test_bad_shape_rejected():
    var s := _fresh()
    var res := GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT})
    assert_eq(_events_of(res, "intent_rejected").size(), 1)

func test_unknown_player_rejected():
    var s := _fresh()
    var res := GameCore.apply_intent(_db, s, "p9", {"type": Intents.SET_READY, "ready": true})
    assert_eq(_events_of(res, "intent_rejected").size(), 1)
