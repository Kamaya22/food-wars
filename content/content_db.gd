class_name ContentDB
extends RefCounted

var ingredients: Dictionary = {}   # id -> IngredientRes
var actions: Dictionary = {}       # id -> ActionRes
var cards: Dictionary = {}         # id -> CardRes
var events: Dictionary = {}        # id -> EventRes
var criteria: Dictionary = {}      # id -> CriterionRes
var match_config: MatchConfigRes = null
