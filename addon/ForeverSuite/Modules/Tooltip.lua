-- Tooltip line: every item tooltip (bags, loot, vendors, quest rewards, chat links) shows what the item
-- is worth to you, and to your partner when their addon has sent their gear.
--   Forever Suite   You +4.2 · Tato +6.1
local _, FS = ...
local G, U = FS.Gear, FS.U
local S = G.State

local Tip = FS:NewModule("tooltip", {
  title = "Tooltip scores",
  desc = "Item tooltips show the upgrade score for you and your partner.",
  order = 30,
})

local SKIP = { ShoppingTooltip1 = true, ShoppingTooltip2 = true, ForeverSuiteScanTip = true }

local function part(st, v)
  local name = "|cff" .. st.prof.color .. (st.isSelf and "You" or st.short or st.name) .. "|r "
  if v.kind == "up" then return name .. U.colorDelta(v.delta) end
  if v.kind == "down" then return name .. U.colorDelta(v.delta) end
  if v.kind == "later" then return name .. "|cffffcc00lvl " .. v.from .. (v.delta and (" " .. U.delta(v.delta)) or "") .. "|r" end
  if v.kind == "equipped" then return name .. "|cff999999worn|r" end
  if v.kind == "relic" then return name .. "|cff999999relic|r" end
  return nil
end

-- the text for one item, or nil (cached per item and state version)
local cache, cacheKey = {}, nil
function Tip.Text(link)
  local it = G:ItemFromLink(link)
  if not it then return nil end
  local states = S:All()
  local key = ""
  for _, st in ipairs(states) do key = key .. (st.version or 0) .. ":" .. (st.liveLevel or 0) .. ";" end
  if key ~= cacheKey then cache, cacheKey = {}, key end
  local c = cache[it]
  if c ~= nil then return c or nil end
  local parts = {}
  for _, st in ipairs(states) do
    local v = G:Evaluate(st, it)
    local p = v and part(st, v)
    if p then parts[#parts + 1] = p end
  end
  local text = #parts > 0 and table.concat(parts, "  ·  ") or false
  cache[it] = text
  return text or nil
end

local function onTooltip(tooltip, data)
  if not Tip.enabled or not tooltip or SKIP[tooltip:GetName() or ""] then return end
  local link
  if tooltip.GetItem then
    local ok, _, l = pcall(tooltip.GetItem, tooltip)
    if ok then link = l end
  end
  if (not link or U.secret(link)) and type(data) == "table" then
    link = (not U.secret(data.hyperlink) and data.hyperlink) or (data.id and not U.secret(data.id) and ("item:" .. data.id)) or nil
  end
  if not link or U.secret(link) then return end
  local ok, text = pcall(Tip.Text, link)
  if ok and text then
    tooltip:AddDoubleLine("|cffd9a441Forever Suite|r", text)
  end
end

local hooked = false
local function hook()
  if hooked then return end
  hooked = true
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltip)
  else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
      if tt and tt.HookScript then pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) onTooltip(self) end) end
    end
  end
end

function Tip:OnEnable() hook() end
