local kNone = 'None'

function printf(fmt, ...)
    print(string.format(fmt, ...))
end

DEBUG = true
function dprintf(fmt, ...)
    if DEBUG then printf(fmt, ...) end
end

local function elemstr(elem)
    local names = {}
    for _, i in ipairs(elem) do table.insert(names, i.name) end
    return table.concat(names, ', ')
end

-- MakeState tracks the making of an item and its dependencies.
MakeState = {}
function MakeState:new(delia, item)
    ms = {
        delia=delia,
        output=item,
        pipe={},      -- keep track of items in temp chest (FIFO, meh)
        barrels={},   -- 
        queue={},     -- make queue, created bf from dep tree
    }
    setmetatable(ms, self)
    self.__index = self
    return ms
end

function MakeState:printqueue()
    for i, elem in ipairs(self.queue) do
        if #elem == 1 then
            printf('%d: %s', i, elem[1].name)
        else
            printf('%d: [%s]', i, elemstr(elem))
        end
    end
end

local function walkitems(rcp, env)
    for _, elem in ipairs(rcp.pruned) do
        if env.__efunc and env.__efunc(elem, env) then goto nextelem end
        if elem and elem ~= kNone then
            for _, item in ipairs(elem) do
                if not env.__ifunc or not env.__ifunc(item, env) then
                    env.__walk(item, env)
                end
            end
        end
        ::nextelem::
    end
end

local function walkrecipes(item, env)
    if not item.pruned then return end
    for _, rcp in ipairs(item.pruned) do
        if not env.__rfunc or not env.__rfunc(rcp, env) then
            walkitems(rcp, env)
        end
    end
end

function MakeState:bfwalk(root, env)
    -- technically only bf for items, will still do recipes df
    env.__queue = {root}
    env.__walk = function(i, e) 
        table.insert(e.__queue, i)
    end
    while #env.__queue > 0 do
        local item = table.remove(env.__queue, 1)
        walkrecipes(item, env)
    end
end

function MakeState:dfwalk(root, env)
    env.__walk = function(i, e)
        walkrecipes(i, e)
    end
    walkrecipes(root, env)
end

function MakeState:phase1()
    -- phase 1 of make. Do a breadth-first scan of dep tree stopping at
    -- elements where all deps are in barrels. While walking:
    --   - fill in self.barrels index, pos
    --   - add elems that are entirely not in barrels to self.queue
    
    -- We do this at the element level because the list of items in 
    -- elem are a logical OR for the recipe, we only need to make one.
    local efunc = function(elem, env)
        local found = 0
        for _, item in ipairs(elem) do
            if env.seen[item] then
                found = found + 1
            elseif item.index and item.pos then
                found = found + 1
                table.insert(env.barrels, item)
                dprintf('Barrel found for %s at (%d, %d).',
                    item.name, item.index, item.pos)
            end
            env.seen[item] = true
        end
        if found < #elem then
            table.insert(env.queue, 1, elem)
            dprintf('Queue insert: [%s]', elemstr(elem))
        end
        return found > 0
    end
    table.insert(self.queue, {self.output})
    local env = {
        __efunc = efunc,
        barrels = self.barrels,
        queue   = self.queue,
        seen    = {},
    }
    self:bfwalk(self.output, env)
    table.sort(self.barrels, function (a,b)
        return a.index < b.index or a.index == b.index and a.pos < b.pos
    end)
end

---[[
require 'items'
require 'recipes'
require 'recipebook'
items:resolve()

for _, item in pairs(items) do
    local ms = MakeState:new(nil, item)
    ms:phase1()
    printf('Queue for %s:', item.name)
    ms:printqueue()
end
--]]

