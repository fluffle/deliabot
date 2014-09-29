-- An Item has the following fields:
--   - id (string): the ID:DMG of the item
--   - name (string): descriptive name of item e.g. "Zucchini Bake"
--   - class (string): the class of the item e.g. "item.PamHarvestCraft:zucchinibakeItem"
--   - usedin (table): LUT of ID:DMG->item where this item is a recipe ingredient
--   - recipes (table): array of Recipes (see recipes.lua)
Item = {}
function Item:new(id, name, class)
    local item = {id=id, name=name, class=class, usedin={}, recipes={}}
    setmetatable(item, self)
    self.__index = self
    return item
end

function Item:fromline(line)
    local _, _, id = line:find('!(%S+)')
    local _, _, cls = line:find('U=([^|]+)')
    local _, e = line:find('L=')
    if id ~= nil and cls ~= nil and e ~= nil then
        local name = line:sub(e+1)
        return Item:new(id, name, cls)
    end
end

function Item:setusedin(item)
    self.usedin[item.id] = item
    return self.usedin[item.id]
end

function Item:isusedin(id)
    return self.usedin[id]
end

function Item:addrecipe(rcp)
    table.insert(self.recipes, rcp)
end

function Item:clearrecipes()
    -- NOTE: this does not clean up the other direction of the graph.
    -- Maybe it should.
    self.recipes = {}
end

function Item:__tostring()
    local strs = {string.format('%s (%s=%s)', self.name, self.class, self.id)}
    if next(self.usedin) then
        table.insert(strs, '\tUsed in:')
        for _, item in pairs(self.usedin) do
            table.insert(strs, '\t\t'..item.name)
        end
    end
    if next(self.recipes) then
        table.insert(strs, '\tRecipes:')
        for _, rcp in ipairs(self.recipes) do
            table.insert(strs, tostring(rcp))
            table.insert(strs, '')
        end
    end
    return table.concat(strs, '\n')
end

-- An ItemSet maps ID:DMGs to Items.
ItemSet = {}
function ItemSet:new()
    local is = {}
    setmetatable(is, self)
    self.__index = self
    return is
end

function ItemSet:fromfile(file)
    is = ItemSet:new()
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
    is = ItemSet:new()
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

function ItemSet:__tostring()
    local strs = {}
    for _, item in pairs(self) do
        table.insert(strs, tostring(item))
    end
    return table.concat(strs, '\n')
end
