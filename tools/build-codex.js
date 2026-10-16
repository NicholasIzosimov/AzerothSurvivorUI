#!/usr/bin/env node
// Builds docs/codex.md and docs/codex.json from Survivor UI's saved variables.
//
// Usage:
//   node tools/build-codex.js [path\to\SurvivorUI.lua]
//
// The saved-variables file defaults to
// C:\Git\wenilla\benilla-config\saved\SurvivorUI.lua. Rerun it after playing:
// the codex is rebuilt from scratch each time, from the player's own collected
// data only (worn jewelry tooltips, ability book, best boss times).
//
// Read from SurvivorUIDB: codex, seenGear, abilityBook, bossBests.
// Ignored: runMemory, gearLog and every setting.
// No dependencies: a small parser below reads the Lua table subset the game
// writes (strings, numbers, booleans, nil, nested tables with ["key"] = value,
// [n] = value, name = value and plain list items).

"use strict";

const fs = require("fs");
const path = require("path");

const DEFAULT_INPUT = "C:\\Git\\wenilla\\benilla-config\\saved\\SurvivorUI.lua";
const OUT_DIR = path.join(__dirname, "..", "docs");
const KINDS = ["Neck", "Ring", "Trinket"];
const KIND_TITLES = { Neck: "Amulets", Ring: "Rings", Trinket: "Trinkets" };
const QUALITIES = {
  ff9d9d9d: "Poor",
  ffffffff: "Common",
  ff1eff00: "Uncommon",
  ff0070dd: "Rare",
  ffa335ee: "Epic",
  ffff8000: "Legendary",
  ffe6cc80: "Artifact",
};

// ---------------------------------------------------------------- Lua parser

function parseLua(source) {
  let pos = 0;

  function fail(message) {
    const line = source.slice(0, pos).split("\n").length;
    throw new Error(`Lua parse error at line ${line}: ${message}`);
  }

  function skip() {
    for (;;) {
      const rest = source.slice(pos, pos + 2);
      if (/^\s/.test(source[pos] || "")) {
        pos++;
      } else if (rest === "--") {
        const long = /^--\[(=*)\[/.exec(source.slice(pos));
        if (long) {
          const close = source.indexOf(`]${long[1]}]`, pos);
          pos = close < 0 ? source.length : close + long[1].length + 2;
        } else {
          const end = source.indexOf("\n", pos);
          pos = end < 0 ? source.length : end + 1;
        }
      } else {
        return;
      }
    }
  }

  function expect(text) {
    skip();
    if (source.slice(pos, pos + text.length) !== text) fail(`expected "${text}"`);
    pos += text.length;
  }

  function string() {
    const quote = source[pos++];
    let out = "";
    for (;;) {
      const c = source[pos++];
      if (c === undefined) fail("unterminated string");
      if (c === quote) return out;
      if (c !== "\\") {
        out += c;
        continue;
      }
      const e = source[pos++];
      const simple = { n: "\n", t: "\t", r: "\r", a: "\x07", b: "\b", f: "\f", v: "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n" };
      if (e in simple) {
        out += simple[e];
      } else if (/[0-9]/.test(e)) {
        let digits = e;
        while (digits.length < 3 && /[0-9]/.test(source[pos])) digits += source[pos++];
        out += String.fromCharCode(Number(digits));
      } else {
        fail(`unknown escape \\${e}`);
      }
    }
  }

  function longString() {
    const open = /^\[(=*)\[\n?/.exec(source.slice(pos));
    const close = `]${open[1]}]`;
    const end = source.indexOf(close, pos);
    if (end < 0) fail("unterminated long string");
    const text = source.slice(pos + open[0].length, end);
    pos = end + close.length;
    return text;
  }

  function number() {
    const match = /^-?(0[xX][0-9a-fA-F]+|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)/.exec(source.slice(pos));
    if (!match) fail("bad number");
    pos += match[0].length;
    return Number(match[0]);
  }

  function value() {
    skip();
    const c = source[pos];
    if (c === "{") return table();
    if (c === '"' || c === "'") return string();
    if (c === "[" && /^\[=*\[/.test(source.slice(pos))) return longString();
    if (c === "-" || c === "." || /[0-9]/.test(c)) return number();
    const word = /^[A-Za-z_][A-Za-z0-9_]*/.exec(source.slice(pos));
    if (word) {
      pos += word[0].length;
      if (word[0] === "true") return true;
      if (word[0] === "false") return false;
      if (word[0] === "nil") return null;
      fail(`unexpected name ${word[0]}`);
    }
    fail(`unexpected "${c}"`);
  }

  // A table becomes a JS object; integer keys stay as string keys "1", "2"...
  function table() {
    expect("{");
    const out = {};
    let next = 1;
    for (;;) {
      skip();
      if (source[pos] === "}") {
        pos++;
        return out;
      }
      let key;
      if (source[pos] === "[" && !/^\[=*\[/.test(source.slice(pos))) {
        pos++;
        key = value();
        expect("]");
        expect("=");
        out[String(key)] = value();
      } else {
        const named = /^([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)/.exec(source.slice(pos));
        if (named) {
          pos += named[0].length;
          out[named[1]] = value();
        } else {
          out[String(next++)] = value();
        }
      }
      skip();
      if (source[pos] === "," || source[pos] === ";") pos++;
      else if (source[pos] !== "}") fail('expected "," or "}"');
    }
  }

  const globals = {};
  for (;;) {
    skip();
    if (pos >= source.length) return globals;
    const name = /^[A-Za-z_][A-Za-z0-9_]*/.exec(source.slice(pos));
    if (!name) fail("expected a global assignment");
    pos += name[0].length;
    expect("=");
    globals[name[0]] = value();
  }
}

// Lua list tables ({[1] = ..., [2] = ...}) as arrays, in index order.
function list(table) {
  if (!table) return [];
  return Object.keys(table)
    .filter((key) => /^\d+$/.test(key))
    .sort((a, b) => a - b)
    .map((key) => table[key]);
}

// ------------------------------------------------------------------- helpers

function stripColors(text) {
  return String(text).replace(/\|c[0-9a-fA-F]{8}/g, "").replace(/\|r/g, "");
}

const ROMAN = { I: 1, V: 5, X: 10, L: 50, C: 100 };

function romanValue(numeral) {
  let value = 0;
  let last = 0;
  for (let i = numeral.length - 1; i >= 0; i--) {
    const digit = ROMAN[numeral[i]];
    if (digit < last) value -= digit;
    else {
      value += digit;
      last = digit;
    }
  }
  return value;
}

// "Quick Strike Ring VIII" -> base "Quick Strike Ring", rank 8. A trailing "+"
// ("X+") is kept in the numeral and sorts just after the plain rank.
function splitRank(name) {
  const match = /^(.*?) ([IVXLC]+)(\+?)$/.exec(name);
  if (!match) return { base: name, numeral: "I", rank: 1, plus: false };
  return { base: match[1], numeral: match[2] + match[3], rank: romanValue(match[2]), plus: match[3] === "+" };
}

function rankOrder(a, b) {
  return a.rank - b.rank || Number(a.plus) - Number(b.plus);
}

function byName(a, b) {
  return a.localeCompare(b, "en");
}

function className(token) {
  return token.charAt(0) + token.slice(1).toLowerCase();
}

function quality(hex) {
  return (hex && QUALITIES[hex.toLowerCase()]) || null;
}

function colorHex(r, g, b) {
  if (typeof r !== "number") return null;
  const part = (v) => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0");
  return part(r) + part(g) + part(b);
}

function formatTime(seconds) {
  const whole = Math.floor(seconds);
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, "0")}`;
}

function formatNumber(value) {
  return Math.round(value).toLocaleString("en-US");
}

// --------------------------------------------------------------- the codex

function buildJewelry(db) {
  const codex = db.codex || {};
  const seen = db.seenGear || {};
  const jewelry = {};
  for (const kind of KINDS) {
    const pieces = new Map();
    const names = new Set([...Object.keys(codex[kind] || {}), ...Object.keys(seen[kind] || {})]);
    for (const fullName of names) {
      const info = (codex[kind] || {})[fullName] || {};
      const { base, numeral, rank, plus } = splitRank(stripColors(fullName));
      if (!pieces.has(base)) pieces.set(base, { name: base, classes: new Set(), only: null, ranks: [] });
      const piece = pieces.get(base);
      for (const cls of Object.keys(info.classes || {})) if (info.classes[cls]) piece.classes.add(cls);
      if (info.only) piece.only = stripColors(info.only);
      const hex = info.hex || (seen[kind] || {})[fullName] || null;
      const lines = list(info.lines).map((line) => {
        const out = { text: stripColors(line["1"] ?? "") };
        const color = colorHex(line["2"], line["3"], line["4"]);
        if (color) out.color = color;
        if (line["5"] != null) out.right = stripColors(line["5"]);
        return out;
      });
      const entry = { numeral, rank, name: stripColors(fullName), quality: quality(hex), hex };
      if (plus) entry.plus = true;
      if (info.icon) entry.icon = info.icon;
      if (info.link) entry.link = info.link;
      entry.tooltip = lines.length > 1;
      entry.lines = lines;
      piece.ranks.push(entry);
    }
    jewelry[kind] = [...pieces.values()]
      .map((piece) => {
        piece.ranks.sort(rankOrder);
        const top = piece.ranks[piece.ranks.length - 1];
        return {
          name: piece.name,
          quality: top.quality,
          icon: [...piece.ranks].reverse().find((r) => r.icon)?.icon ?? null,
          classes: [...piece.classes].sort(byName),
          only: piece.only,
          ranks: piece.ranks,
        };
      })
      .sort((a, b) => byName(a.name, b.name));
  }
  return jewelry;
}

function upgradeText(kind, value) {
  const shown = Number.isInteger(value) ? String(value) : String(Math.round(value * 10) / 10);
  return kind.includes("#") ? kind.replace("#", shown) : `${kind} ${shown}`;
}

function buildAbilities(db) {
  const book = db.abilityBook || {};
  const out = {};
  for (const cls of Object.keys(book).sort(byName)) {
    out[cls] = Object.keys(book[cls])
      .sort(byName)
      .map((name) => {
        const info = book[cls][name];
        const upgrades = Object.keys(info.upgrades || {})
          .sort(byName)
          .map((kind) => ({ kind, best: info.upgrades[kind], text: upgradeText(kind, info.upgrades[kind]) }));
        return {
          name,
          icon: info.icon ?? null,
          inBook: info.inBook === true,
          castsTwice: typeof info.echoLine === "boolean" ? info.echoLine : null,
          crits: typeof info.critLine === "boolean" ? info.critLine : null,
          highestRank: info.rank ?? null,
          runs: info.runs ?? 0,
          bestAverageCast: info.best ?? null,
          bestAverageCastRank: info.bestRank ?? null,
          upgrades,
        };
      });
  }
  return out;
}

function buildBosses(db) {
  const bests = db.bossBests || {};
  const out = {};
  for (const cls of Object.keys(bests).sort(byName)) {
    out[cls] = Object.keys(bests[cls])
      .sort(byName)
      .map((boss) => ({ boss, seconds: bests[cls][boss], time: formatTime(bests[cls][boss]) }));
  }
  return out;
}

// ------------------------------------------------------------------ markdown

function md(text) {
  return String(text).replace(/([\\`*_|<>\[\]])/g, "\\$1");
}

function yesNo(flag) {
  return flag === true ? "yes" : flag === false ? "no" : "–";
}

function renderMarkdown(data) {
  const out = [];
  out.push("# Survivor UI Codex", "");
  out.push(
    "Everything the addon has recorded while playing Azeroth Survivors: every amulet, ring and trinket worn, " +
      "each class's abilities and the best boss times. Generated by `tools/build-codex.js` from the saved " +
      "variables; do not edit by hand.",
    ""
  );
  out.push("- [Jewelry](#jewelry)");
  for (const kind of KINDS) out.push(`  - [${KIND_TITLES[kind]}](#${KIND_TITLES[kind].toLowerCase()})`);
  out.push("- [Abilities](#abilities)", "- [Best boss times](#best-boss-times)", "");

  out.push("## Jewelry", "");
  out.push(
    "Each piece by its name without rank, with every rank seen. A rank's text is its tooltip as kept when " +
      "worn; ranks listed under *name only* were seen before their tooltip was kept.",
    ""
  );
  for (const kind of KINDS) {
    const pieces = data.jewelry[kind];
    out.push(`### ${KIND_TITLES[kind]}`, "");
    if (!pieces.length) {
      out.push("*None seen yet.*", "");
      continue;
    }
    for (const piece of pieces) {
      out.push(`#### ${md(piece.name)}`, "");
      const facts = [];
      if (piece.quality) facts.push(piece.quality);
      facts.push(`ranks ${piece.ranks.map((r) => r.numeral).join(", ")}`);
      facts.push(piece.classes.length ? `worn by ${piece.classes.map(className).join(", ")}` : "worn by: not recorded");
      if (piece.only) facts.push(`kept to ${md(piece.only)}`);
      out.push(facts.join(" · "), "");
      const nameOnly = [];
      for (const rank of piece.ranks) {
        const text = rank.lines.slice(1).map((line) => (line.right ? `${line.text} — ${line.right}` : line.text));
        const label = `${rank.numeral}${rank.quality && rank.quality !== piece.quality ? ` (${rank.quality})` : ""}`;
        if (!text.length) {
          nameOnly.push(label);
        } else {
          out.push(`- **${label}**`);
          for (const line of text) out.push(`  - ${md(line)}`);
        }
      }
      if (nameOnly.length) out.push(`- *Name only:* ${nameOnly.join(", ")}`);
      out.push("");
    }
  }

  out.push("## Abilities", "");
  out.push(
    "Per class. *Twice* and *Crit* say whether the ability's tooltip has the cast-twice and crit lines. " +
      "*Best cast* is the best average damage per cast the meter has seen, at the rank given. " +
      "Upgrades show the best value seen of each kind.",
    ""
  );
  const classes = Object.keys(data.abilities);
  if (!classes.length) out.push("*None recorded yet.*", "");
  for (const cls of classes) {
    out.push(`### ${className(cls)}`, "");
    out.push("| Ability | Twice | Crit | Highest rank | Runs | Best cast | Upgrades |");
    out.push("| --- | --- | --- | --- | --- | --- | --- |");
    for (const a of data.abilities[cls]) {
      const name = a.inBook ? md(a.name) : `${md(a.name)} *(not in spell book)*`;
      const best = a.bestAverageCast != null
        ? `${formatNumber(a.bestAverageCast)}${a.bestAverageCastRank != null ? ` (rank ${a.bestAverageCastRank})` : ""}`
        : "–";
      const upgrades = a.upgrades.length ? a.upgrades.map((u) => md(u.text)).join(", ") : "–";
      out.push(`| ${name} | ${yesNo(a.castsTwice)} | ${yesNo(a.crits)} | ${a.highestRank ?? "–"} | ${a.runs} | ${best} | ${upgrades} |`);
    }
    out.push("");
  }

  out.push("## Best boss times", "");
  const bossClasses = Object.keys(data.bossBests);
  if (!bossClasses.length) out.push("*None recorded yet.*", "");
  for (const cls of bossClasses) {
    out.push(`### ${className(cls)}`, "");
    out.push("| Boss | Best |", "| --- | --- |");
    for (const b of data.bossBests[cls]) out.push(`| ${md(b.boss)} | ${b.time} |`);
    out.push("");
  }
  return out.join("\n");
}

// ---------------------------------------------------------------------- main

function main() {
  const input = process.argv[2] || DEFAULT_INPUT;
  const globals = parseLua(fs.readFileSync(input, "utf8"));
  const db = globals.SurvivorUIDB;
  if (!db) throw new Error(`${input} has no SurvivorUIDB table`);

  const data = {
    jewelry: buildJewelry(db),
    abilities: buildAbilities(db),
    bossBests: buildBosses(db),
  };

  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(path.join(OUT_DIR, "codex.json"), JSON.stringify(data, null, 2) + "\n");
  fs.writeFileSync(path.join(OUT_DIR, "codex.md"), renderMarkdown(data));

  const pieces = KINDS.reduce((n, kind) => n + data.jewelry[kind].length, 0);
  const abilities = Object.values(data.abilities).reduce((n, l) => n + l.length, 0);
  const bosses = Object.values(data.bossBests).reduce((n, l) => n + l.length, 0);
  console.log(`Codex built: ${pieces} jewelry pieces, ${abilities} abilities, ${bosses} boss times -> docs/codex.md, docs/codex.json`);
}

main();
