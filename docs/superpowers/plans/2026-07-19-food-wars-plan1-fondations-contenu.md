# Food Wars — Plan 1 : Fondations données & calcul de plat

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Poser la fondation headless et déterministe du jeu : charger le contenu (ingrédients / actions / cartes / événements / critères / config) avec validation stricte, calculer les stats d'un plat à partir d'ingrédients et d'actions, et juger deux plats pour désigner un vainqueur — le tout testable sans lancer de rendu ni de réseau.

**Architecture:** Couche **Contenu** (Resources typées chargées depuis JSON via `ContentLoader` → `ContentDB` injecté) + amorce de la couche **Cœur** pur (`Stats`, `Rng`, `StatEngine`, `JudgmentEngine`). Aucun de ces modules ne référence de nœud Godot lié au rendu : ils tournent en headless et sont pilotés par GUT. C'est le socle réutilisé tel quel côté serveur lors de la future migration (voir spec §2).

**Tech Stack:** Godot 4 (GDScript uniquement), GUT (Godot Unit Test) pour les tests headless, Python 3 + PyYAML pour l'outil d'authoring YAML→JSON (build-time uniquement, hors runtime).

## Global Constraints

- **Moteur** : Godot 4.x, **GDScript uniquement** (aucun C#, aucune GDExtension).
- **Pureté du Cœur** : les fichiers sous `core/` et `content/` ne référencent **jamais** `Node`, `Node2D`, `Control`, `get_tree()`, `Sprite`, ni aucune API de rendu/scène. Uniquement `RefCounted`, `Resource`, et types de données.
- **Déterminisme** : aucun appel à `randi()`/`randf()` globaux. Tout aléa passe par une instance `Rng` seedée et injectée. Même seed + mêmes entrées = même résultat.
- **Clés de stats figées** : exactement `["umami", "sucre", "acide", "gras", "amer", "texture"]` (dans cet ordre). Défini une seule fois dans `core/stats.gd`, jamais dupliqué.
- **Contenu** : authoring en YAML sous `content/source/`, compilé en JSON sous `content/compiled/`. Le **runtime ne lit que du JSON**. Les **tests** injectent des dictionnaires en mémoire (`load_from_dict`) et ne dépendent d'aucun fichier.
- **Tests** : GUT, exécutés en headless. Un test échoue bruyamment ; le contenu invalide est refusé au chargement, jamais toléré.
- **Nommage** : fichiers en `snake_case.gd` ; classes en `PascalCase` via `class_name`.

---

## Structure de fichiers

| Fichier | Responsabilité |
|---|---|
| `project.godot` | Projet Godot minimal, headless-compatible |
| `core/stats.gd` | `Stats` — clés de stats + helpers purs (empty/add/clamp) |
| `core/rng.gd` | `Rng` — générateur seedé déterministe injectable |
| `content/resources/ingredient_res.gd` | `IngredientRes` — donnée typée + `from_dict` |
| `content/resources/action_res.gd` | `ActionRes` |
| `content/resources/card_res.gd` | `CardRes` (+ enums Type/Target) |
| `content/resources/event_res.gd` | `EventRes` |
| `content/resources/criterion_res.gd` | `CriterionRes` |
| `content/resources/match_config_res.gd` | `MatchConfigRes` |
| `content/content_db.gd` | `ContentDB` — registres en lecture seule |
| `content/content_loader.gd` | `ContentLoader` — parse + valide + résout les refs |
| `core/systems/stat_engine.gd` | `StatEngine` — effets sur stats, calcul de plat |
| `core/systems/judgment_engine.gd` | `JudgmentEngine` — score pondéré + vainqueur |
| `scripts/build_content.py` | Outil authoring YAML→JSON (build-time) |
| `content/source/*.yaml` | Contenu éditable à la main |
| `content/compiled/content.json` | Contenu compilé chargé par le runtime |
| `tests/*.gd` | Suites GUT |
| `tests/fixtures/valid_content.gd` | Fixture partagée : un dict de contenu valide minimal |

---

### Task 1 : Squelette de projet + GUT + test sanity

**Files:**
- Create: `project.godot`
- Create: `.gitattributes`
- Create: `tests/test_sanity.gd`

**Interfaces:**
- Consumes: rien.
- Produces: un projet Godot exécutable en headless et une commande GUT qui tourne.

- [ ] **Step 1 : Installer GUT**

GUT n'est pas versionné dans le dépôt (dossier `addons/`). L'installer une fois localement :

```bash
cd "<repo-root>"
git clone --depth 1 https://github.com/bitwes/Gut.git /tmp/gut
mkdir -p addons
cp -r /tmp/gut/addons/gut addons/gut
```

- [ ] **Step 2 : Créer `project.godot`**

```ini
config_version=5

[application]
config/name="Food Wars"
config/features=PackedStringArray("4.5")
run/main_scene=""

[editor_plugins]
enabled=PackedStringArray("res://addons/gut/plugin.cfg")
```

- [ ] **Step 3 : Créer `.gitattributes`** (normalise les fins de ligne, évite le bruit LF/CRLF sous Windows)

```
* text=auto eol=lf
*.gd text eol=lf
*.py text eol=lf
```

- [ ] **Step 4 : Écrire le test sanity**

Fichier `tests/test_sanity.gd` :

```gdscript
extends GutTest

func test_gut_runs():
    assert_eq(1 + 1, 2, "GUT doit exécuter les tests")
```

- [ ] **Step 5 : Lancer le test et vérifier qu'il passe**

Run :
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```
Expected : sortie GUT indiquant `1 passing (0 failing)`.

- [ ] **Step 6 : Ajouter GUT au `.gitignore` puis commit**

Ajouter la ligne `addons/gut/` au `.gitignore` existant (GUT est un outil, pas du code produit).

```bash
git add .gitignore project.godot .gitattributes tests/test_sanity.gd
git commit -m "chore: squelette projet Godot 4 + GUT headless"
```

---

### Task 2 : `Stats` — clés et helpers purs

**Files:**
- Create: `core/stats.gd`
- Test: `tests/test_stats.gd`

**Interfaces:**
- Consumes: rien.
- Produces:
  - `Stats.KEYS: Array` — `["umami","sucre","acide","gras","amer","texture"]`
  - `Stats.empty() -> Dictionary` — dict avec chaque clé à `0`
  - `Stats.add(a: Dictionary, b: Dictionary) -> Dictionary` — somme clé à clé, nouveau dict
  - `Stats.clamp_stats(s: Dictionary, lo: int, hi: int) -> Dictionary` — borne chaque clé

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_stats.gd` :

```gdscript
extends GutTest

func test_empty_has_all_keys_at_zero():
    var e := Stats.empty()
    assert_eq(e.size(), 6, "6 clés de stats")
    for k in Stats.KEYS:
        assert_eq(int(e[k]), 0, "%s doit valoir 0" % k)

func test_add_sums_key_by_key():
    var a := {"umami": 2, "gras": 1}
    var b := {"umami": 3, "acide": 4}
    var r := Stats.add(a, b)
    assert_eq(int(r["umami"]), 5)
    assert_eq(int(r["gras"]), 1)
    assert_eq(int(r["acide"]), 4)
    assert_eq(int(r["amer"]), 0, "clé absente = 0")

func test_add_does_not_mutate_inputs():
    var a := Stats.empty()
    var b := {"umami": 5}
    Stats.add(a, b)
    assert_eq(int(a["umami"]), 0, "l'entrée ne doit pas être modifiée")

func test_clamp_bounds_each_key():
    var s := {"umami": 99, "acide": -99}
    var r := Stats.clamp_stats(s, -10, 10)
    assert_eq(int(r["umami"]), 10)
    assert_eq(int(r["acide"]), -10)
```

- [ ] **Step 2 : Lancer le test, vérifier l'échec**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_stats.gd -gexit`
Expected : FAIL — `Stats` non défini.

- [ ] **Step 3 : Implémenter `core/stats.gd`**

```gdscript
class_name Stats
extends RefCounted

const KEYS: Array = ["umami", "sucre", "acide", "gras", "amer", "texture"]

static func empty() -> Dictionary:
    var d: Dictionary = {}
    for k in KEYS:
        d[k] = 0
    return d

static func add(a: Dictionary, b: Dictionary) -> Dictionary:
    var out: Dictionary = empty()
    for k in KEYS:
        out[k] = int(a.get(k, 0)) + int(b.get(k, 0))
    return out

static func clamp_stats(s: Dictionary, lo: int, hi: int) -> Dictionary:
    var out: Dictionary = empty()
    for k in KEYS:
        out[k] = clampi(int(s.get(k, 0)), lo, hi)
    return out
```

- [ ] **Step 4 : Lancer le test, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_stats.gd -gexit`
Expected : PASS (4 tests).

- [ ] **Step 5 : Commit**

```bash
git add core/stats.gd tests/test_stats.gd
git commit -m "feat(core): Stats — clés figées et helpers purs"
```

---

### Task 3 : `Rng` — générateur seedé déterministe

**Files:**
- Create: `core/rng.gd`
- Test: `tests/test_rng.gd`

**Interfaces:**
- Consumes: rien.
- Produces:
  - `Rng.new(seed_value: int)` — construit un générateur seedé
  - `Rng.randi_range(from: int, to: int) -> int`
  - `Rng.randf() -> float`
  - `Rng.get_state() -> int` / `Rng.set_state(state: int) -> void` — pour sérialiser l'état (utile Plan 2)

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_rng.gd` :

```gdscript
extends GutTest

func test_same_seed_same_sequence():
    var a := Rng.new(42)
    var b := Rng.new(42)
    for i in range(20):
        assert_eq(a.randi_range(0, 1000), b.randi_range(0, 1000),
            "même seed doit produire la même séquence")

func test_different_seed_diverges():
    var a := Rng.new(1)
    var b := Rng.new(2)
    var same := true
    for i in range(20):
        if a.randi_range(0, 1000000) != b.randi_range(0, 1000000):
            same = false
    assert_false(same, "des seeds différents doivent diverger")

func test_state_roundtrip_resumes_sequence():
    var a := Rng.new(7)
    a.randi_range(0, 100)
    var snapshot := a.get_state()
    var next_a := a.randi_range(0, 100)
    var b := Rng.new(999)
    b.set_state(snapshot)
    assert_eq(b.randi_range(0, 100), next_a, "restaurer l'état reprend la séquence")
```

- [ ] **Step 2 : Lancer le test, vérifier l'échec**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_rng.gd -gexit`
Expected : FAIL — `Rng` non défini.

- [ ] **Step 3 : Implémenter `core/rng.gd`**

```gdscript
class_name Rng
extends RefCounted

var _rng: RandomNumberGenerator

func _init(seed_value: int) -> void:
    _rng = RandomNumberGenerator.new()
    _rng.seed = seed_value

func randi_range(from: int, to: int) -> int:
    return _rng.randi_range(from, to)

func randf() -> float:
    return _rng.randf()

func get_state() -> int:
    return int(_rng.state)

func set_state(state: int) -> void:
    _rng.state = state
```

- [ ] **Step 4 : Lancer le test, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_rng.gd -gexit`
Expected : PASS (3 tests).

- [ ] **Step 5 : Commit**

```bash
git add core/rng.gd tests/test_rng.gd
git commit -m "feat(core): Rng seedé déterministe avec sérialisation d'état"
```

---

### Task 4 : Classes de ressources typées

**Files:**
- Create: `content/resources/ingredient_res.gd`
- Create: `content/resources/action_res.gd`
- Create: `content/resources/card_res.gd`
- Create: `content/resources/event_res.gd`
- Create: `content/resources/criterion_res.gd`
- Create: `content/resources/match_config_res.gd`
- Test: `tests/test_resources.gd`

**Interfaces:**
- Consumes: `Stats` (Task 2).
- Produces (chaque classe expose un `static from_dict(d: Dictionary) -> <Class>`) :
  - `IngredientRes` : `id: String`, `display_name: String`, `cost: int`, `stats: Dictionary`, `tags: PackedStringArray`
  - `ActionRes` : `id: String`, `display_name: String`, `base_duration_sec: int`, `effect: Dictionary`
  - `CardRes` : `id: String`, `display_name: String`, `type: CardRes.Type`, `target: CardRes.Target`, `linked_action: String` (`""` si aucune), `effect: Dictionary` ; enums `Type { GLOBAL, CONTEXTUAL }`, `Target { SELF, OPPONENT }`
  - `EventRes` : `id: String`, `display_name: String`, `trigger_window: String`, `effect: Dictionary`
  - `CriterionRes` : `id: String`, `weight: float`, `note: String`
  - `MatchConfigRes` : `ingredient_budget: int`, `ingredients_per_player_min/max: int`, `timeline_actions_min/max: int`, `deck_size_min/max: int`, `starting_hand_size: int`, `phase_planning_sec: int`, `phase_execution_sec: int`, `phase_judgment_sec: int`, `event_frequency_window_sec: int`

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_resources.gd` :

```gdscript
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
```

- [ ] **Step 2 : Lancer le test, vérifier l'échec**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_resources.gd -gexit`
Expected : FAIL — classes non définies.

- [ ] **Step 3 : Implémenter les 6 fichiers de ressources**

`content/resources/ingredient_res.gd` :
```gdscript
class_name IngredientRes
extends Resource

var id: String
var display_name: String
var cost: int
var stats: Dictionary
var tags: PackedStringArray

static func from_dict(d: Dictionary) -> IngredientRes:
    var r := IngredientRes.new()
    r.id = String(d.get("id", ""))
    r.display_name = String(d.get("name", r.id))
    r.cost = int(d.get("cost", 0))
    r.stats = Stats.clamp_stats(d.get("stats", {}), -99, 99)
    r.tags = PackedStringArray(d.get("tags", []))
    return r
```

`content/resources/action_res.gd` :
```gdscript
class_name ActionRes
extends Resource

var id: String
var display_name: String
var base_duration_sec: int
var effect: Dictionary

static func from_dict(d: Dictionary) -> ActionRes:
    var r := ActionRes.new()
    r.id = String(d.get("id", ""))
    r.display_name = String(d.get("name", r.id))
    r.base_duration_sec = int(d.get("base_duration_sec", 0))
    r.effect = d.get("effect", {})
    return r
```

`content/resources/card_res.gd` :
```gdscript
class_name CardRes
extends Resource

enum Type { GLOBAL, CONTEXTUAL }
enum Target { SELF, OPPONENT }

var id: String
var display_name: String
var type: Type
var target: Target
var linked_action: String
var effect: Dictionary

static func from_dict(d: Dictionary) -> CardRes:
    var r := CardRes.new()
    r.id = String(d.get("id", ""))
    r.display_name = String(d.get("name", r.id))
    r.type = Type.CONTEXTUAL if String(d.get("type", "global")) == "contextual" else Type.GLOBAL
    r.target = Target.OPPONENT if String(d.get("target", "self")) == "opponent" else Target.SELF
    r.linked_action = String(d.get("linked_action", ""))
    r.effect = d.get("effect", {})
    return r
```

`content/resources/event_res.gd` :
```gdscript
class_name EventRes
extends Resource

var id: String
var display_name: String
var trigger_window: String
var effect: Dictionary

static func from_dict(d: Dictionary) -> EventRes:
    var r := EventRes.new()
    r.id = String(d.get("id", ""))
    r.display_name = String(d.get("name", r.id))
    r.trigger_window = String(d.get("trigger_window", ""))
    r.effect = d.get("effect", {})
    return r
```

`content/resources/criterion_res.gd` :
```gdscript
class_name CriterionRes
extends Resource

var id: String
var weight: float
var note: String

static func from_dict(d: Dictionary) -> CriterionRes:
    var r := CriterionRes.new()
    r.id = String(d.get("id", ""))
    r.weight = float(d.get("weight", 1.0))
    r.note = String(d.get("note", ""))
    return r
```

`content/resources/match_config_res.gd` :
```gdscript
class_name MatchConfigRes
extends Resource

var ingredient_budget: int
var ingredients_per_player_min: int
var ingredients_per_player_max: int
var timeline_actions_min: int
var timeline_actions_max: int
var deck_size_min: int
var deck_size_max: int
var starting_hand_size: int
var phase_planning_sec: int
var phase_execution_sec: int
var phase_judgment_sec: int
var event_frequency_window_sec: int

static func from_dict(d: Dictionary) -> MatchConfigRes:
    var r := MatchConfigRes.new()
    r.ingredient_budget = int(d.get("ingredient_budget", 0))
    var ipp: Dictionary = d.get("ingredients_per_player", {})
    r.ingredients_per_player_min = int(ipp.get("min", 0))
    r.ingredients_per_player_max = int(ipp.get("max", 0))
    var ta: Dictionary = d.get("timeline_actions", {})
    r.timeline_actions_min = int(ta.get("min", 0))
    r.timeline_actions_max = int(ta.get("max", 0))
    var ds: Dictionary = d.get("deck_size", {})
    r.deck_size_min = int(ds.get("min", 0))
    r.deck_size_max = int(ds.get("max", 0))
    r.starting_hand_size = int(d.get("starting_hand_size", 0))
    var pd: Dictionary = d.get("phase_durations", {})
    r.phase_planning_sec = int(pd.get("planning", 0))
    r.phase_execution_sec = int(pd.get("execution", 0))
    r.phase_judgment_sec = int(pd.get("judgment", 0))
    r.event_frequency_window_sec = int(d.get("event_frequency_window_sec", 0))
    return r
```

- [ ] **Step 4 : Lancer le test, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_resources.gd -gexit`
Expected : PASS (7 tests).

- [ ] **Step 5 : Commit**

```bash
git add content/resources tests/test_resources.gd
git commit -m "feat(content): ressources typées avec from_dict"
```

---

### Task 5 : `ContentDB` + `ContentLoader` avec validation

**Files:**
- Create: `content/content_db.gd`
- Create: `content/content_loader.gd`
- Create: `tests/fixtures/valid_content.gd`
- Test: `tests/test_content_loader.gd`

**Interfaces:**
- Consumes: toutes les ressources (Task 4), `Stats` (Task 2).
- Produces:
  - `ContentDB` : `ingredients: Dictionary` (id→`IngredientRes`), `actions`, `cards`, `events`, `criteria` (id→`CriterionRes`), `match_config: MatchConfigRes`.
  - `ContentLoader.load_from_dict(raw: Dictionary) -> ContentLoader.LoadResult`
  - `ContentLoader.LoadResult` : `ok: bool`, `db: ContentDB`, `errors: PackedStringArray`
  - Fixture `ValidContent.make() -> Dictionary` : un contenu brut valide minimal.

Le format `raw` attendu :
```
{
  "ingredients": [ {..}, .. ],
  "actions":     [ {..}, .. ],
  "cards":       [ {..}, .. ],
  "events":      [ {..}, .. ],
  "criteria":    [ {..}, .. ],
  "match_config": { .. }
}
```

Règles de validation (échec = `ok=false` + message dans `errors`, tiré de spec §5) :
1. `id` présent et unique dans chaque catégorie.
2. `cost` d'un ingrédient ≥ 0.
3. Une carte `CONTEXTUAL` doit avoir un `linked_action` référençant une action existante.
4. Le `trigger_window` d'un événement ∈ `{planning, execution, judgment}`.
5. `deck_size.min` ≤ nombre de cartes définies.
6. Un critère doit avoir un `weight` numérique (déjà garanti par `from_dict`) et un `id` non vide.

- [ ] **Step 1 : Écrire la fixture partagée**

Fichier `tests/fixtures/valid_content.gd` :

```gdscript
class_name ValidContent
extends RefCounted

# Contenu brut minimal mais VALIDE, réutilisé par plusieurs suites.
static func make() -> Dictionary:
    return {
        "ingredients": [
            {"id": "tomate", "name": "Tomate", "cost": 2, "stats": {"umami": 3, "acide": 4}, "tags": ["legume"]},
            {"id": "boeuf", "name": "Bœuf", "cost": 3, "stats": {"umami": 5, "gras": 3}, "tags": ["viande"]},
            {"id": "sucre", "name": "Sucre", "cost": 1, "stats": {"sucre": 6}, "tags": ["base"]},
            {"id": "citron", "name": "Citron", "cost": 1, "stats": {"acide": 5}, "tags": ["fruit"]},
        ],
        "actions": [
            {"id": "cuire", "name": "Cuire", "base_duration_sec": 45, "effect": {"stats": {"umami": 2, "acide": -1}}},
            {"id": "mixer", "name": "Mixer", "base_duration_sec": 20, "effect": {"stats": {"texture": 3}}},
            {"id": "assaisonner", "name": "Assaisonner", "base_duration_sec": 15, "effect": {"stats": {"umami": 1, "sucre": 1}}},
        ],
        "cards": [
            {"id": "card_boost_umami", "name": "Umami+", "type": "global", "target": "self", "effect": {"stats": {"umami": 2}}},
            {"id": "card_saboter", "name": "Sabotage", "type": "contextual", "target": "opponent", "linked_action": "cuire", "effect": {"stats": {"acide": 2}}},
        ],
        "events": [
            {"id": "coupure", "name": "Coupure de courant", "trigger_window": "execution", "effect": {"rule": "stop_oven_seconds", "value": 5}},
        ],
        "criteria": [
            {"id": "umami", "weight": 1.5},
            {"id": "gras", "weight": 0.5},
        ],
        "match_config": {
            "ingredient_budget": 10,
            "ingredients_per_player": {"min": 3, "max": 6},
            "timeline_actions": {"min": 5, "max": 6},
            "deck_size": {"min": 2, "max": 20},
            "starting_hand_size": 2,
            "phase_durations": {"planning": 150, "execution": 330, "judgment": 60},
            "event_frequency_window_sec": 240,
        },
    }
```

- [ ] **Step 2 : Écrire le test qui échoue**

Fichier `tests/test_content_loader.gd` :

```gdscript
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

func _has_error(res, needle: String) -> bool:
    for e in res.errors:
        if String(e).findn(needle) != -1:
            return true
    return false
```

- [ ] **Step 3 : Lancer le test, vérifier l'échec**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_content_loader.gd -gexit`
Expected : FAIL — `ContentLoader` / `ContentDB` / `ValidContent` non définis.

- [ ] **Step 4 : Implémenter `content/content_db.gd`**

```gdscript
class_name ContentDB
extends RefCounted

var ingredients: Dictionary = {}   # id -> IngredientRes
var actions: Dictionary = {}       # id -> ActionRes
var cards: Dictionary = {}         # id -> CardRes
var events: Dictionary = {}        # id -> EventRes
var criteria: Dictionary = {}      # id -> CriterionRes
var match_config: MatchConfigRes = null
```

- [ ] **Step 5 : Implémenter `content/content_loader.gd`**

```gdscript
class_name ContentLoader
extends RefCounted

class LoadResult:
    var ok: bool = false
    var db: ContentDB = null
    var errors: PackedStringArray = PackedStringArray()

static func load_from_dict(raw: Dictionary) -> LoadResult:
    var result := LoadResult.new()
    var db := ContentDB.new()
    var errors := PackedStringArray()

    _load_list(raw.get("ingredients", []), db.ingredients,
        func(d): return IngredientRes.from_dict(d), "ingredient", errors)
    _load_list(raw.get("actions", []), db.actions,
        func(d): return ActionRes.from_dict(d), "action", errors)
    _load_list(raw.get("cards", []), db.cards,
        func(d): return CardRes.from_dict(d), "card", errors)
    _load_list(raw.get("events", []), db.events,
        func(d): return EventRes.from_dict(d), "event", errors)
    _load_list(raw.get("criteria", []), db.criteria,
        func(d): return CriterionRes.from_dict(d), "criterion", errors)

    if raw.has("match_config"):
        db.match_config = MatchConfigRes.from_dict(raw["match_config"])
    else:
        errors.append("match_config manquant")

    _validate(db, errors)

    result.db = db
    result.errors = errors
    result.ok = errors.is_empty()
    return result

static func _load_list(items: Array, out: Dictionary, factory: Callable, kind: String, errors: PackedStringArray) -> void:
    for d in items:
        var id := String(d.get("id", ""))
        if id == "":
            errors.append("%s sans id" % kind)
            continue
        if out.has(id):
            errors.append("%s : id dupliqué '%s'" % [kind, id])
            continue
        out[id] = factory.call(d)

static func _validate(db: ContentDB, errors: PackedStringArray) -> void:
    # Coût des ingrédients >= 0
    for id in db.ingredients:
        var ing: IngredientRes = db.ingredients[id]
        if ing.cost < 0:
            errors.append("ingredient '%s' : cost negatif (%d)" % [id, ing.cost])

    # Cartes contextuelles : linked_action doit exister
    for id in db.cards:
        var c: CardRes = db.cards[id]
        if c.type == CardRes.Type.CONTEXTUAL:
            if c.linked_action == "" or not db.actions.has(c.linked_action):
                errors.append("card '%s' : linked_action '%s' introuvable" % [id, c.linked_action])

    # Fenêtre de déclenchement des événements
    var valid_windows := ["planning", "execution", "judgment"]
    for id in db.events:
        var e: EventRes = db.events[id]
        if not valid_windows.has(e.trigger_window):
            errors.append("event '%s' : trigger_window invalide '%s'" % [id, e.trigger_window])

    # deck_size.min <= nombre de cartes définies
    if db.match_config != null:
        if db.match_config.deck_size_min > db.cards.size():
            errors.append("match_config : deck_size.min (%d) > cartes definies (%d)" % [db.match_config.deck_size_min, db.cards.size()])
```

- [ ] **Step 6 : Lancer le test, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_content_loader.gd -gexit`
Expected : PASS (6 tests).

- [ ] **Step 7 : Commit**

```bash
git add content/content_db.gd content/content_loader.gd tests/fixtures/valid_content.gd tests/test_content_loader.gd
git commit -m "feat(content): ContentLoader avec validation stricte + ContentDB"
```

---

### Task 6 : Chargement JSON depuis fichier + contenu seed + convertisseur YAML→JSON

**Files:**
- Modify: `content/content_loader.gd` (ajout de `load_from_json_file`)
- Create: `content/source/ingredients.yaml`
- Create: `content/source/actions.yaml`
- Create: `content/source/cards.yaml`
- Create: `content/source/events.yaml`
- Create: `content/source/criteria.yaml`
- Create: `content/source/match_config.yaml`
- Create: `scripts/build_content.py`
- Test: `tests/test_content_json.gd`

**Interfaces:**
- Consumes: `ContentLoader.load_from_dict` (Task 5).
- Produces:
  - `ContentLoader.load_from_json_file(path: String) -> ContentLoader.LoadResult` (lit un JSON, délègue à `load_from_dict`).
  - `content/compiled/content.json` généré par `scripts/build_content.py`.

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_content_json.gd` :

```gdscript
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
```

- [ ] **Step 2 : Lancer le test, vérifier l'échec**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_content_json.gd -gexit`
Expected : FAIL — `load_from_json_file` non défini.

- [ ] **Step 3 : Ajouter `load_from_json_file` à `content/content_loader.gd`**

Ajouter cette méthode statique dans la classe `ContentLoader` :

```gdscript
static func load_from_json_file(path: String) -> LoadResult:
    if not FileAccess.file_exists(path):
        var r := LoadResult.new()
        r.db = ContentDB.new()
        r.errors.append("fichier introuvable : %s" % path)
        return r
    var text := FileAccess.get_file_as_string(path)
    var parsed = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        var r := LoadResult.new()
        r.db = ContentDB.new()
        r.errors.append("JSON invalide dans : %s" % path)
        return r
    return load_from_dict(parsed)
```

- [ ] **Step 4 : Lancer le test, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_content_json.gd -gexit`
Expected : PASS (3 tests).

- [ ] **Step 5 : Créer les fichiers source YAML**

`content/source/ingredients.yaml` :
```yaml
- id: tomate
  name: Tomate
  cost: 2
  stats: {umami: 3, acide: 4}
  tags: [legume, frais]
- id: boeuf
  name: Bœuf
  cost: 3
  stats: {umami: 5, gras: 3}
  tags: [viande]
- id: sucre
  name: Sucre
  cost: 1
  stats: {sucre: 6}
  tags: [base]
- id: citron
  name: Citron
  cost: 1
  stats: {acide: 5}
  tags: [fruit]
```

`content/source/actions.yaml` :
```yaml
- id: cuire
  name: Cuire
  base_duration_sec: 45
  effect: {stats: {umami: 2, acide: -1}}
- id: mixer
  name: Mixer
  base_duration_sec: 20
  effect: {stats: {texture: 3}}
- id: assaisonner
  name: Assaisonner
  base_duration_sec: 15
  effect: {stats: {umami: 1, sucre: 1}}
```

`content/source/cards.yaml` :
```yaml
- id: card_boost_umami
  name: Umami+
  type: global
  target: self
  effect: {stats: {umami: 2}}
- id: card_saboter
  name: Sabotage
  type: contextual
  target: opponent
  linked_action: cuire
  effect: {stats: {acide: 2}}
```

`content/source/events.yaml` :
```yaml
- id: coupure
  name: Coupure de courant
  trigger_window: execution
  effect: {rule: stop_oven_seconds, value: 5}
```

`content/source/criteria.yaml` :
```yaml
- id: umami
  weight: 1.5
- id: gras
  weight: 0.5
```

`content/source/match_config.yaml` :
```yaml
ingredient_budget: 10
ingredients_per_player: {min: 3, max: 6}
timeline_actions: {min: 5, max: 6}
deck_size: {min: 2, max: 20}
starting_hand_size: 2
phase_durations: {planning: 150, execution: 330, judgment: 60}
event_frequency_window_sec: 240
```

- [ ] **Step 6 : Créer le convertisseur `scripts/build_content.py`**

```python
#!/usr/bin/env python3
"""Compile les sources YAML de content/source/ en content/compiled/content.json.

Usage:  python scripts/build_content.py
Dépendance: pip install pyyaml
"""
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML requis : pip install pyyaml")

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "content" / "source"
OUT = ROOT / "content" / "compiled" / "content.json"

# fichier source -> clé dans le JSON final (les 5 premiers sont des listes)
LIST_FILES = {
    "ingredients": "ingredients",
    "actions": "actions",
    "cards": "cards",
    "events": "events",
    "criteria": "criteria",
}

def main() -> None:
    data = {}
    for stem, key in LIST_FILES.items():
        path = SRC / f"{stem}.yaml"
        if not path.exists():
            sys.exit(f"Source manquante : {path}")
        with path.open(encoding="utf-8") as f:
            data[key] = yaml.safe_load(f) or []

    cfg_path = SRC / "match_config.yaml"
    if not cfg_path.exists():
        sys.exit(f"Source manquante : {cfg_path}")
    with cfg_path.open(encoding="utf-8") as f:
        data["match_config"] = yaml.safe_load(f) or {}

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"Écrit : {OUT}")

if __name__ == "__main__":
    main()
```

- [ ] **Step 7 : Générer le JSON et vérifier qu'il charge**

Run :
```bash
python scripts/build_content.py
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```
Expected : `content/compiled/content.json` créé ; toutes les suites passent.

- [ ] **Step 8 : Commit**

```bash
git add content/content_loader.gd content/source scripts/build_content.py content/compiled/content.json tests/test_content_json.gd
git commit -m "feat(content): chargement JSON + sources YAML + convertisseur build_content.py"
```

---

### Task 7 : `StatEngine` — effets et calcul de plat

**Files:**
- Create: `core/systems/stat_engine.gd`
- Test: `tests/test_stat_engine.gd`

**Interfaces:**
- Consumes: `Stats` (Task 2), `IngredientRes` / `ActionRes` (Task 4).
- Produces:
  - `StatEngine.STAT_MIN: int` = `-50`, `StatEngine.STAT_MAX: int` = `50`
  - `StatEngine.apply_effect(stats: Dictionary, effect: Dictionary) -> Dictionary` — applique un `EffectSpec` (partie `"stats"`) et borne le résultat
  - `StatEngine.compute_dish(ingredients: Array, actions: Array) -> Dictionary` — somme des stats d'ingrédients (`IngredientRes`) puis application des effets d'actions (`ActionRes`) dans l'ordre

Note : les règles nommées (`effect.rule`) ne modifient pas les stats du plat ici ; elles seront interprétées par le moteur d'événements/cartes au Plan 2. `apply_effect` ignore silencieusement une clé `rule`.

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_stat_engine.gd` :

```gdscript
extends GutTest

func test_apply_effect_adds_and_clamps():
    var base := {"umami": 49}
    var r := StatEngine.apply_effect(base, {"stats": {"umami": 10}})
    assert_eq(int(r["umami"]), StatEngine.STAT_MAX, "doit borner à STAT_MAX")

func test_apply_effect_ignores_named_rule():
    var r := StatEngine.apply_effect(Stats.empty(), {"rule": "stop_oven_seconds", "value": 5})
    for k in Stats.KEYS:
        assert_eq(int(r[k]), 0, "une règle nommée ne touche pas les stats du plat")

func test_compute_dish_sums_ingredients_then_actions():
    var tomate := IngredientRes.from_dict({"id": "tomate", "cost": 2, "stats": {"umami": 3, "acide": 4}})
    var boeuf := IngredientRes.from_dict({"id": "boeuf", "cost": 3, "stats": {"umami": 5, "gras": 3}})
    var cuire := ActionRes.from_dict({"id": "cuire", "base_duration_sec": 45, "effect": {"stats": {"umami": 2, "acide": -1}}})
    var dish := StatEngine.compute_dish([tomate, boeuf], [cuire])
    # umami: 3+5+2=10 ; acide: 4-1=3 ; gras: 3
    assert_eq(int(dish["umami"]), 10)
    assert_eq(int(dish["acide"]), 3)
    assert_eq(int(dish["gras"]), 3)

func test_compute_dish_empty():
    var dish := StatEngine.compute_dish([], [])
    for k in Stats.KEYS:
        assert_eq(int(dish[k]), 0)
```

- [ ] **Step 2 : Lancer le test, vérifier l'échec**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_stat_engine.gd -gexit`
Expected : FAIL — `StatEngine` non défini.

- [ ] **Step 3 : Implémenter `core/systems/stat_engine.gd`**

```gdscript
class_name StatEngine
extends RefCounted

const STAT_MIN: int = -50
const STAT_MAX: int = 50

static func apply_effect(stats: Dictionary, effect: Dictionary) -> Dictionary:
    var out := Stats.clamp_stats(stats, STAT_MIN, STAT_MAX)
    if effect.has("stats"):
        out = Stats.add(out, effect["stats"])
    return Stats.clamp_stats(out, STAT_MIN, STAT_MAX)

static func compute_dish(ingredients: Array, actions: Array) -> Dictionary:
    var s := Stats.empty()
    for ing in ingredients:
        s = Stats.add(s, ing.stats)
    for act in actions:
        s = apply_effect(s, act.effect)
    return Stats.clamp_stats(s, STAT_MIN, STAT_MAX)
```

- [ ] **Step 4 : Lancer le test, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_stat_engine.gd -gexit`
Expected : PASS (4 tests).

- [ ] **Step 5 : Commit**

```bash
git add core/systems/stat_engine.gd tests/test_stat_engine.gd
git commit -m "feat(core): StatEngine — effets et calcul de plat"
```

---

### Task 8 : `JudgmentEngine` — score pondéré et vainqueur

**Files:**
- Create: `core/systems/judgment_engine.gd`
- Test: `tests/test_judgment_engine.gd`

**Interfaces:**
- Consumes: `CriterionRes` (Task 4).
- Produces:
  - `JudgmentEngine.score_dish(dish_stats: Dictionary, criteria: Array) -> float` — somme `stat[c.id] * c.weight` sur chaque `CriterionRes`
  - `JudgmentEngine.judge(dish_a: Dictionary, dish_b: Dictionary, criteria: Array) -> Dictionary` — retourne `{"score_a": float, "score_b": float, "winner": String}` avec `winner ∈ {"a","b","draw"}`

Note (spec §3, §9) : au Plan 1, chaque `CriterionRes.id` correspond à une **clé de stat** (ex. `umami`). Le bonus d'originalité (critère calculé sur l'historique des tags) est **hors périmètre** ici et sera ajouté au Plan 2 ; un critère dont l'`id` n'est pas une clé de stat contribue `0` pour l'instant.

- [ ] **Step 1 : Écrire le test qui échoue**

Fichier `tests/test_judgment_engine.gd` :

```gdscript
extends GutTest

func _criteria() -> Array:
    return [
        CriterionRes.from_dict({"id": "umami", "weight": 1.5}),
        CriterionRes.from_dict({"id": "gras", "weight": 0.5}),
    ]

func test_score_dish_weighted_sum():
    var dish := {"umami": 10, "gras": 4, "acide": 8}
    # 10*1.5 + 4*0.5 = 15 + 2 = 17 (acide non noté)
    assert_almost_eq(JudgmentEngine.score_dish(dish, _criteria()), 17.0, 0.001)

func test_unknown_criterion_scores_zero():
    var crit := [CriterionRes.from_dict({"id": "originalite", "weight": 2.0})]
    assert_almost_eq(JudgmentEngine.score_dish({"umami": 10}, crit), 0.0, 0.001)

func test_judge_picks_higher_score():
    var a := {"umami": 10}
    var b := {"umami": 4}
    var r := JudgmentEngine.judge(a, b, _criteria())
    assert_eq(r["winner"], "a")
    assert_almost_eq(r["score_a"], 15.0, 0.001)

func test_judge_draw():
    var a := {"umami": 6}
    var b := {"umami": 6}
    var r := JudgmentEngine.judge(a, b, _criteria())
    assert_eq(r["winner"], "draw")
```

- [ ] **Step 2 : Lancer le test, vérifier l'échec**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_judgment_engine.gd -gexit`
Expected : FAIL — `JudgmentEngine` non défini.

- [ ] **Step 3 : Implémenter `core/systems/judgment_engine.gd`**

```gdscript
class_name JudgmentEngine
extends RefCounted

static func score_dish(dish_stats: Dictionary, criteria: Array) -> float:
    var total := 0.0
    for c in criteria:
        total += float(dish_stats.get(c.id, 0)) * c.weight
    return total

static func judge(dish_a: Dictionary, dish_b: Dictionary, criteria: Array) -> Dictionary:
    var sa := score_dish(dish_a, criteria)
    var sb := score_dish(dish_b, criteria)
    var winner := "draw"
    if sa > sb:
        winner = "a"
    elif sb > sa:
        winner = "b"
    return {"score_a": sa, "score_b": sb, "winner": winner}
```

- [ ] **Step 4 : Lancer le test, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_judgment_engine.gd -gexit`
Expected : PASS (4 tests).

- [ ] **Step 5 : Commit**

```bash
git add core/systems/judgment_engine.gd tests/test_judgment_engine.gd
git commit -m "feat(core): JudgmentEngine — score pondéré et vainqueur"
```

---

### Task 9 : Intégration — du contenu chargé au vainqueur

**Files:**
- Test: `tests/test_integration_dish.gd`

**Interfaces:**
- Consumes: `ContentLoader`, `ContentDB`, `StatEngine`, `JudgmentEngine`, `ValidContent`.
- Produces: preuve que la chaîne complète fonctionne headless (livrable du Plan 1).

- [ ] **Step 1 : Écrire le test d'intégration**

Fichier `tests/test_integration_dish.gd` :

```gdscript
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
```

- [ ] **Step 2 : Lancer le test, vérifier le succès**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_integration_dish.gd -gexit`
Expected : PASS (2 tests).

- [ ] **Step 3 : Lancer TOUTE la suite (non-régression)**

Run : `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
Expected : toutes les suites passent, 0 échec.

- [ ] **Step 4 : Commit**

```bash
git add tests/test_integration_dish.gd
git commit -m "test(core): intégration contenu→calcul→jugement de bout en bout"
```

---

## Self-Review (effectuée)

**Couverture spec (§ concernés par le Plan 1) :**
- §5 pipeline contenu YAML→JSON→Resources + validation → Tasks 4, 5, 6 ✅
- §3 `StatEngine`, `JudgmentEngine`, `Rng` seedé → Tasks 3, 7, 8 ✅
- §2 pureté headless (aucune dépendance rendu) → contrainte globale, respectée par tous les fichiers `core/`/`content/` ✅
- §7 tests GUT par niveau (unitaire + intégration) → chaque task + Task 9 ✅
- **Hors périmètre assumé** (renvoyé au Plan 2/3/4, cf. spec §9) : `GameState`, `Intents`, `Timeline`, `EventScheduler`, `CardResolver`, `PhaseMachine`, `GameCore`, réseau, présentation, bonus d'originalité, diminishing returns.

**Scan placeholders :** aucun TODO/TBD ; chaque étape de code contient le code complet ; chaque test contient ses assertions réelles.

**Cohérence des types :** `Stats.KEYS`, `from_dict`, `ContentLoader.LoadResult{ok, db, errors}`, `StatEngine.compute_dish/apply_effect`, `JudgmentEngine.judge` → signatures identiques entre déclaration (blocs Interfaces) et usage (tests + implémentations). Vérifié.

---

## Suite

Après validation du Plan 1, les plans suivants seront rédigés dans le même dossier :
- **Plan 2** — Cœur de partie & machine à phases (`GameState`, `Intents`, `Timeline`, `EventScheduler`, `CardResolver`, `PhaseMachine`, `GameCore`, `get_view`, bonus d'originalité).
- **Plan 3** — Réseau (relais WebSocket, `NetSession`/`ITransport`, `protocol`, `reconciler`, test d'intégration hôte/invité).
- **Plan 4** — Présentation (scènes Godot, UI, input, view models, optimistic UI).
