-- 背包資料模型。每個 inventory 是 stack 陣列：{ {id, count}, ... }
-- 重量上限以公斤計，超過上限不能再放。撿到無法塞下時應提示玩家。
--
-- 物品 def 來自 src/items.lua（傳入避免循環依賴）。
local items = require("src.items")

local M = {}

function M.new(opts)
  return {
    stacks = {},
    weightLimit = (opts and opts.weightLimit) or 30, -- 公斤
    slotLimit = (opts and opts.slotLimit) or 16,
  }
end

function M.weight(inv)
  local w = 0
  for _, s in ipairs(inv.stacks) do
    local def = items.def(s.id)
    if def then w = w + def.weight * s.count end
  end
  return w
end

function M.isFull(inv)
  return #inv.stacks >= inv.slotLimit
end

-- 嘗試加入物品。回傳 added (數量), overflow (沒能塞下的數量)
function M.add(inv, id, count)
  local def = items.def(id)
  if not def or count <= 0 then return 0, count or 0 end
  local remaining = count
  -- 先補既有 stack
  for _, s in ipairs(inv.stacks) do
    if s.id == id and s.count < def.stackMax then
      local space = def.stackMax - s.count
      local canFit = math.floor((inv.weightLimit - M.weight(inv)) / def.weight)
      local n = math.min(space, remaining, canFit)
      if n > 0 then
        s.count = s.count + n
        remaining = remaining - n
        if remaining <= 0 then return count, 0 end
      end
    end
  end
  -- 開新 stack
  while remaining > 0 and #inv.stacks < inv.slotLimit do
    local canFit = math.floor((inv.weightLimit - M.weight(inv)) / def.weight)
    if canFit <= 0 then break end
    local n = math.min(def.stackMax, remaining, canFit)
    if n <= 0 then break end
    table.insert(inv.stacks, { id = id, count = n })
    remaining = remaining - n
  end
  return count - remaining, remaining
end

function M.remove(inv, id, count)
  local need = count
  for i = #inv.stacks, 1, -1 do
    local s = inv.stacks[i]
    if s.id == id then
      local n = math.min(s.count, need)
      s.count = s.count - n
      need = need - n
      if s.count <= 0 then table.remove(inv.stacks, i) end
      if need <= 0 then return count end
    end
  end
  return count - need
end

function M.countOf(inv, id)
  local n = 0
  for _, s in ipairs(inv.stacks) do
    if s.id == id then n = n + s.count end
  end
  return n
end

-- 用第 idx 個 stack 的物品（必須是 consumable 且 def.onUse 回傳 true 才扣）
function M.useStack(inv, idx, player)
  local s = inv.stacks[idx]
  if not s then return false end
  local def = items.def(s.id)
  if not def or def.kind == "key" or not def.onUse then return false end
  local ok = def.onUse(player)
  if ok then
    s.count = s.count - 1
    if s.count <= 0 then table.remove(inv.stacks, idx) end
  end
  return ok
end

-- 用 id 找第一個可用的 stack 並使用（HUD 快捷鍵用）
function M.useFirst(inv, id, player)
  for i, s in ipairs(inv.stacks) do
    if s.id == id then
      return M.useStack(inv, i, player)
    end
  end
  return false
end

-- 把整個 stack 移到 dst（如儲物箱）；回傳實際搬走數量
function M.moveStack(src, idx, dst)
  local s = src.stacks[idx]
  if not s then return 0 end
  local moved, _ = M.add(dst, s.id, s.count)
  if moved > 0 then
    s.count = s.count - moved
    if s.count <= 0 then table.remove(src.stacks, idx) end
  end
  return moved
end

-- 從 loot table 隨機抽一份戰利品，附加到 inv，回傳被加入的清單 (給訊息用)
function M.lootFromTable(inv, lootTable)
  local rng = love.math.random
  local rollMin, rollMax = lootTable.rolls[1], lootTable.rolls[2]
  local rolls = rng(rollMin, rollMax)
  local totalWeight = 0
  for _, e in ipairs(lootTable.pool) do totalWeight = totalWeight + e.weight end
  local added = {}
  for _ = 1, rolls do
    local r = rng() * totalWeight
    local pick
    for _, e in ipairs(lootTable.pool) do
      r = r - e.weight
      if r <= 0 then pick = e; break end
    end
    pick = pick or lootTable.pool[1]
    local count = rng(pick.min, pick.max)
    local got, overflow = M.add(inv, pick.id, count)
    if got > 0 then
      table.insert(added, { id = pick.id, count = got })
    end
    if overflow > 0 then
      -- 背包滿了，丟在地上的概念：本原型直接記為「overflow」，UI 可提示
      table.insert(added, { id = pick.id, count = overflow, overflow = true })
    end
  end
  return added
end

-- 嘗試合成。inv 必須擁有 recipe 所有 inputs，且輸出能塞下背包。
-- 回傳 ok, message
function M.craft(inv, recipe)
  for _, inp in ipairs(recipe.inputs) do
    if M.countOf(inv, inp.id) < inp.count then
      return false, "材料不足"
    end
  end
  -- 預估合成後重量是否會爆
  local outDef = items.def(recipe.output.id)
  local removeWeight = 0
  for _, inp in ipairs(recipe.inputs) do
    local d = items.def(inp.id)
    if d then removeWeight = removeWeight + d.weight * inp.count end
  end
  local addWeight = outDef.weight * recipe.output.count
  if M.weight(inv) - removeWeight + addWeight > inv.weightLimit then
    return false, "合成後超重"
  end
  for _, inp in ipairs(recipe.inputs) do
    M.remove(inv, inp.id, inp.count)
  end
  local got, overflow = M.add(inv, recipe.output.id, recipe.output.count)
  if got <= 0 then
    -- 不太可能發生，但安全起見把材料還回
    for _, inp in ipairs(recipe.inputs) do
      M.add(inv, inp.id, inp.count)
    end
    return false, "背包滿了"
  end
  return true, ("合成 %s ×%d"):format(items.def(recipe.output.id).name, got)
end

-- 撤離結算：所有物品估價總和（金錢），ammo 不計入估價避免刷分
function M.appraise(inv)
  local total = 0
  for _, s in ipairs(inv.stacks) do
    local def = items.def(s.id)
    if def and def.kind ~= "ammo" then
      total = total + def.value * s.count
    end
  end
  return total
end

return M
