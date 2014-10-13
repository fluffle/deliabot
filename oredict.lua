-- Many if not all HarvestCraft recipes are defined in terms of one-item
-- oreDict entries. I suspect this is to make Pam's life easier when writing
-- new recipes. Encapsulating it in a simple class makes life easier for me :-)

local function parse(line)
    local _, e, name = line:find('(@[^-]+)->')
    if e ~= nil and line:len() > e then
        -- This name has IDs associated.
        local s = e + 1
        local ids = {}
        while true do
            -- yay more crackpot parsing
            _, e, id = line:find('%((%d+:%d+),%d+%)', s)
            if id == nil then break end
            table.insert(ids, id)
            s = e + 1
        end
        if #ids > 0 then
            return name, ids
        end
    end
end

local function resolve(ids, itemset)
    local items = {}
    for _, id in ipairs(ids) do
        if itemset:item(id) then
            table.insert(items, itemset:item(id))
        end
    end
    return items
end

OreDict = {}
function OreDict:new()
    -- we have a many:many mapping between names and Items
    local dict = {name2items={}, item2names={}}
    setmetatable(dict, self)
    self.__index = self
    return dict
end

function OreDict:fromfile(file, itemset)
    local dict = OreDict:new()
    local fh = assert(io.open(file, 'r'))
    for line in fh:lines() do
        name, ids = parse(line)
        if name and ids then
            dict:insert(name, resolve(ids, itemset))
        end
    end
    fh:close()
    return dict
end

function OreDict:items(name)
    return self.name2items[name]
end

function OreDict:names(item)
    return self.item2names[item]
end

function OreDict:replace(name, ...)
    assert(self.name2items[name], 'Trying to replace nonexistent oredict entry')
    self:remove(name)
    self:insert(name, {...})
end

function OreDict:insert(name, items)
    -- this conveniently doesn't mess with ipairs() and is used as
    -- a marker to distinguish an oredict list from a single item.
    items.name = name
    self.name2items[name] = items
    for _, item in ipairs(items) do
        self.item2names[item] = self.item2names[item] or {}
        table.insert(self.item2names[item], name)
    end
end

function OreDict:remove(name)
    assert(self.name2items[name], 'Trying to remove nonexistent oredict entry')
    local old = self.name2items[name]
    self.name2items[name] = nil
    for _, item in ipairs(old) do
        for i, n in ipairs(self.item2names[item]) do
            if n == name then
                table.remove(self.item2names[item], i)
            end
        end
    end
    return old
end
