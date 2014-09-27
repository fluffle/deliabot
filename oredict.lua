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
    local dict = {}
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
            dict[name] = resolve(ids, itemset)
            -- this conveniently doesn't mess with ipairs()
            dict[name].name = name
        end
    end
    fh.close()
    return dict
end

function OreDict:lookup(name)
    return self[name]
end

