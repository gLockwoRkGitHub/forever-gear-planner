# Forever Suite (in-game addon)

The planner inside WoW Forever. The addon carries the whole item database and the same ranking and level
model as the website, and works with the character's live level and gear.

**Download:** [ForeverSuite.zip](https://github.com/gLockwoRkGitHub/forever-gear-planner/releases/download/addon/ForeverSuite.zip)
(rebuilt with every item data update). Unzip into `World of Warcraft/_forever_/Interface/AddOns`; the folder
`ForeverSuite` goes directly in there. In the game: `/fs`, or the book icon at the minimap.

## Modules

Every module can be switched off on the Settings tab or with `/fs module <id> off`.

| Module | id | What it does |
|---|---|---|
| Gear planner | `planner` | Gear tab: per slot what you wear and the best upgrades for your level (or a level you pick), where they drop, the next upgrade within 3 levels. Finished quests are left out, items in your bags are marked. |
| Dungeon guide | `dungeon` | Dungeons tab: dungeons ranked by upgrades for you and your partner, boss by boss who gains what. Entering a dungeon prints a summary and opens the tab. |
| Tooltip scores | `tooltip` | Every item tooltip: `Forever Suite  You +4.2 · Tato +6.1`. |
| Best quest reward | `questreward` | Gold star on the best reward, a coin on the most valuable one when nothing is an upgrade. |
| Quest sync | `questsync` | Quests tab: what your partner has done that you have not, and the other way round. |
| Partner sync | `partner` | In a group, both addons swap level, gear, character sheet, talents and settings, so each sees the other's scores. The last state is kept for when the partner is offline. |
| Loot hints | `loothints` | On a loot roll or in the loot window: who gains how much. |

New ideas become new modules: `FS:NewModule(id, { title, desc, order })` with `OnInitialize`, `OnEnable`,
`OnDisable`, `self:RegisterEvent(...)` and `self:Listen(...)` (internal messages such as `STATE_CHANGED`,
`PARTNER_CHANGED`, `COMM_<kind>`). A tab is added with `FS.Window:AddTab(id, title, order, builder, moduleId)`.

## What comes from where

| | Source |
|---|---|
| Items, sources, ability ranks | Built into the addon (`scripts/build_addon.py` from `data/items.js`, `data/mechanics.json`) |
| Level, gear (exact random-suffix stats), bags, finished quests, professions, character sheet | The game, live |
| Talents | The game on English clients; otherwise the website import |
| Stat-weight preset, custom weights, filters | Settings tab, or taken over from the website import |

**Website import:** planner page, tab *Addon*, *Text fürs Addon kopieren*; in the game `/fs import`, paste,
*Import*. Repeat after spending talent points. The text holds both characters; each client uses the one
for its class.

WoW Forever runs the retail addon API with Midnight's restrictions: combat values are secret, so nothing
reads the combat log (a crit leaderboard is not possible). Addon messages wait until you are out of combat.

## Development

```bash
python scripts/build_addon.py      # -> build/addon/ForeverSuite and build/ForeverSuite.zip
node addon/tests/parity.js         # runs the website's ranking for test scenarios -> addon/tests/expected.lua
lua5.1 addon/tests/run.lua         # loads the addon in a mocked client: same results as the website, every module runs
```

The workflow `addon.yml` runs these steps and publishes the zip. `Model.lua` is a port of `site/model.js`
and `Engine.lua` of the ranking in `site/app.js`; the parity test fails when they drift apart.
The interface version in `ForeverSuite.toc` is 16001 (client 1.60.1); raise it when Forever patches.
