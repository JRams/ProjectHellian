// ---------------------------------------------------------------
// Grid logic: cardinal-direction movement, pathfinding, ranges.
// Engine-agnostic.
// ---------------------------------------------------------------

// The four cardinal directions. There is no diagonal movement.
const CARDINALS = [
  { dx: 0, dy: -1 }, // north
  { dx: 1, dy: 0 },  // east
  { dx: 0, dy: 1 },  // south
  { dx: -1, dy: 0 }, // west
];

function inBounds(x, y) {
  return x >= 0 && x < MAP_W && y >= 0 && y < MAP_H;
}

function terrainAt(x, y) {
  return TERRAIN[TERRAIN_CHARS[MAP_LAYOUT[y][x]]];
}

// Movement cost of a tile for a specific unit (Infinity = impassable).
function moveCost(unit, x, y) {
  const t = terrainAt(x, y);
  if (unit.cls.flier) return 1;                       // fliers ignore terrain
  if (unit.cls.mounted && t === TERRAIN.mountain) return Infinity;
  return t.cost;
}

function key(x, y) { return y * MAP_W + x; }

// Dijkstra flood-fill over cardinal steps. Returns Map(key -> {x, y, cost,
// from}) of every tile the unit can reach with its movement stat. Tiles
// occupied by enemies block passage; tiles occupied by allies can be passed
// through but not stopped on (marked passOnly).
function reachableTiles(unit, units) {
  const occupied = new Map();
  for (const u of units) {
    if (u.hp > 0 && u !== unit) occupied.set(key(u.x, u.y), u);
  }

  const best = new Map();
  const start = { x: unit.x, y: unit.y, cost: 0, from: null };
  best.set(key(unit.x, unit.y), start);
  const frontier = [start];

  while (frontier.length) {
    // pop lowest-cost node (fine for maps this size)
    let bi = 0;
    for (let i = 1; i < frontier.length; i++) {
      if (frontier[i].cost < frontier[bi].cost) bi = i;
    }
    const cur = frontier.splice(bi, 1)[0];

    for (const { dx, dy } of CARDINALS) {
      const nx = cur.x + dx, ny = cur.y + dy;
      if (!inBounds(nx, ny)) continue;
      const stepCost = moveCost(unit, nx, ny);
      const total = cur.cost + stepCost;
      if (total > unit.cls.mov) continue;
      const blocker = occupied.get(key(nx, ny));
      if (blocker && blocker.team !== unit.team) continue; // enemies block
      const prev = best.get(key(nx, ny));
      if (prev && prev.cost <= total) continue;
      const node = { x: nx, y: ny, cost: total, from: cur };
      best.set(key(nx, ny), node);
      frontier.push(node);
    }
  }

  // Can't end movement on any occupied tile (ally or enemy).
  for (const [k, node] of best) {
    node.passOnly = occupied.has(k);
  }
  return best;
}

// Reconstruct the cardinal-step path to a reachable tile.
function pathTo(reachable, x, y) {
  let node = reachable.get(key(x, y));
  const path = [];
  while (node) {
    path.unshift({ x: node.x, y: node.y });
    node = node.from;
  }
  return path;
}

function manhattan(x1, y1, x2, y2) {
  return Math.abs(x1 - x2) + Math.abs(y1 - y2);
}

// Enemies attackable from a given standing position.
function targetsFrom(unit, x, y, units, ranges) {
  const rs = ranges || unit.cls.range;
  return units.filter(u =>
    u.hp > 0 && u.team !== unit.team && rs.includes(manhattan(x, y, u.x, u.y)));
}

// Wounded allies healable from a given standing position.
function healTargetsFrom(unit, x, y, units) {
  if (!unit.cls.healRange || unit.cls.healRange.length === 0) return [];
  return units.filter(u =>
    u.hp > 0 && u !== unit && u.team === unit.team && u.hp < u.maxHp &&
    unit.cls.healRange.includes(manhattan(x, y, u.x, u.y)));
}
