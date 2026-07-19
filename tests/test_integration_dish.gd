extends GutTest

var _db: ContentDB

func before_all():
    var res := ContentLoader.load_from_dict(ValidContent.make())
    assert_true(res.ok, "le contenu de fixture doit être valide : %s" % str(res.errors))
    _db = res.db

func _ings(ids: Array) -> Array:
    var out := []
    for id in ids:
        out.append(_db.ingredients[id])
    return out

func _acts(ids: Array) -> Array:
    var out := []
    for id in ids:
        out.append(_db.actions[id])
    return out

func _criteria() -> Array:
    return _db.criteria.values()

func test_full_chain_content_to_winner():
    # Joueur A : bœuf + tomate, cuit et assaisonné → riche en umami
    var dish_a := StatEngine.compute_dish(_ings(["boeuf", "tomate"]), _acts(["cuire", "assaisonner"]))
    # Joueur B : citron + sucre, mixé → acide/sucré, peu d'umami
    var dish_b := StatEngine.compute_dish(_ings(["citron", "sucre"]), _acts(["mixer"]))

    var verdict := JudgmentEngine.judge(dish_a, dish_b, _criteria())
    # Les critères notent umami (1.5) et gras (0.5) → A doit gagner
    assert_eq(verdict["winner"], "a",
        "A (umami/gras) doit battre B ; a=%.1f b=%.1f" % [verdict["score_a"], verdict["score_b"]])

func test_chain_is_deterministic():
    var d1 := StatEngine.compute_dish(_ings(["boeuf", "tomate"]), _acts(["cuire"]))
    var d2 := StatEngine.compute_dish(_ings(["boeuf", "tomate"]), _acts(["cuire"]))
    assert_eq(d1, d2, "mêmes entrées → même plat")
