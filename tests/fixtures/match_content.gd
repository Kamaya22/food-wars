class_name MatchContent
extends RefCounted

static func db() -> ContentDB:
    var res := ContentLoader.load_from_dict(ValidContent.make())
    assert(res.ok, "fixture de contenu invalide: %s" % str(res.errors))
    return res.db
