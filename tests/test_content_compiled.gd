extends GutTest

const PATH := "res://content/compiled/content.json"

func test_real_compiled_content_is_valid():
    if not FileAccess.file_exists(PATH):
        pending("content.json non généré — lancer python scripts/build_content.py")
        return
    var res := ContentLoader.load_from_json_file(PATH)
    assert_true(res.ok, "le contenu authored reel doit etre valide ; erreurs: %s" % str(res.errors))
    assert_true(res.db.ingredients.has("tomate"), "l'ingredient 'tomate' doit exister")
    assert_true(res.db.cards.has("card_saboter"), "la carte 'card_saboter' doit exister")
    # ok == true implique deja que linked_action de card_saboter a ete resolu par _validate.
