#!/usr/bin/env node
// Renders docs/items.md and SurvivorUI/ItemDetails.lua (the Codex's catalog,
// for pieces not yet worn) from docs/items.json: the game's own item details
// (the armory's Details pages), transcribed from screenshots.
//
// Usage:
//   node tools/build-items.js [path\to\AzerothSurvivors.exe]
//
// Given the game, each piece's icon is read from its data (its key, name
// and icon run together: "accuriaBand of AccuriaINV_Jewelry_Ring_15") and
// kept in items.json, so later builds need no game.
//
// Rings and trinkets list what a new one gives at each rarity. Amulets list
// their lines and, beside them, what they reach empowered: "its numbers grow
// toward three times their own", read as three times each amount (a
// percentage, or a figure like 6.0 health) but not a count, a limit or a
// time ("1 more enemy", "2 times a second", "60 sec", "5 yd"), nor a health
// threshold ("leaves you at 50% health").

"use strict";

const fs = require("fs");
const path = require("path");

const DOCS = path.join(__dirname, "..", "docs");
const ADDON = path.join(__dirname, "..", "SurvivorUI");
const DEFAULT_GAME = "C:\\Users\\nicho\\Downloads\\AzerothSurvivors\\AzerothSurvivors\\AzerothSurvivors.exe";
const SAVED = "C:\\Git\\wenilla\\benilla-config\\saved\\SurvivorUI.lua";  // the Codex's recorded icons, where at hand
const data = JSON.parse(fs.readFileSync(path.join(DOCS, "items.json"), "utf8"));

function allPieces() {
  return [...data.rings, ...data.trinkets, ...data.amulets];
}

// The icon after a piece's name in the game's data. The icon runs into what
// follows: the next piece's key and name ("Spell_Nature_AbolishMagictep
// Talisman of..."), a line's text ("+{v}% damage"), or a word after a number
// ("INV_Jewelry_Ring_49Naxxramas"); it ends at the first of those.
function readIcons(game) {
  const knownIcons = new Set();
  const talentIcons = fs.readFileSync(path.join(ADDON, "TalentIcons.lua"), "utf8");
  for (const m of talentIcons.matchAll(/Icons\\\\([A-Za-z0-9_]+)"/g)) knownIcons.add(m[1]);
  if (fs.existsSync(SAVED)) {
    for (const m of fs.readFileSync(SAVED, "utf8").matchAll(/Icons\\\\([A-Za-z0-9_]+)"/g)) knownIcons.add(m[1]);
  }
  const bytes = fs.readFileSync(game);
  const text = bytes.toString("latin1");
  const names = allPieces().map((p) => p.name);
  const nextName = new RegExp("^[a-z_]+(?:" + names.map((n) => n.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|") + ")");
  const found = {};
  for (const name of names) {
    let at = text.indexOf(name + "INV_");
    for (const prefix of ["Spell_", "Ability_", "Trade_"]) if (at < 0) at = text.indexOf(name + prefix);
    if (at < 0) continue;
    const run = /^[\x20-\x7e]+/.exec(text.slice(at + name.length))[0];
    // The first plain stop: a line's text ("+{v}%", "Each kill heals"). A
    // word after a number is no stop: some icons end so
    // ("INV_Jewelry_Ring_49Naxxramas").
    let end = run.length;
    for (let i = 5; i < run.length; i++) {
      const rest = run.slice(i);
      if (/^[+\-{]/.test(rest) || /^[A-Z][a-z]+ /.test(rest)) {
        end = i;
        break;
      }
    }
    // Before that stop the next piece's key and name may start. Where they
    // could start at several places: an icon the addon already knows (the
    // talents', or one the Codex recorded) settles it; else a key that
    // starts after a number ("Pearl_05|hoj|Hand of Justice"); else the
    // shortest key.
    const cuts = [];
    for (let i = 5; i < end; i++) {
      if (/[a-z]/.test(run[i]) && nextName.test(run.slice(i, end + 200))) cuts.push(i);
    }
    const known = cuts.find((i) => knownIcons.has(run.slice(0, i)));
    const afterNumber = cuts.find((i) => /\d/.test(run[i - 1]));
    if (known !== undefined) end = known;
    else if (afterNumber !== undefined) end = afterNumber;
    else if (cuts.length) end = cuts[cuts.length - 1];
    found[name] = run.slice(0, end);
  }
  return found;
}

function md(text) {
  return String(text).replace(/([\\`*_|<>\[\]])/g, "\\$1");
}

function tripled(value, decimals) {
  const n = value * 3;
  return decimals ? n.toFixed(decimals) : String(Math.round(n * 10) / 10);
}

// A line at three times its amounts.
function empowered(line) {
  return line.replace(/(\d+(?:\.(\d+))?)(%?)/g, (whole, number, decimals, percent, at, text) => {
    const before = text.slice(0, at);
    const after = text.slice(at + whole.length);
    if (percent && /^\s*health instead/.test(after)) return whole;
    if (percent || decimals) return tripled(parseFloat(number), decimals ? decimals.length : 0) + percent;
    return whole;
  });
}

function rankedTable(pieces) {
  const out = [];
  for (const piece of pieces) {
    out.push(`#### ${md(piece.name)}`, "", `*${md(piece.kind)}*`, "");
    out.push("| Rarity | A new one |", "| --- | --- |");
    piece.byRarity.forEach((value, index) => out.push(`| ${data.rarities[index]} | ${md(value)} |`));
    out.push("", `Picked again: ${md(piece.again)}`, "");
  }
  return out;
}

function lua(text) {
  return '"' + String(text).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

// The addon's copy: by the Codex's kinds (Ring, Trinket, Neck), by name.
function writeLua() {
  const lines = [
    "-- Survivor UI: the game's own item details (the armory's Details pages),",
    "-- by Codex kind and name, generated by tools/build-items.js from",
    "-- docs/items.json; edit the JSON, not this file. The Codex fills in from it",
    "-- what the hero has not recorded: pieces never worn, a ring's or trinket's",
    "-- worth at each rarity, an amulet's empowered ceiling.",
    "",
    "SurvivorUI_ITEM_DETAILS = {",
  ];
  const ranked = (kind, pieces) => {
    lines.push(`\t${kind} = {`);
    for (const piece of pieces) {
      lines.push(`\t\t[${lua(piece.name)}] = {`);
      lines.push(`\t\t\tkind = ${lua(piece.kind)},`);
      if (piece.icon) lines.push(`\t\t\ticon = ${lua("Interface\\Icons\\" + piece.icon)},`);
      lines.push(`\t\t\tbyRarity = { ${piece.byRarity.map(lua).join(", ")} },`);
      lines.push(`\t\t\tagain = ${lua(piece.again)},`);
      lines.push("\t\t},");
    }
    lines.push("\t},");
  };
  ranked("Ring", data.rings);
  ranked("Trinket", data.trinkets);
  lines.push("\tNeck = {");
  for (const amulet of data.amulets) {
    lines.push(`\t\t[${lua(amulet.name)}] = {`);
    lines.push(`\t\t\trarity = ${lua(amulet.rarity)},`);
    if (amulet.icon) lines.push(`\t\t\ticon = ${lua("Interface\\Icons\\" + amulet.icon)},`);
    lines.push(`\t\t\tlines = { ${amulet.lines.map(lua).join(", ")} },`);
    lines.push(`\t\t\tempowered = { ${amulet.lines.map((line) => lua(empowered(line))).join(", ")} },`);
    lines.push("\t\t},");
  }
  lines.push("\t},", "}", "");
  fs.writeFileSync(path.join(ADDON, "ItemDetails.lua"), lines.join("\n"));
}

function main() {
  // Icons from the game, where it is at hand, kept in the JSON.
  const game = process.argv[2] || DEFAULT_GAME;
  if (fs.existsSync(game)) {
    const icons = readIcons(game);
    let added = 0;
    for (const piece of allPieces()) {
      if (icons[piece.name] && piece.icon !== icons[piece.name]) {
        piece.icon = icons[piece.name];
        added++;
      }
    }
    if (added) fs.writeFileSync(path.join(DOCS, "items.json"), JSON.stringify(data, null, 2) + "\n");
    const missing = allPieces().filter((p) => !p.icon).map((p) => p.name);
    console.log(`icons: ${added} read from the game` + (missing.length ? `; none for ${missing.join(", ")}` : ""));
  }
  writeLua();

  const out = [];
  out.push("# Survivor UI: item details", "");
  out.push(
    "The game's own item details (the armory's Details pages), transcribed from screenshots. " +
      "Generated by `tools/build-items.js` from `docs/items.json`; edit the JSON, not this page.",
    ""
  );
  out.push("- [Rings](#rings)", "- [Trinkets](#trinkets)", "- [Amulets](#amulets)", "");

  out.push("## Rings", "", "What a new one gives at each rarity, and how picking it again grows it.", "");
  out.push(...rankedTable(data.rings));
  out.push("## Trinkets", "", "What a new one gives at each rarity, and how picking it again grows it.", "");
  out.push(...rankedTable(data.trinkets));

  out.push("## Amulets", "");
  out.push(
    "Each comes at one rarity. Offered again while worn, it is empowered: its numbers grow toward three " +
      "times their own. *Empowered* below is that ceiling, read as three times each amount (not counts, " +
      "limits, times or a health threshold).",
    ""
  );
  for (const rarity of data.rarities) {
    const amulets = data.amulets.filter((a) => a.rarity === rarity);
    if (!amulets.length) continue;
    out.push(`### ${rarity}`, "", "| Amulet | Gives | Empowered |", "| --- | --- | --- |");
    for (const amulet of amulets) {
      const gives = amulet.lines.map(md).join("<br>");
      const most = amulet.lines.map((line) => md(empowered(line))).join("<br>");
      out.push(`| ${md(amulet.name)} | ${gives} | ${most} |`);
    }
    out.push("");
  }

  fs.writeFileSync(path.join(DOCS, "items.md"), out.join("\n"));
  console.log(`items.md: ${data.rings.length} rings, ${data.trinkets.length} trinkets, ${data.amulets.length} amulets`);
}

main();
