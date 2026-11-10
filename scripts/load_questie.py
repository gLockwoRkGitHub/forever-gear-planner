"""Load QuestieDB Forever data (Era seed + generated Forever delta) into plain JSON.

Lua is evaluated in a sandboxed environment (no os/io/require).
Usage: python3 -I load_questie.py <questiedb_dir> <delta_dir> <out_json>
"""
import json
import sys
from pathlib import Path

import lupa

QDB, DELTA, OUT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
make_env = lua.eval("""
function()
  local env = {pairs=pairs, ipairs=ipairs, type=type, tostring=tostring, tonumber=tonumber,
               string=string, table=table, math=math, next=next, select=select, unpack=table.unpack}
  return env
end
""")
sandbox_load = lua.eval("""
function(code, name, env, ...)
  local fn, err = load(code, name, "t", env)
  if not fn then error(err) end
  return fn(...)
end
""")

# Enum constants used by the generated delta files (zoneIDs, sortKeys from the repo's enum files)
ENUM_DIR = QDB / "src" / "corrections" / "enum"
enum_lib = lua.table()
enum_lib["Enum"] = lua.table()
for enum_file in ("zones.lua", "quests.lua"):
    sandbox_load(Path(ENUM_DIR / enum_file).read_text(encoding="utf-8"), enum_file, make_env(), None, enum_lib)
ENUM = enum_lib["Enum"]

RACE_KEYS = {
    "NONE": 0, "HUMAN": 1, "ORC": 2, "DWARF": 4, "NIGHT_ELF": 8, "UNDEAD": 16, "TAUREN": 32,
    "GNOME": 64, "TROLL": 128, "GOBLIN": 256, "SKYBORNE_ALLIANCE": 2**32, "SKYBORNE_HORDE": 2**33,
}
RACE_KEYS["ALL_ALLIANCE"] = 1 + 4 + 8 + 64 + 2**32
RACE_KEYS["ALL_HORDE"] = 2 + 16 + 32 + 128 + 2**33
CLASS_KEYS = {"NONE": 0, "WARRIOR": 1, "PALADIN": 2, "HUNTER": 4, "ROGUE": 8, "PRIEST": 16,
              "SHAMAN": 64, "MAGE": 128, "WARLOCK": 256, "DRUID": 1024, "ALL_CLASSES": 1503}


def py_table(d):
    t = lua.table()
    for k, v in d.items():
        t[k] = v
    return t


def read(path):
    return Path(path).read_text(encoding="utf-8")


def lua_to_py(v):
    if lupa.lua_type(v) == "table":
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [lua_to_py(v[k]) for k in keys]
        return {k: lua_to_py(v[k]) for k in keys}
    return v


def extract_keys_and_data(path, keys_name, data_name):
    text = read(path)
    # keys table
    start = text.index(f"QuestieDB.{keys_name} = {{")
    end = text.index("\n}", start) + 2
    keys_code = "return " + text[start + len(f"QuestieDB.{keys_name} = "):end]
    keys = lua_to_py(sandbox_load(keys_code, keys_name, make_env()))
    dstart = text.index(f"QuestieDB.{data_name} = [[") + len(f"QuestieDB.{data_name} = [[")
    dend = text.index("]]", dstart)
    data = sandbox_load(text[dstart:dend], data_name, make_env())
    return keys, data


def load_delta(path, keys_map):
    """keys_map: {'itemKeys': {...}} -> returns {id: {field: value | ('add', value)}}"""
    text = read(path)
    env = make_env()
    # Build key tables where "<field>_add" maps to a marker string
    qdb = lua.table()
    for kname, kdict in keys_map.items():
        t = lua.table()
        for field, idx in kdict.items():
            t[field] = idx
            t[field + "_add"] = f"add:{idx}"
        qdb[kname] = t
    qdb["raceKeys"] = py_table(RACE_KEYS)
    qdb["classKeys"] = py_table(CLASS_KEYS)
    qdb["sortKeys"] = ENUM["sortKeys"]
    modules = lua.table()
    loader = lua.table()
    lua.execute("""
    function __mk_loader(loader, modules, qdb)
      loader.CreateModule = function(self, name) local m = {}; modules[name] = m; return m end
      loader.ImportModule = function(self, name)
        if name == "QuestieDB" then return qdb end
        if name == "ZoneDB" then return {zoneIDs = __zoneIDs} end
        return {}
      end
    end
    """)
    lua.globals()["__zoneIDs"] = ENUM["zoneIDs"]
    lua.globals().__mk_loader(loader, modules, qdb)
    env["QuestieLoader"] = loader
    sandbox_load(text, str(path), env)
    mod = next(iter(modules.values()))
    result = mod.Load(mod)
    out = {}
    for item_id in result.keys():
        entry = result[item_id]
        fields = {}
        for k in entry.keys():
            fields[str(k)] = lua_to_py(entry[k])
        out[int(item_id)] = fields
    return out


def apply_delta(base_rows, delta):
    for rid, fields in delta.items():
        row = base_rows.setdefault(rid, {})
        for k, v in fields.items():
            if k.startswith("add:"):
                idx = int(k[4:])
                cur = row.get(idx) or []
                if isinstance(v, list):
                    row[idx] = list(cur) + [x for x in v if x not in cur]
                else:
                    row[idx] = v
            else:
                row[int(k)] = v


def rows_to_py(data):
    rows = {}
    for rid in data.keys():
        r = data[rid]
        row = {}
        for k in r.keys():
            row[int(k)] = lua_to_py(r[k])
        rows[int(rid)] = row
    return rows


result = {}
for kind, fname, kname, dname, dfile in [
    ("items", "foreverItemDB.lua", "itemKeys", "itemData", "foreverBaseItem.lua"),
    ("quests", "foreverQuestDB.lua", "questKeys", "questData", "foreverBaseQuest.lua"),
    ("npcs", "foreverNpcDB.lua", "npcKeys", "npcData", "foreverBaseNpc.lua"),
    ("objects", "foreverObjectDB.lua", "objectKeys", "objectData", "foreverBaseObject.lua"),
]:
    keys, data = extract_keys_and_data(QDB / "data" / "Forever" / fname, kname, dname)
    rows = rows_to_py(data)
    delta = load_delta(DELTA / dfile, {kname: keys})
    apply_delta(rows, delta)
    inv = {v: k for k, v in keys.items()}
    named = {}
    for rid, row in rows.items():
        named[rid] = {inv[i]: v for i, v in row.items() if i in inv and v is not None}
    result[kind] = named
    print(kind, len(rows), "rows,", len(delta), "delta entries")

OUT.write_text(json.dumps(result), encoding="utf-8")
print("written", OUT)
