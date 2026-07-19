extends GutTest

func test_ingredient_from_dict():
    var r := IngredientRes.from_dict({
        "id": "tomate", "name": "Tomate", "cost": 2,
        "stats": {"umami": 3, "acide": 4}, "tags": ["legume", "frais"]})
    assert_eq(r.id, "tomate")
    assert_eq(r.display_name, "Tomate")
    assert_eq(r.cost, 2)
    assert_eq(int(r.stats["acide"]), 4)
    assert_eq(int(r.stats["gras"]), 0, "stats absentes = 0")
    assert_true(r.tags.has("frais"))

func test_ingredient_name_defaults_to_id():
    var r := IngredientRes.from_dict({"id": "sel", "cost": 0})
    assert_eq(r.display_name, "sel")

func test_action_from_dict():
    var r := ActionRes.from_dict({
        "id": "cuire", "name": "Cuire", "base_duration_sec": 45,
        "effect": {"stats": {"umami": 2, "acide": -1}}})
    assert_eq(r.id, "cuire")
    assert_eq(r.base_duration_sec, 45)
    assert_eq(int(r.effect["stats"]["umami"]), 2)

func test_card_enums_parse():
    var g := CardRes.from_dict({"id": "c1", "type": "global", "target": "opponent", "effect": {}})
    assert_eq(g.type, CardRes.Type.GLOBAL)
    assert_eq(g.target, CardRes.Target.OPPONENT)
    assert_eq(g.linked_action, "")
    var c := CardRes.from_dict({"id": "c2", "type": "contextual", "linked_action": "cuire", "effect": {}})
    assert_eq(c.type, CardRes.Type.CONTEXTUAL)
    assert_eq(c.target, CardRes.Target.SELF, "target par défaut = self")
    assert_eq(c.linked_action, "cuire")

func test_event_from_dict():
    var r := EventRes.from_dict({"id": "e1", "name": "Coupure", "trigger_window": "execution", "effect": {"rule": "stop_oven_seconds", "value": 5}})
    assert_eq(r.trigger_window, "execution")
    assert_eq(r.effect["rule"], "stop_oven_seconds")

func test_criterion_from_dict():
    var r := CriterionRes.from_dict({"id": "umami", "weight": 1.5, "note": "clé"})
    assert_almost_eq(r.weight, 1.5, 0.001)

func test_match_config_from_dict():
    var r := MatchConfigRes.from_dict({
        "ingredient_budget": 10,
        "ingredients_per_player": {"min": 3, "max": 6},
        "timeline_actions": {"min": 5, "max": 6},
        "deck_size": {"min": 15, "max": 20},
        "starting_hand_size": 4,
        "phase_durations": {"planning": 150, "execution": 330, "judgment": 60},
        "event_frequency_window_sec": 240})
    assert_eq(r.ingredient_budget, 10)
    assert_eq(r.ingredients_per_player_max, 6)
    assert_eq(r.deck_size_min, 15)
    assert_eq(r.phase_execution_sec, 330)
    assert_eq(r.event_frequency_window_sec, 240)
