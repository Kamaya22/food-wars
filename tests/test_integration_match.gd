extends GutTest

var _db: ContentDB

func before_all():
    _db = MatchContent.db()

# Joue un match scripté et renvoie le GameState final.
func _play(seed: int) -> GameState:
    var s := GameCore.start_match(_db, _db.match_config, seed, ["p0", "p1"])
    # --- PLANNING : chaque joueur pose des ingrédients + actions, puis se déclare prêt ---
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "boeuf"})
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "tomate"})
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_ACTION, "action_id": "cuire"})
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.ADD_ACTION, "action_id": "assaisonner"})
    GameCore.apply_intent(_db, s, "p1", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "citron"})
    GameCore.apply_intent(_db, s, "p1", {"type": Intents.ADD_INGREDIENT, "ingredient_id": "sucre"})
    GameCore.apply_intent(_db, s, "p1", {"type": Intents.ADD_ACTION, "action_id": "mixer"})
    GameCore.apply_intent(_db, s, "p0", {"type": Intents.SET_READY, "ready": true})
    GameCore.apply_intent(_db, s, "p1", {"type": Intents.SET_READY, "ready": true})
    assert_eq(s.phase, GameState.Phase.EXECUTION, "les deux prêts → exécution")
    # --- EXECUTION + JUDGMENT : on tick jusqu'à la fin du match ---
    var guard := 0
    while s.phase != GameState.Phase.FINISHED and guard < 100000:
        GameCore.tick(_db, s, 1.0)
        guard += 1
    assert_ne(s.phase, GameState.Phase.EXECUTION, "le match doit se terminer")
    return s

func test_full_match_produces_winner():
    var s := _play(2024)
    assert_eq(s.phase, GameState.Phase.FINISHED)
    assert_true(s.result.has("winner"))
    # p0 (boeuf/tomate, cuit+assaisonné → umami/gras) doit battre p1 (citron/sucre, mixé)
    assert_eq(s.result["winner"], "p0",
        "scores=%s" % str(s.result["scores"]))

func test_match_is_deterministic():
    var a := _play(2024)
    var b := _play(2024)
    assert_eq(a.to_dict(), b.to_dict(), "même seed + même script → même état final")

func test_view_never_leaks_opponent_hand_during_match():
    var s := GameCore.start_match(_db, _db.match_config, 7, ["p0", "p1"])
    var view := GameCore.get_view(_db, s, "p0")
    assert_false(view.opponents["p1"].has("hand"))
