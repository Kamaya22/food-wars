extends GutTest

func test_valid_content_loads():
    var res := ContentLoader.load_from_dict(ValidContent.make())
    assert_true(res.ok, "contenu valide doit charger ; erreurs: %s" % str(res.errors))
    assert_eq(res.db.ingredients.size(), 4)
    assert_eq(res.db.actions.size(), 3)
    assert_true(res.db.ingredients.has("tomate"))
    assert_eq(res.db.match_config.ingredient_budget, 10)

func test_duplicate_id_rejected():
    var raw := ValidContent.make()
    raw["ingredients"].append({"id": "tomate", "cost": 1})
    var res := ContentLoader.load_from_dict(raw)
    assert_false(res.ok)
    assert_true(_has_error(res, "tomate"), "l'erreur doit mentionner l'id dupliqué")

func test_negative_cost_rejected():
    var raw := ValidContent.make()
    raw["ingredients"][0]["cost"] = -5
    var res := ContentLoader.load_from_dict(raw)
    assert_false(res.ok)
    assert_true(_has_error(res, "cost"))

func test_contextual_card_bad_link_rejected():
    var raw := ValidContent.make()
    raw["cards"][1]["linked_action"] = "action_inexistante"
    var res := ContentLoader.load_from_dict(raw)
    assert_false(res.ok)
    assert_true(_has_error(res, "action_inexistante"))

func test_bad_event_window_rejected():
    var raw := ValidContent.make()
    raw["events"][0]["trigger_window"] = "midnight"
    var res := ContentLoader.load_from_dict(raw)
    assert_false(res.ok)
    assert_true(_has_error(res, "trigger_window"))

func test_deck_min_greater_than_cards_rejected():
    var raw := ValidContent.make()
    raw["match_config"]["deck_size"]["min"] = 99
    var res := ContentLoader.load_from_dict(raw)
    assert_false(res.ok)
    assert_true(_has_error(res, "deck_size"))

func test_non_dict_list_entry_rejected_without_crash():
    var raw := ValidContent.make()
    raw["ingredients"].append("pas_un_dict")
    var res := ContentLoader.load_from_dict(raw)
    assert_false(res.ok)
    assert_true(_has_error(res, "ingredient"), "l'erreur doit mentionner la categorie 'ingredient'")

func test_non_dict_match_config_rejected_without_crash():
    var raw := ValidContent.make()
    raw["match_config"] = "pas_un_objet"
    var res := ContentLoader.load_from_dict(raw)
    assert_false(res.ok)
    assert_true(_has_error(res, "match_config"), "l'erreur doit mentionner 'match_config'")

func test_non_positive_event_window_rejected():
    var raw := ValidContent.make()
    raw["match_config"]["event_frequency_window_sec"] = 0
    var res := ContentLoader.load_from_dict(raw)
    assert_false(res.ok)
    assert_true(_has_error(res, "event_frequency_window_sec"))

func _has_error(res, needle: String) -> bool:
    for e in res.errors:
        if String(e).findn(needle) != -1:
            return true
    return false
