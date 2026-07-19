extends GutTest

func test_valid_add_ingredient():
    var r := Intents.validate_shape({"type": Intents.ADD_INGREDIENT, "ingredient_id": "tomate"})
    assert_true(r.ok, r.error)

func test_valid_set_ready():
    assert_true(Intents.validate_shape({"type": Intents.SET_READY, "ready": true}).ok)

func test_valid_play_card_optional_target():
    assert_true(Intents.validate_shape({"type": Intents.PLAY_CARD, "card_id": "c1"}).ok)
    assert_true(Intents.validate_shape({"type": Intents.PLAY_CARD, "card_id": "c1", "target_player_id": "p1"}).ok)

func test_unknown_type_rejected():
    var r := Intents.validate_shape({"type": "voler_recette"})
    assert_false(r.ok)
    assert_true(r.error.length() > 0)

func test_missing_payload_rejected():
    assert_false(Intents.validate_shape({"type": Intents.ADD_INGREDIENT}).ok)
    assert_false(Intents.validate_shape({"type": Intents.REMOVE_ACTION, "index": "pas_un_int"}).ok)
    assert_false(Intents.validate_shape({"type": Intents.SET_READY, "ready": "oui"}).ok)

func test_non_dict_or_missing_type_rejected():
    assert_false(Intents.validate_shape({}).ok)
