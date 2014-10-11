local kNone = 'None'

local function printf(fmt, ...)
    print(string.format(fmt, ...))
end

DEBUG = true
local function dprintf(fmt, ...)
    if DEBUG then printf(fmt, ...) end
end

local function elemstr(elem)
    local names = {}
    for _, i in ipairs(elem) do table.insert(names, i.name) end
    return table.concat(names, ', ')
end

local function byPosition(a, b)
    return a.index < b.index or a.index == b.index and a.pos < b.pos
end

local function byCost(a,b) return a:cost() < b:cost() end

-- MakeState tracks the making of an item and its dependencies.
MakeState = {}
function MakeState:new(item, count)
    ms = {
        output=item,  -- what to make
        count=count,  -- how many to make
        pipe={},      -- keep track of items in temp chest (FIFO, meh)
        roots={},     -- MakeNodes for each recipe of output + dep tree
        items={},     -- Map of Item -> { mul, count } for items in barrels.
        p1done=false, -- Have we successfully completed phase1?
    }
    setmetatable(ms, self)
    self.__index = self
    return ms
end

function MakeState:serialize(s)
    if not self.roots or #self.roots == 0 then
        s:write('%s has no recipes.', self.output.name)
        return
    end
    for i, n in ipairs(self.roots) do
        s:partial('%d: ', i)
        n:serialize(s)
        s:write(',')
    end
end

function MakeState:phase1(delia)
    -- TODO: this is a bit of a mess.
    -- This:
    --   1. Figures out the barrels and deps for the desired output.
    --   2. Scores all the alternatives based on turtle movement.
    --   3. Checks the set of barrels to ensure enough items exist.
    --   4. Iterates through oredict or recipes when they don't.
    --   5. Returns true if recipe can be made, false otherwise.
    if not self.output.pruned then return end
    for i, rcp in ipairs(self.output.pruned) do
        self.roots[i] = MakeNode:new(rcp)
        self.roots[i]:buildTree()
    end

    local recalculate, failed, reverse = true, false, false
    while recalculate and not failed do
        -- This loop does some hoop jumping to avoid re-doing work.
        -- If a second iteration occurs, itemlist will contain
        -- a large number of barrels that have already been checked.
        table.sort(self.roots, byCost)
        local root = self.roots[1]
        local itemlist = root:items() 
        local itemdata = {}
        table.sort(itemlist, byPosition)

        for _, item in ipairs(itemlist) do
            if not self.items[item] then
                -- Only check items not previously checked.
                itemdata[item] = { mul = 0 }
            end
        end
        
        for i=#itemlist,1,-1 do
            -- Add up multipliers for items by counting dupes,
            -- then dedupe and skip items already looked for.
            if itemdata[itemlist[i]] then
                itemdata[itemlist[i]].mul = itemdata[itemlist[i]].mul + 1
                if i ~= #itemlist and itemlist[i] == itemlist[i+1] then
                    table.remove(itemlist, i+1)
                end
            else
                table.remove(itemlist, i)
            end
        end
        if #itemlist == 0 then
            printf('Post-filter itemlist is empty, bailing out.')
            failed = true
            break
        end

        recalculate = false
        local s, e, step = 1, #itemlist, 1
        if reverse then
            -- reverse flip-flops between true and false on each loop iteration
            -- If true, we start from the end of itemlist and work backwards.
            -- Itemlist is sorted by barrel position, so when reverse is false
            -- the turtle works from low to high index, and when it is true
            -- the turtle works from high to low. Switching between the two
            -- should result in fewer moves and faster barrel checking.
            s, e, step = #itemlist, 1, -1
        end
        for i=s,e,step do
            local item = itemlist[i]
            -- Check barrels (
            local data = itemdata[item]
            data.count = delia:checkInBarrel(item)
            if data.count < self.count * data.mul then
--                printf('Need %d %s in (%d, %d), have %d.', self.count * data.mul,
--                    item.name, item.index, item.pos, data.count)
                recalculate = true
                if not root:findNext(item) then
                    printf('Missing items for recipe: %s (%d, %d)',
                        item.name, item.index, item.pos)
                    failed = true
                end
            end
        end
        for item, data in pairs(itemdata) do
            self.items[item] = data
        end
        reverse = not reverse
    end
    self.p1done = not failed
    return self.p1done
end

function MakeState:phase2(delia)
    if not self.p1done or not self.roots or #self.roots == 0 then return end
    local root = self.roots[1]
    root:make(delia, self.count)
end

-- MakeNode tracks the making of one recipe of an item
MakeNode = {}
function MakeNode:new(rcp)
    ms = {
        rcp=rcp,      -- what to make
        barrels={},   -- elems in barrels, map of elem -> sorted {Item}
        deps={},      -- deps of this recipe, map of elem -> {MakeNode}
    }
    setmetatable(ms, self)
    self.__index = self
    return ms
end

function MakeNode:serialize(s)
    s:write('%s (cost: %d) {', self.rcp.output.name, self:cost())
    for i, elem in self.rcp.pruned:items() do
        if self.barrels[elem] then
            s:write('Elem %d in barrels: [%s],', i, elemstr(self.barrels[elem]))
        elseif self.deps[elem] then
            s:write('Elem %d has recipes: {', i)
            for j, n in ipairs(self.deps[elem]) do
                s:partial('%d: ', j)
                n:serialize(s)
                s:write(',')
            end
            s:write('},')
        else
            s:write('Elem %d is in no barrels and has no recipes!', i)
        end
    end
    s:partial('}')
end

function MakeNode:buildTree()
    -- For this recipe, figure out whether at least one input item for each
    -- recipe element is in a barrel. Where none are, create a set of new
    -- MakeNodes for each recipe of each item that can be used for that
    -- recipe element. Where barrels exist, create an ordered list per elem.
    for _, elem in self.rcp.pruned:items() do
        local barrels = {}
        for _, item in ipairs(elem) do
            if item.index and item.pos then
                table.insert(barrels, item)
--                dprintf('Barrel found for %s at (%d, %d).',
--                    item.name, item.index, item.pos)
            end
        end
        if #barrels > 0 then
            table.sort(barrels, byPosition)
            self.barrels[elem] = barrels
        else
            -- We do this at the element level because the list of items in 
            -- elem are a logical OR for the recipe, we only need to make one
            -- of them, and we only need to make one of the recipes.
            dprintf('Queue insert: [%s]', elemstr(elem))
            local deps = {}
            for _, item in ipairs(elem) do
                for _, rcp in ipairs(item.pruned) do
                    local node = MakeNode:new(rcp)
                    node:buildTree()
                    table.insert(deps, node)
                end
            end
            if #deps > 0 then
                table.sort(deps, byCost)
                self.deps[elem] = deps
            else
                dprintf('No recipes found for any item in %s.', elemstr(elem))
            end
        end
    end
end

function MakeNode:cost()
    local cost = 0
    for _, elem in self.rcp.pruned:items() do
        if self.barrels[elem] then
            cost = cost + self.barrels[elem][1]:cost()
        elseif self.deps[elem] then
            cost = cost + self.deps[elem][1]:cost()
        end
    end
    if self.rcp.type == 'furnace' then
        cost = cost + 10
    end
    return cost
end

function MakeNode:items()
    local items = {}
    for _, blist in pairs(self.barrels) do
        if not blist[1].istool then
            -- assume no need to check tools.
            table.insert(items, blist[1])
        end
    end
    for _, nlist in pairs(self.deps) do
        for _, b in ipairs(nlist[1]:items()) do
            table.insert(items, b)
        end
    end
    return items
end

function MakeNode:findNext(item)
    -- Make phase 1 has determined that there are not enough
    -- of item in its barrel to successfully make the recipe.
    -- Walk the tree and figure out what's next.
    local new = nil
    local empty = {}
    for elem, blist in pairs(self.barrels) do
        if blist[1] == item then
            table.remove(blist, 1)
            if #blist > 0 then
                if not new then
                    new = blist[1]
                    dprintf('Replacing %s with %s.', item.name, new.name)
                elseif new ~= blist[1] then
                    dprintf('Wat, expected all nexts to be the same.')
                    dprintf('%s != %s for %s', new, blist[1], self.rcp.output.name) 
                end
            else
                table.insert(empty, elem)
            end
        end
    end
    if new then return true end
    if #empty == 0 then
        -- Not in barrels of current node, so try all children
        for _, nlist in pairs(self.deps) do
            if nlist[1]:findNext(item) then return true end
        end
        return false
    end
    for _, elem in ipairs(empty) do
        self.barrels[elem] = nil
        local deps = {}
        for _, it in ipairs(elem) do
            if it.pruned then
                for _, rcp in ipairs(it.pruned) do
                    local node = MakeNode:new(rcp)
                    node:buildTree()
                    table.insert(deps, node)
                end
            end
        end
        if #deps > 0 then
            table.sort(deps, byCost)
            self.deps[elem] = deps
            dprintf('No more barrels for %s, substituting recipes.', elemstr(elem))
        else
            dprintf('No recipes for %s.', elemstr(elem))
            return false
        end
    end
    return true
end

function MakeNode:make(delia, n)
    if not next(self.deps) then
        -- Simple case!
        local items = {}
        for _, blist in pairs(self.barrels) do
            table.insert(items, blist[1])
        end
        table.sort(items, byPosition)
        delia:makeSimple(items, n)
        return
    end
    print('Still not implemented.')
end
            

--[[
require 'items'
require 'recipes'
require 'recipebook'
require 'serializer'
items:resolve()

for _, item in pairs(items) do
    local ms = MakeState:new(nil, item)
    ms:phase1()
    local s = Serializer:new()
    ms:serialize(s)
    print(s)
end
--]]

