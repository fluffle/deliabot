if turtle then
    os.loadAPI('lib/util')
    kNone = util.kNone
else
    require 'util'
end

local function resolve(id, itemset, oredict)
    if id:sub(1,1) == '@' and oredict:items(id) then
        return oredict:items(id)
    elseif id ~= kNone and itemset:item(id) then
        return {itemset:item(id)}
    elseif id == kNone then
        return kNone
    end
end

Inputs = {}
function Inputs:new(inputs)
    inputs = inputs or {}
    setmetatable(inputs, self)
    self.__index = self
    return inputs
end

function Inputs:items()
    return ipairs(self)
end

function Inputs:serialize(s)
    for _, elem in ipairs(self) do
        if not elem or elem == kNone then
            s:write('%s,', kNone)
        else
            s:write('{')
            for _, item in ipairs(elem) do
                s:write('%q,', item.id)
            end
            if elem.name then
                s:write('name = %q,', elem.name)
            end
            s:write('},')
        end
    end
end

function Inputs:resolve(itemset)
    for _, elem in ipairs(self) do
        for i, id in ipairs(elem) do
            if itemset:item(id) then
                elem[i] = itemset:item(id)
            end
        end
    end
end

Shaped = Inputs:new()

function Shaped:fromline(line, itemset, oredict)
    local inputs = Shaped:new()
    local _, s, w, h = line:find('!%(w=(%d),h=(%d)%)')
    if not s then return end
    inputs.width = tonumber(w)
    inputs.height = tonumber(h)
    for i=1,(inputs.width*inputs.height) do
        local _, e, id = line:find('%(([^%)]+)%)', s)
        if not id then
            print("Shaped recipe does not have enough elements to fulfill width*height")
            print(line)
            return
        end
        if id == kNone then
            inputs[i] = kNone
        else
            _, _, id = id:find('([^,]+),%d+')
            inputs[i] = resolve(id, itemset, oredict)
            if not inputs[i] then return end
        end
        s = e + 1
    end
    return inputs
end

function Shaped:serialize(s)
    s:write('Shaped:new {')
    Inputs.serialize(self, s)
    s:write('width = %d,', self.width)
    s:write('height = %d,', self.height)
    s:partial('}')
end

Shapeless = Inputs:new()

function Shapeless:fromline(line, itemset, oredict)
    local inputs = Shapeless:new()
    local s, _ = line:find('!')
    while true do
        local _, e, id = line:find('%(([^,]+),%d+%)', s)
        id = resolve(id, itemset, oredict)
        if not id then return end
        table.insert(inputs, id)
        if line:sub(e+1, e+2) == '->' then break end
        s = e + 1
    end
    return inputs
end

function Shapeless:serialize(s)
    s:write('Shapeless:new {')
    Inputs.serialize(self, s)
    s:partial('}')
end

-- A Recipe has the following fields:
--   - type (string): "shaped", "shapeless", "shapedore", "shapelessore", "furnace"
--   - inputs (Shaped|Shapeless): Object describing recipe inputs.
--     each array is another array because we do oredict resolution and
--     life is much easier when things are consistent.
--   - output (Item): ID:DMG of the recipe output
--   - outcount (int): number of items recipe produces
--   - _makeable (bool): can this recipe be made (for makeable() caching)
--   - pruned (Shaped|Shapeless): Object describing *makeable* recipe inputs.
Recipe = {}
function Recipe:new(rcp)
    rcp = rcp or {}
    setmetatable(rcp, self)
    self.__index = self
    return rcp
end

function Recipe:fromline(line, itemset, oredict)
    local _, _, typ = line:find('recipedumper:(%w+)!')
    if not typ then return end
    local rcp = Recipe:new{type=typ}
    local _, _, output, outcount = line:find('->%((%d+:%d+),(%d+)%)')
    if not output or not itemset:item(output) then return end
    rcp.output = itemset:item(output)
    rcp.outcount = outcount
    if rcp:shaped() then
        rcp.inputs = Shaped:fromline(line, itemset, oredict)
    else
        rcp.inputs = Shapeless:fromline(line, itemset, oredict)
    end
    if not rcp.inputs then return end
    return rcp
end

function Recipe:shaped()
    return self.type:sub(1,6) == 'shaped'
end

function Recipe:furnace()
    return self.type == 'furnace'
end

function Recipe:makeable()
    if self._makeable ~= nil then
        -- We've done this lookup already. Yay caching.
        return self._makeable
    end
    local pruned = Shapeless:new()
    if self:shaped() then
        pruned = Shaped:new()
        pruned.width = self.inputs.width
        pruned.height = self.inputs.height
    end
    self._makeable = true
    for i, elem in self.inputs:items() do
        -- We need one of the items in each elem to be either makeable
        -- or in a barrel somewhere.
        if elem and elem ~= kNone then
            local makeable = {}
            for _, item in ipairs(elem) do
                if item:makeable() or (item.index and item.pos) then
--[[
                    if item:makeable() then
                        print(string.format('Item %s is makeable for %s.',
                            item.name, self.output.name))
                    end
                    if item.index and item.pos then
                        print(string.format('Item %s is in barrel (%d,%d).',
                            item.name, item.index, item.pos))
                    end
--]]
                    table.insert(makeable, item)
                end
            end
            if #makeable == 0 then
                self._makeable = false
--[[
                if elem.name then
                    print('No items makeable in ' .. elem.name)
                else
                    print('Item ' .. elem[1].name .. ' not makeable.')
                end
--]]
                break
            end
            pruned[i] = makeable
        end
    end
    if self._makeable then
        self.pruned = pruned
    end
    return self._makeable
end

function Recipe:serialize(s)
    -- We flatten the graph for serialization here by writing item IDs
    -- instead of serialized items for recipe inputs and outputs.
    s:write('Recipe:new {')
    s:write('type = %q,', self.type)
    s:write('output = %q,', self.output.id)
    s:write('outcount = %d,', self.outcount)
    if self.inputs then
        s:partial('inputs = ')
        self.inputs:serialize(s)
        s:write(',')
    end
    if self.pruned then
        s:partial('pruned = ')
        self.pruned:serialize(s)
        s:write(',')
    end
    s:partial('}')
end

function Recipe:resolve(itemset)
    -- This function does most of the work of unflattening the recipe graph
    if type(self.output) ~= 'string' then return end
    if not self.output or not itemset:item(self.output) then return end
    self.output = itemset:item(self.output)
    self.inputs:resolve(itemset)
    if self.pruned then self.pruned:resolve(itemset) end
end
