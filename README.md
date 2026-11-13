# Forever Gear Planner

A leveling gear planner for **World of Warcraft: Forever**, for two characters:

| Profile | Character | Spec |
|---|---|---|
| Shaman | Koda Ashmane (EU, normal) | Tauren Enhancement, two-handers only |
| Druid | Tato Mcpaw (EU, normal) | Tauren Feral (Cat / Bear) |

For every slot it ranks the best Quest, Dungeon, Vendor and Crafted items for the character's level, shows
what is equipped right now and how much each item would be an upgrade. A dungeon tab ranks dungeons by how
many upgrades they hold. The page works on phones.

The published page is password protected and only readable with the password.

**In the game:** the addon [Forever Suite](addon/README.md) brings the planner into WoW Forever: best upgrades
per slot for the live level and gear, upgrade scores in tooltips, best quest reward, dungeon guide, loot hints,
and gear and quest sync with your partner. [Download the zip](https://github.com/gLockwoRkGitHub/forever-gear-planner/releases/download/addon/ForeverSuite.zip).

## How it updates

| Workflow | When | What it does |
|---|---|---|
| `deploy.yml` | every hour, on push, manually | Fetches level and equipped gear of both characters, builds the page, encrypts it with the password, publishes it on GitHub Pages |
| `update-items.yml` | weekly (Monday), manually | Rebuilds the item database from the newest game data, commits `data/items.js`, then runs `deploy.yml` and `addon.yml` |
| `addon.yml` | after the item update, on addon changes, manually | Builds the addon zip, tests it against the website's ranking, publishes it on the release `addon` |

Character data comes from the **Blizzard API** when the Blizzard secrets are set, otherwise from
[armorywowforever.com](https://armorywowforever.com). If a fetch fails, the last good result is used and
marked as older. WoW Forever has no realms: the API addresses characters as
`/profile/wow/character/{name}-{surname}` in the `profile-forever-{region}` namespace. Characters show up
there from level 10, after logging out once.

To check the fetched data, run *Build and deploy* manually with **Log every fetched item** ticked: the log
then lists every equipped item with its stats (Blizzard and armory side by side).

Item data comes from the WoW Forever game tables on [wago.tools](https://wago.tools), quest, NPC and vendor
data (also the dungeon quest lines with their pre-quests, `data/dungeon_quests.json`) from [QuestieDB](https://github.com/Questie/QuestieDB), and item tooltips from
[Wowhead](https://www.wowhead.com/forever).

## Level model

The default stat weights are computed per character and level (`site/model.js`): how fast the character kills
a typical mob two levels below (health from QuestieDB x1.3), with every fight starting with cooldowns ready (and a
cat with full energy). Inputs: talents and character sheet (Blizzard API) and the ability ranks in the game
data (`data/mechanics.json`, built by `scripts/extract_mechanics.py`). Each weight is the extra kill speed of
one point of a stat, counted in Strength points; two-handers are valued by their damage and speed directly.

- Shaman: Stormstrike opens (100% weapon damage, 8 sec cooldown), Earth Shock after the global cooldown and
  every 6 sec, Improved Stormstrike resets, auto attacks with Flurry. Windfury Weapon from 30 and Windfury Totem
  from 32 roll on every hit (counted in a third of the fights, as in the log); Mental Dexterity turns 33/66/100%
  of Intellect into attack power by rank. Calibrated with Koda's advanced combat log (13 Nov 2026, level 35,
  107 solo kills): quest mobs 2 levels below, 1.3x Classic health, ~1,200-1,600 armor at 30-37 (~28% physical
  reduction), Earth Shock without level scaling, Stormstrike 1.04x its weapon damage, Windfury Totem in about a
  third of the fights. Model vs log: kill time 12.5 vs 12.6 sec, damage split within 3 points.
- Hotfixes the game tables on wago.tools do not show yet are applied in `scripts/extract_mechanics.py`
  (`HOTFIXES`, `MENTAL_DEXTERITY`): currently Blizzard's hotfix of 10 Nov 2026 (Stormstrike 150% → 100%,
  6 → 8 sec; Mental Dexterity 50/100/150% → 33/66/100%; Windfury Weapon and Windfury Totem together). The
  Blizzard API's talent tooltips still show the old Mental Dexterity values, so the model goes by the rank.
- Druid (Cat Form, from 20): 100 energy at the start plus 10 per second, Rake, Claw, Ferocious Bite at 5 combo
  points; the cat's auto attack is assumed to do the weapon's damage per second (not yet checked with a log).
- Not modelled: mana, downtime, buffs, special item effects.

## Setup

1. **Secrets** – *Settings → Secrets and variables → Actions → New repository secret*

   | Name | Required | Value |
   |---|---|---|
   | `PAGE_PASSWORD` | yes | The password for the page (a long passphrase is best) |
   | `BLIZZARD_CLIENT_ID` | no | Client ID of an API client from [develop.battle.net](https://develop.battle.net/access/clients) |
   | `BLIZZARD_CLIENT_SECRET` | no | Client secret of that API client |

2. **Pages** – *Settings → Pages → Build and deployment → Source: GitHub Actions*
3. **First run** – *Actions → Build and deploy → Run workflow*

The page is then at `https://glockworkgithub.github.io/forever-gear-planner/`.

To change the password, update the `PAGE_PASSWORD` secret and run *Build and deploy* again. Devices that
chose "Remember me" have to enter the new password once.

## Characters

Edit `characters.json` to change who is tracked (`key` is the planner profile: `shaman` or `druid`).

## Running it locally

```bash
pip install -r requirements.txt
python scripts/build_items.py      # item database -> data/items.js (a few minutes on first run)
python scripts/fetch_gear.py       # levels and gear -> build/gear.json
python scripts/build_site.py       # page -> build/index.html (unencrypted, open it in a browser)
```

## Notes

- Random-suffix items ("of the Gorilla") get exact stats from the Blizzard API; without it (armory) they are
  estimated.
- Around 40% of WoW Forever items are hidden in the game data until someone discovers them, so the item list
  grows with the weekly update.
- GitHub pauses scheduled workflows after 60 days without repository activity. The weekly item commit keeps
  the repository active; if nothing changed for a long time, re-enable the workflow under *Actions*.
