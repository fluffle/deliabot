-- An Item has the following fields:
--   - id (string): the ID:DMG of the item
--   - name (string): descriptive name of item e.g. "Zucchini Bake"
--   - class (string): the class of the item e.g. "item.PamHarvestCraft:zucchinibakeItem"
--   - index (int): if this item exists in a barrel, index of that barrel
--   - pos (int): if this item exists in a barrel, pos of that barrel
--   - recipes (table): array of Recipes (see recipes.lua)
--   - pruned (table): array of makeable Recipes.
--   - _makeable (bool}: Whether this item is makeable (for makeable() caching)
--   - istool (bool): Whether this item is a harvestcraft tool.
Item = {}
function Item:new(item)
    item = item or {}
    item.recipes = item.recipes or {}
    setmetatable(item, self)
    self.__index = self
    return item
end

function Item:fromline(line)
    local _, _, id = line:find('!(%S+)')
    local _, _, class = line:find('U=([^|]+)')
    local _, e = line:find('L=')
    if id ~= nil and class ~= nil and e ~= nil then
        local name = line:sub(e+1)
        return Item:new{id=id, name=name, class=class}
    end
end

function Item:addrecipe(rcp)
    table.insert(self.recipes, rcp)
end

function Item:clearrecipes()
    self.recipes = {}
end

function Item:cost()
    -- The make "cost" of an item in a barrel is:
    if self.index and self.pos then
        return self.index * 2 + math.ceil(self.pos/2)
    end
end

function Item:makeable()
    if #self.recipes == 0 then return false end
    if self._makeable ~= nil then
        -- We've done this lookup already. Yay caching.
        return self._makeable
    end
    self.pruned = {}
    self._makeable = true
    for i, rcp in ipairs(self.recipes) do
        if rcp:makeable() then
--            print(string.format('Recipe %d is makeable for %s.', i, self.name))
            table.insert(self.pruned, rcp)
        end
    end
    if #self.pruned == 0 then
        self._makeable = false
    end
    return self._makeable
end

function Item:serialize(s)
    s:write('Item:new {')
    for _, elem in ipairs({'id', 'name', 'class'}) do
        if self[elem] then
            s:write('%s = %q,', elem, self[elem])
        end
    end
    if self.index and self.pos then
        s:write('index = %d,', self.index)
        s:write('pos = %d,', self.pos)
    end
    if self.istool then s:write('istool = true,') end
    for n, t in pairs({recipes = self.recipes, pruned = self.pruned}) do
        if next(t) then
            s:write('%s = {', n)
            for _, rcp in ipairs(t) do
                rcp:serialize(s)
                s:write(',')
            end
            s:write('},')
        end
    end
    s:partial('}')
end

function Item:resolve(itemset)
    for _, t in ipairs({self.recipes, self.pruned}) do
        if next(t) then
            for _, rcp in ipairs(t) do rcp:resolve(itemset) end
        end
    end
end

-- An ItemSet maps ID:DMGs to Items.
ItemSet = {}
function ItemSet:new(is)
    is = is or {}
    setmetatable(is, self)
    self.__index = self
    return is
end

function ItemSet:fromfile(file)
    local is = ItemSet:new()
    local fh = assert(io.open(file, 'r'))
    for line in fh:lines() do
        item = Item:fromline(line)
        if item then
            is[item.id] = item
        end
    end
    fh.close()
    return is
end

function ItemSet:insert(item)
    self[item.id] = item
    return self
end

function ItemSet:remove(item)
    assert(self[item.id], "Removing nonexistent item.")
    self[item.id] = nil
    return self
end

function ItemSet:mergefrom(is)
    for id, item in pairs(is) do
        self[id] = item
    end
    return self
end

function ItemSet:filter(filter)
    local is = ItemSet:new()
    for id, item in pairs(self) do
        if filter(item) then
            is[id] = item
        end
    end
    return is
end

function ItemSet:exists(item)
    return self[item.id]
end

function ItemSet:item(id)
    return self[id]
end

function ItemSet:name(id)
    if self[id] then
        return self[id].name
    end
end

function ItemSet:serialize(s)
    s:write('ItemSet:new {')
    local ids = {}
    for id, _ in pairs(self) do
        table.insert(ids, id)
    end
    table.sort(ids, function(a,b)
        local _, _, aid, admg = a:find('(%d+):(%d+)')
        local _, _, bid, bdmg = b:find('(%d+):(%d+)')
        aid, admg, bid, bdmg = tonumber(aid), tonumber(admg), tonumber(bid), tonumber(bdmg)
        return aid < bid or aid == bid and admg < bdmg
    end)
    for _, id in ipairs(ids) do
        s:partial('[%q] = ', id)
        self[id]:serialize(s)
        s:write(',')
    end
    s:partial('}')
end

-- A serialized itemset is flat, this restores the links between
-- recipe inputs and items.
function ItemSet:resolve()
    for _, item in pairs(self) do item:resolve(self) end
end
