# Port of js/data.js — all static tables: terrain, classes, rosters, map.
# `class_name` registers this globally, so any script can say GameData.TILE.
# Everything is `static`: this class is never instantiated, it's a namespace.
class_name GameData
extends RefCounted

const TILE := 44  # pixel size of one grid tile (used by the renderer)

# Map legend: . plain, f forest, m mountain, ~ water, = bridge, F fort
const MAP_LAYOUT: Array[String] = [
	"....f..~~...m...",
	"..f....~~..mm..f",
	".......~~...m...",
	"f...f..==......f",
	"......~~~...f...",
	"..F...~~~.......",
	".......~~...F...",
	"...f...==.......",
	"......~~~....f..",
	".f....~~~..f....",
	"....~~~~........",
	"...~~~~....m..mm",
]

const MAP_W := 16
const MAP_H := 12

const TERRAIN_CHARS := {
	".": "plain", "f": "forest", "m": "mountain",
	"~": "water", "=": "bridge", "F": "fort",
}

# Quick Time Events (Legend of Dragoon style "additions").
# Offense: each class has a unique attack pattern — `periods` is the seconds
# between successive press targets (one entry per press); `perfect`/`good`
# are the timing tolerances in seconds.
# On touch (this branch): each offense step is a SWIPE in the listed
# direction, graded at the moment the swipe crosses the distance threshold;
# a wrong-direction swipe is a Miss. Patterns are themed per class.
# Defense is a HOLD-AND-RELEASE parry: press and hold while the attacker
# winds up (`windup`) and charges in (`travel`), then release as the blow
# lands. Tolerances grade the release against the impact moment.
const DEFENSE_QTE := {"windup": 0.5, "travel": 0.9, "perfect": 0.07, "good": 0.16}

# Starting rosters: [class name, x, y, personal name]
const PLAYER_ARMY := [
	["Knight", 1, 4, "Doran"],
	["Mercenary", 2, 3, "Silke"],
	["Cavalier", 1, 6, "Renny"],
	["Archer", 2, 5, "Wick"],
	["Mage", 1, 8, "Ophira"],
	["Healer", 0, 5, "Tama"],
	["Pegasus", 3, 7, "Averil"],
]

const ENEMY_ARMY := [
	["Knight", 14, 5, "Gorm"],
	["Mercenary", 13, 7, "Vask"],
	["Cavalier", 14, 3, "Hessa"],
	["Archer", 13, 4, "Pell"],
	["Mage", 14, 8, "Zed"],
	["Healer", 15, 6, "Mire"],
	["Pegasus", 12, 6, "Kaia"],
]

# `static var` (not const) because TerrainType.new() isn't a constant
# expression. Initialized once when the class is first loaded.
static var terrain_types := {
	"plain": TerrainType.new("Plains", 1, 0, 0, Color("7a9e5f"), Color("74985a")),
	"forest": TerrainType.new("Forest", 2, 1, 20, Color("4f7a42"), Color("49743d")),
	"mountain": TerrainType.new("Mountain", 3, 2, 30, Color("8a7a63"), Color("84745e")),
	"water": TerrainType.new("River", INF, 0, 0, Color("4f7fae"), Color("4a7aa9")),
	"bridge": TerrainType.new("Bridge", 1, 0, 0, Color("a08c66"), Color("9a8660")),
	"fort": TerrainType.new("Fort", 2, 3, 20, Color("8f8f97"), Color("89898f")),
}

static var unit_classes := {
	"Knight": UnitClass.new({
		"display_name": "Knight", "icon": "K", "weapon": "Iron Lance",
		"max_hp": 30, "strength": 12, "skill": 6, "speed": 3,
		"defense": 13, "resistance": 3, "movement": 4,
		"attack_range": [1], "might": 8, "hit": 80, "crit": 0,
		"description": "Armored wall. Hits hard, moves slow, shrugs off physical damage.",
		"qte": {"swipes": ["down"], "periods": [1.1], "perfect": 0.07, "good": 0.16},
	}),
	"Mercenary": UnitClass.new({
		"display_name": "Mercenary", "icon": "M", "weapon": "Steel Sword",
		"max_hp": 26, "strength": 9, "skill": 13, "speed": 11,
		"defense": 6, "resistance": 4, "movement": 5,
		"attack_range": [1], "might": 7, "hit": 95, "crit": 10,
		"description": "Balanced swordfighter. Accurate, fast, doubles slower foes.",
		"qte": {"swipes": ["right", "left", "right"],
			"periods": [0.55, 0.55, 0.55], "perfect": 0.055, "good": 0.12},
	}),
	"Cavalier": UnitClass.new({
		"display_name": "Cavalier", "icon": "C", "weapon": "Iron Lance",
		"max_hp": 27, "strength": 10, "skill": 8, "speed": 8,
		"defense": 9, "resistance": 4, "movement": 7,
		"attack_range": [1], "might": 8, "hit": 85, "crit": 0, "is_mounted": true,
		"description": "Mounted lancer. High movement, but mountains block the horse.",
		"qte": {"swipes": ["right", "right"], "periods": [0.7, 0.45], "perfect": 0.06, "good": 0.13},
	}),
	"Archer": UnitClass.new({
		"display_name": "Archer", "icon": "A", "weapon": "Iron Bow",
		"max_hp": 23, "strength": 9, "skill": 12, "speed": 7,
		"defense": 5, "resistance": 3, "movement": 5,
		"attack_range": [2], "might": 7, "hit": 90, "crit": 5,
		"description": "Attacks at range 2 only. Safe from melee counters, weak up close.",
		"qte": {"swipes": ["up"], "periods": [0.8], "perfect": 0.04, "good": 0.09},
	}),
	"Mage": UnitClass.new({
		"display_name": "Mage", "icon": "W", "weapon": "Fire Tome",
		"max_hp": 21, "strength": 2, "magic_power": 12, "skill": 9, "speed": 8,
		"defense": 3, "resistance": 10, "movement": 5,
		"attack_range": [1, 2], "might": 6, "hit": 90, "crit": 0, "is_magic": true,
		"description": "Magic damage targets resistance. Melts armored units.",
		"qte": {"swipes": ["up", "down"], "periods": [0.9, 0.5], "perfect": 0.06, "good": 0.13},
	}),
	"Healer": UnitClass.new({
		"display_name": "Healer", "icon": "H", "weapon": "Heal Staff",
		"max_hp": 20, "strength": 2, "magic_power": 9, "skill": 8, "speed": 8,
		"defense": 3, "resistance": 9, "movement": 5,
		"heal_range": [1], "heal_power": 12,
		"description": "Cannot attack. Restores HP to adjacent allies.",
	}),
	"Pegasus": UnitClass.new({
		"display_name": "Pegasus Knight", "icon": "P", "weapon": "Slim Lance",
		"max_hp": 23, "strength": 8, "skill": 10, "speed": 13,
		"defense": 5, "resistance": 9, "movement": 7,
		"attack_range": [1], "might": 6, "hit": 90, "crit": 5, "is_flier": true,
		"description": "Flier: ignores all terrain. Fast and evasive, but fragile.",
		"qte": {"swipes": ["up", "right", "down"],
			"periods": [0.45, 0.4, 0.35], "perfect": 0.05, "good": 0.11},
	}),
}

# QTE ring colors follow combat type: blue physical, green magic, red defense.
static var qte_colors := {
	"physical": Color("4a90d9"), "magic": Color("3ecf6e"), "defense": Color("e04848"),
}

# Keyed by Unit.Team enum values.
static var team_colors := {
	Unit.Team.PLAYER: {
		"main": Color("4a90d9"), "dark": Color("2c5f96"), "light": Color("8dbef0"),
	},
	Unit.Team.ENEMY: {
		"main": Color("d9534f"), "dark": Color("96342c"), "light": Color("f0938d"),
	},
}
