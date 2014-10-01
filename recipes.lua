local function getName(input)
    if not input or input == kNone then
        return kNone
    elseif input.name then
        return input.name
    else
        return input[1].name
    end
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
function Inputs:new()
    local inputs = {}
    setmetatable(inputs, self)
    self.__index = self
    return inputs
end

function Inputs:items()
    return ipairs(self)
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

function Shaped:__tostring()
    local strs = {}
    for h=1,self.height do
        local line = {}
        for w=1,self.width do
            table.insert(line, getName(self[w+(3*(h-1))]))
        end
        table.insert(strs, '\t\t(' .. table.concat(line, ')\t\t(') .. ')')
    end
    return table.concat(strs, '\n')
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

function Shapeless:__tostring()
    local strs = {}
    if #self > 6 then
        -- fill vertically to match NEI
        for h=1,3 do
            local line = {}
            for w=1,3 do
                table.insert(line, getName(self[h+(3*(w-1))]))
            end
            table.insert(strs, '\t\t(' .. table.concat(line, ')\t\t(') .. ')')
        end
    else
        for h=1,3 do
            local line = {}
            for w=1,2 do
                table.insert(line, getName(self[w+(2*(h-1))]))
            end
            table.insert(line, kNone)
            table.insert(strs, '\t\t(' .. table.concat(line, ')\t\t(') .. ')')
        end
    end
    return table.concat(strs, '\n')
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

function Recipe:new(typ)
    local rcp = {type=typ, inputs={}}
    setmetatable(rcp, self)
    self.__index = self
    return rcp
end

function Recipe:fromline(line, itemset, oredict)
    local _, _, typ = line:find('recipedumper:(%w+)!')
    if not typ then return end
    local rcp = Recipe:new(typ)
    local _, _, output, outcount = line:find('->%((%d+:%d+),(%d+)%)')
    if not output or not itemset[output] then return end
    rcp.output = itemset[output]
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
                if item:makeable() or item.barrel then
--[[
                    if item:makeable() then
                        print(string.format('Item %s is makeable for %s.',
                            item.name, self.output.name))
                    end
                    if item.barrel then
                        print(string.format('Item %s is in barrel (%d,%d).',
                            item.name, item.barrel[1], item.barrel[2]))
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
                    

function Recipe:__tostring()
    return tostring(self.inputs)
end

