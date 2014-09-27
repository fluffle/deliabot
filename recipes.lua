local kNone = 'None'
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
    if id:sub(1,1) == '@' and oredict:lookup(id) then
        return oredict:lookup(id)
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

function Recipe:__tostring()
    return tostring(self.inputs)
end        

local function ignore(rcp)
    -- special case: most Pam's vegetables have a recipe that looks like
    -- (item) + (item) -> 2(item). Skip these because they are pointless.
    if not rcp:shaped() and #rcp.inputs == 2
        and rcp.inputs[1][1] == rcp.output
        and rcp.inputs[2][1] == rcp.output
    then
        return true
    end
end

-- The recipe loader handles loading recipes from a file and turning the
-- itemset into a graph of recipe dependencies.
function LoadRecipes(file, itemset, oredict)
    local fh = io.open(file, 'r')
    for line in fh:lines() do
        local rcp = Recipe:fromline(line, itemset, oredict)
        if rcp and not ignore(rcp) then
            rcp.output:addrecipe(rcp)
            for _, elem in rcp.inputs:items() do
                if elem ~= kNone then
                    for _, item in ipairs(elem) do
                        item:setusedin(rcp.output)
                    end
                end
            end 
        end
    end
    fh.close()
end
