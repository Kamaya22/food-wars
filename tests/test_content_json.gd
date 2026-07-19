extends GutTest

const TMP := "user://test_content.json"

func before_all():
    var raw := ValidContent.make()
    var f := FileAccess.open(TMP, FileAccess.WRITE)
    f.store_string(JSON.stringify(raw))
    f.close()

func test_load_from_json_file():
    var res := ContentLoader.load_from_json_file(TMP)
    assert_true(res.ok, "erreurs: %s" % str(res.errors))
    assert_eq(res.db.ingredients.size(), 4)

func test_missing_file_reports_error():
    var res := ContentLoader.load_from_json_file("user://n_existe_pas.json")
    assert_false(res.ok)
    assert_true(res.errors.size() > 0)

func test_malformed_json_reports_error():
    var f := FileAccess.open("user://bad.json", FileAccess.WRITE)
    f.store_string("{ pas du json")
    f.close()
    var res := ContentLoader.load_from_json_file("user://bad.json")
    assert_false(res.ok)
