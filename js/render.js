// ---------------------------------------------------------------
// Canvas renderer. Pure presentation — reads game state, draws it.
// ---------------------------------------------------------------

class Renderer {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    canvas.width = MAP_W * TILE;
    canvas.height = MAP_H * TILE;
  }

  draw(game, ui) {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    // Terrain
    for (let y = 0; y < MAP_H; y++) {
      for (let x = 0; x < MAP_W; x++) {
        const t = terrainAt(x, y);
        ctx.fillStyle = (x + y) % 2 === 0 ? t.color : t.colorAlt;
        ctx.fillRect(x * TILE, y * TILE, TILE, TILE);
        this.drawTerrainDetail(x, y, t);
      }
    }

    // Grid lines
    ctx.strokeStyle = "rgba(0,0,0,0.12)";
    ctx.lineWidth = 1;
    for (let x = 0; x <= MAP_W; x++) {
      ctx.beginPath(); ctx.moveTo(x * TILE, 0); ctx.lineTo(x * TILE, MAP_H * TILE); ctx.stroke();
    }
    for (let y = 0; y <= MAP_H; y++) {
      ctx.beginPath(); ctx.moveTo(0, y * TILE); ctx.lineTo(MAP_W * TILE, y * TILE); ctx.stroke();
    }

    // Highlights: movement range
    if (ui.reachable) {
      for (const node of ui.reachable.values()) {
        if (node.passOnly) continue;
        this.tint(node.x, node.y, "rgba(80,140,255,0.40)");
      }
    }
    // Highlights: attackable enemies / healable allies
    if (ui.attackTargets) {
      for (const t of ui.attackTargets) this.tint(t.x, t.y, "rgba(255,60,60,0.45)");
    }
    if (ui.healTargets) {
      for (const t of ui.healTargets) this.tint(t.x, t.y, "rgba(60,255,120,0.45)");
    }

    // Planned path
    if (ui.path && ui.path.length > 1) {
      ctx.strokeStyle = "rgba(255,255,255,0.85)";
      ctx.lineWidth = 4;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.beginPath();
      for (let i = 0; i < ui.path.length; i++) {
        const px = ui.path[i].x * TILE + TILE / 2;
        const py = ui.path[i].y * TILE + TILE / 2;
        if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
      }
      ctx.stroke();
    }

    // Units
    for (const u of game.units) {
      if (u.hp > 0) this.drawUnit(u, ui);
    }

    // Cursor
    if (ui.hover && inBounds(ui.hover.x, ui.hover.y)) {
      ctx.strokeStyle = "#ffe94d";
      ctx.lineWidth = 3;
      ctx.strokeRect(ui.hover.x * TILE + 2, ui.hover.y * TILE + 2, TILE - 4, TILE - 4);
    }
  }

  tint(x, y, color) {
    this.ctx.fillStyle = color;
    this.ctx.fillRect(x * TILE, y * TILE, TILE, TILE);
  }

  drawTerrainDetail(x, y, t) {
    const ctx = this.ctx;
    const cx = x * TILE + TILE / 2, cy = y * TILE + TILE / 2;
    ctx.save();
    if (t === TERRAIN.forest) {
      ctx.fillStyle = "rgba(20,60,20,0.55)";
      ctx.beginPath();
      ctx.moveTo(cx, cy - 12); ctx.lineTo(cx + 9, cy + 8); ctx.lineTo(cx - 9, cy + 8);
      ctx.closePath(); ctx.fill();
    } else if (t === TERRAIN.mountain) {
      ctx.fillStyle = "rgba(70,55,40,0.6)";
      ctx.beginPath();
      ctx.moveTo(cx - 13, cy + 10); ctx.lineTo(cx - 2, cy - 11); ctx.lineTo(cx + 6, cy + 10);
      ctx.closePath(); ctx.fill();
      ctx.fillStyle = "rgba(255,255,255,0.7)";
      ctx.beginPath();
      ctx.moveTo(cx - 5, cy - 5); ctx.lineTo(cx - 2, cy - 11); ctx.lineTo(cx + 1, cy - 5);
      ctx.closePath(); ctx.fill();
    } else if (t === TERRAIN.water) {
      ctx.strokeStyle = "rgba(255,255,255,0.35)";
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.moveTo(cx - 12, cy); ctx.quadraticCurveTo(cx - 6, cy - 5, cx, cy);
      ctx.quadraticCurveTo(cx + 6, cy + 5, cx + 12, cy);
      ctx.stroke();
    } else if (t === TERRAIN.bridge) {
      ctx.strokeStyle = "rgba(60,40,20,0.5)";
      ctx.lineWidth = 2;
      for (let i = -1; i <= 1; i++) {
        ctx.beginPath();
        ctx.moveTo(x * TILE + 4, cy + i * 10);
        ctx.lineTo(x * TILE + TILE - 4, cy + i * 10);
        ctx.stroke();
      }
    } else if (t === TERRAIN.fort) {
      ctx.fillStyle = "rgba(60,60,70,0.65)";
      ctx.fillRect(cx - 10, cy - 6, 20, 14);
      for (let i = 0; i < 3; i++) ctx.fillRect(cx - 10 + i * 8, cy - 11, 4, 6);
    }
    ctx.restore();
  }

  drawUnit(u, ui) {
    const ctx = this.ctx;
    const cx = u.x * TILE + TILE / 2, cy = u.y * TILE + TILE / 2;
    const colors = TEAM_COLORS[u.team];
    const grayed = u.acted && u.team === (ui.game ? ui.game.turn : null);

    // Body
    ctx.save();
    if (ui.selected === u) {
      ctx.shadowColor = "#ffe94d";
      ctx.shadowBlur = 12;
    }
    ctx.fillStyle = grayed ? "#8a8a8a" : colors.main;
    ctx.strokeStyle = grayed ? "#5a5a5a" : colors.dark;
    ctx.lineWidth = 2.5;
    ctx.beginPath();
    ctx.arc(cx, cy - 2, 14, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.restore();

    // Class letter
    ctx.fillStyle = "#fff";
    ctx.font = "bold 15px 'Segoe UI', sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(u.cls.icon, cx, cy - 2);

    // HP bar
    const w = TILE - 12, h = 5;
    const bx = u.x * TILE + 6, by = u.y * TILE + TILE - 9;
    ctx.fillStyle = "rgba(0,0,0,0.55)";
    ctx.fillRect(bx, by, w, h);
    const frac = u.hp / u.maxHp;
    ctx.fillStyle = frac > 0.5 ? "#5ad35a" : frac > 0.25 ? "#e8c33a" : "#e05050";
    ctx.fillRect(bx + 1, by + 1, (w - 2) * frac, h - 2);
  }
}
