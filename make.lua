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
        local tocheck = {}
        table.sort(itemlist, byPosition)

        for _, item in ipairs(itemlist) do
            if self.items[item] then
                -- Reset multipliers on items we have seen.
                self.items[item].mul = 0
                -- If we replaced an item but it's still in itemlist
                -- another recipe is trying to use it (probably from
                -- a *different* replacement) and we need to fix that
                -- with another findNext(). TL;DR: this is probably Salt. 
                self.items[item].replaced = false
            else
                -- Only check items not previously checked.
                self.items[item] = { mul = 0 }
                tocheck[item] = true
            end
        end
        
        for i=#itemlist,1,-1 do
            -- Add up multipliers for items by counting dupes,
            -- then dedupe and skip items already looked for.
            local item = itemlist[i]
            self.items[item].mul = self.items[item].mul + 1
            if tocheck[item] then
                if i ~= #itemlist and itemlist[i] == itemlist[i+1] then
                    table.remove(itemlist, i+1)
                end
            else 
                table.remove(itemlist, i)
            end
        end

        recalculate = false
        if #itemlist > 0 then
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
                -- Check barrels
                self.items[item].count = delia:checkInBarrel(item)
            end
        end
        for item, data in pairs(self.items) do
            if not data.replaced and data.count < self.count * data.mul then
                dprintf('Need %d %s in (%d, %d), have %d.', self.count * data.mul,
                    item.name, item.index, item.pos, data.count)
                if not root:findNext(item) then
                    printf('Missing %d %s for recipe.',
                        self.count * data.mul - data.count, item.name)
                    failed = true
                end
                recalculate = true
                -- this item has been replaced with another (or a recipe)
                data.replaced = true
            end
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
        temp={},      -- deps of this recipe in temp chests, map elem -> Item
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

function MakeNode:depth()
    if not next(self.deps) then return 0 end
    local depth = 0
    for _, nlist in pairs(self.deps) do
        depth = math.max(depth, nlist[1]:depth() + 1)
    end
    return depth
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

function MakeNode:make(delia, n, intermediate)
    local item = self.rcp.output
    if self.rcp:shaped() then
        printf('Shaped recipe for %s, failing.', item.name)
        return false
    end
    if next(self.deps) then
        local tomake = {}
        for elem, _ in pairs(self.deps) do
            table.insert(tomake, elem)
        end
        table.sort(tomake, function (a,b)
            -- We need to make our dependencies deepest-first to
            -- avoid (some) of the problems with using a temp chest.
            -- Having a stable sort order is nice, sort by name too.
            na = self.deps[a][1]
            nb = self.deps[b][1]
            return (na:depth() > nb:depth()
                or na:depth() == nb:depth()
                and na.rcp.output.name < nb.rcp.output.name)
        end)
        for _, elem in pairs(tomake) do
            local node = self.deps[elem][1]
            local dep = node.rcp.output
            printf('%s depth %d', dep.name, node:depth())
            if not node:make(delia, n, true) then return false end
            self.deps[elem] = nil
            if dep.index and dep.pos then
                -- successfully crafted dep into barrel.
                self.barrels[elem] = {dep}
            elseif node.rcp:furnace() then
                -- successfully crafted dep into furnace output chest.
                -- NASTY HACK: temporarily set index for crafting.
                dep.index = 'fout'
                self.temp[elem] = dep
            else
                -- successfully crafted dep into temp chest.
                -- NASTY HACK: temporarily set index for crafting.
                dep.index = 'temp'
                self.temp[elem] = dep
            end
        end
    end
    local ok = true
    if next(self.deps) then
        printf('Failed to clear deps while making %s.', item.name)
        ok = false
    elseif self.rcp:furnace() then
        local items = {}
        for _, elem in self.rcp.pruned:items() do
            if self.barrels[elem] then
                table.insert(items, self.barrels[elem][1])
            elseif self.temp[elem] then
                table.insert(items, self.temp[elem])
            end
        end
        if #items ~= 1 then
            printf('Very confused trying to furnace %d items.', #items)
            return false
        end
        if item.index and item.pos then
            -- Move cooked item to barrel after if it exists.
            ok = delia:furnace(items[1], n, item.index, item.pos)
        elseif not intermediate then
            -- Making a final item, so move to output chest.
            ok = delia:furnace(items[1], n, 'out')
        else
            -- Leave it in furnace output chest.
            ok = delia:furnace(items[1], n)
        end
    else
        -- Shapeless craft. Make ingredient list and go.
        local items = {}
        for _, blist in pairs(self.barrels) do
            table.insert(items, blist[1])
        end
        table.sort(items, byPosition)
        for _, dep in pairs(self.temp) do
            table.insert(items, dep)
        end
        if item.index and item.pos then
            -- Craft into item barrel if it exists.
            ok = delia:shapeless(items, n, item.index, item.pos)
        elseif intermediate then
            -- If this is an intermediate dep then craft into temp chest.
            ok = delia:shapeless(items, n, 'temp')
        else
            -- Otherwise craft into output chest.
            ok =  delia:shapeless(items, n, 'out')
        end
    end
    for _, dep in pairs(self.temp) do
        dep.index = nil
    end
    return ok
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

