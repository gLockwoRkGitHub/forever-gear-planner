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

## How it updates

| Workflow | When | What it does |
|---|---|---|
| `deploy.yml` | every hour, on push, manually | Fetches level and equipped gear of both characters, builds the page, encrypts it with the password, publishes it on GitHub Pages |
| `update-items.yml` | weekly (Monday), manually | Rebuilds the item database from the newest game data, commits `data/items.js`, then runs `deploy.yml` |

Character data comes from the **Blizzard API** when the Blizzard secrets are set, otherwise from
[armorywowforever.com](https://armorywowforever.com). If a fetch fails, the last good result is used and
marked as older. WoW Forever has no realms: the API addresses characters as
`/profile/wow/character/{name}-{surname}` in the `profile-forever-{region}` namespace. Characters show up
there from level 10, after logging out once.

To check the fetched data, run *Build and deploy* manually with **Log every fetched item** ticked: the log
then lists every equipped item with its stats (Blizzard and armory side by side).

Item data comes from the WoW Forever game tables on [wago.tools](https://wago.tools), quest, NPC and vendor
data from [QuestieDB](https://github.com/Questie/QuestieDB), and item tooltips from
[Wowhead](https://www.wowhead.com/forever).

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
