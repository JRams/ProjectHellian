// ---------------------------------------------------------------
// Static game data: terrain types, unit classes, army rosters, map
// Engine-agnostic: no rendering or DOM code in this file.
// ---------------------------------------------------------------

const TILE = 44; // pixel size of one grid tile (used by renderer)

const TERRAIN = {
  plain:    { name: "Plains",   cost: 1, def: 0, avoid: 0,  color: "#7a9e5f", colorAlt: "#74985a" },
  forest:   { name: "Forest",   cost: 2, def: 1, avoid: 20, color: "#4f7a42", colorAlt: "#49743d" },
  mountain: { name: "Mountain", cost: 3, def: 2, avoid: 30, color: "#8a7a63", colorAlt: "#84745e" },
  water:    { name: "River",    cost: Infinity, def: 0, avoid: 0, color: "#4f7fae", colorAlt: "#4a7aa9" },
  bridge:   { name: "Bridge",   cost: 1, def: 0, avoid: 0,  color: "#a08c66", colorAlt: "#9a8660" },
  fort:     { name: "Fort",     cost: 2, def: 3, avoid: 20, color: "#8f8f97", colorAlt: "#89898f" },
};

// Map legend: . plain, f forest, m mountain, ~ water, = bridge, F fort
const MAP_LAYOUT = [
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
];

const MAP_W = MAP_LAYOUT[0].length; // 16
const MAP_H = MAP_LAYOUT.length;    // 12

const TERRAIN_CHARS = {
  ".": "plain", "f": "forest", "m": "mountain",
  "~": "water", "=": "bridge", "F": "fort",
};

// Quick Time Events (Legend of Dragoon style "additions").
// Each class has a unique attack pattern: `periods` is the seconds between
// successive press targets (one entry per press); `perfect`/`good` are the
// timing tolerances in seconds. Defense is one universal well-timed brace.
// Ring colors follow combat type: blue physical, green magic, red defense.
const DEFENSE_QTE = { periods: [0.7], perfect: 0.06, good: 0.14 };
const QTE_COLORS = { physical: "#4a90d9", magic: "#3ecf6e", defense: "#e04848" };

// Unit classes. range = attack distances (manhattan). mt/hit/crit describe
// the class's default weapon. magic damage targets res instead of def.
const CLASSES = {
  Knight: {
    name: "Knight", icon: "K", weapon: "Iron Lance",
    hp: 30, str: 12, mag: 0, skl: 6, spd: 3, def: 13, res: 3, mov: 4,
    range: [1], mt: 8, hit: 80, crit: 0,
    desc: "Armored wall. Hits hard, moves slow, shrugs off physical damage.",
    qte: { periods: [1.1], perfect: 0.07, good: 0.16 },
  },
  Mercenary: {
    name: "Mercenary", icon: "M", weapon: "Steel Sword",
    hp: 26, str: 9, mag: 0, skl: 13, spd: 11, def: 6, res: 4, mov: 5,
    range: [1], mt: 7, hit: 95, crit: 10,
    desc: "Balanced swordfighter. Accurate, fast, doubles slower foes.",
    qte: { periods: [0.55, 0.55, 0.55], perfect: 0.055, good: 0.12 },
  },
  Cavalier: {
    name: "Cavalier", icon: "C", weapon: "Iron Lance",
    hp: 27, str: 10, mag: 0, skl: 8, spd: 8, def: 9, res: 4, mov: 7,
    range: [1], mt: 8, hit: 85, crit: 0, mounted: true,
    desc: "Mounted lancer. High movement, but mountains block the horse.",
    qte: { periods: [0.7, 0.45], perfect: 0.06, good: 0.13 },
  },
  Archer: {
    name: "Archer", icon: "A", weapon: "Iron Bow",
    hp: 23, str: 9, mag: 0, skl: 12, spd: 7, def: 5, res: 3, mov: 5,
    range: [2], mt: 7, hit: 90, crit: 5,
    desc: "Attacks at range 2 only. Safe from melee counters, weak up close.",
    qte: { periods: [0.8], perfect: 0.04, good: 0.09 },
  },
  Mage: {
    name: "Mage", icon: "W", weapon: "Fire Tome",
    hp: 21, str: 2, mag: 12, skl: 9, spd: 8, def: 3, res: 10, mov: 5,
    range: [1, 2], mt: 6, hit: 90, crit: 0, magic: true,
    desc: "Magic damage targets resistance. Melts armored units.",
    qte: { periods: [0.9, 0.5], perfect: 0.06, good: 0.13 },
  },
  Healer: {
    name: "Healer", icon: "H", weapon: "Heal Staff",
    hp: 20, str: 2, mag: 9, skl: 8, spd: 8, def: 3, res: 9, mov: 5,
    range: [], healRange: [1], healPower: 12,
    desc: "Cannot attack. Restores HP to adjacent allies.",
  },
  Pegasus: {
    name: "Pegasus Knight", icon: "P", weapon: "Slim Lance",
    hp: 23, str: 8, mag: 0, skl: 10, spd: 13, def: 5, res: 9, mov: 7,
    range: [1], mt: 6, hit: 90, crit: 5, flier: true,
    desc: "Flier: ignores all terrain. Fast and evasive, but fragile.",
    qte: { periods: [0.45, 0.4, 0.35], perfect: 0.05, good: 0.11 },
  },
};

// Starting rosters: [className, x, y, personalName]
const PLAYER_ARMY = [
  ["Knight",    1,  4, "Doran"],
  ["Mercenary", 2,  3, "Silke"],
  ["Cavalier",  1,  6, "Renny"],
  ["Archer",    2,  5, "Wick"],
  ["Mage",      1,  8, "Ophira"],
  ["Healer",    0,  5, "Tama"],
  ["Pegasus",   3,  7, "Averil"],
];

const ENEMY_ARMY = [
  ["Knight",    14, 5, "Gorm"],
  ["Mercenary", 13, 7, "Vask"],
  ["Cavalier",  14, 3, "Hessa"],
  ["Archer",    13, 4, "Pell"],
  ["Mage",      14, 8, "Zed"],
  ["Healer",    15, 6, "Mire"],
  ["Pegasus",   12, 6, "Kaia"],
];

const TEAM_COLORS = {
  player: { main: "#4a90d9", dark: "#2c5f96", light: "#8dbef0" },
  enemy:  { main: "#d9534f", dark: "#96342c", light: "#f0938d" },
};
