local kNone = 'None'

if turtle then
    os.loadAPI('lib/make')
    MakeState = make.MakeState
end

local function printf(fmt, ...)
    print(string.format(fmt, ...))
end

DEBUG = true
local function dprintf(fmt, ...)
    if DEBUG then printf(fmt, ...) end
end

local specialLocs = {
    home = {0, 0}, -- home spot, fuel below.
    out  = {0, 2}, -- output chest to the right of turtle
    temp = {0, 3}, -- intermediate storage
    fin  = {0, 7}, -- chest that feeds items into a furnace
    fout = {0, 6}, -- chest where items fed into the furnace appear
}

-- There are 5 different turtle locations in a ring of barrels:
--        48
--       3  7
--       2  6
--        15
-- loc
--  0: pos = 0: facing forward above ring barrel 1  CW 
--  1: pos = 1,2: facing LEFT  above ring barrel 1   |
--  2: pos = 3,4: facing LEFT  below ring barrel 4  \/ /\
--  4: pos = 7,8: facing RIGHT below ring barrel 8     |
--  3: pos = 5,6: facing RIGHT above ring barrel 5    CCW

-- We can navigate this with 5 clockwise and 5 counter-clockwise movements.
-- Each of these pairs perform opposite actions and return the new location.
local moves = {cw={}, ccw={}}

moves.cw[0] = function ()
    if turtle.turnLeft() then return 1 end
end
moves.ccw[1] = function ()
    if turtle.turnRight() then return 0 end
end

moves.cw[1] = function ()
    if turtle.up() then return 2 end
end
moves.ccw[2] = function ()
    if turtle.down() then return 1 end
end

moves.cw[2] = function ()
    local ok = turtle.turnRight()
    ok = ok and turtle.turnRight()
    ok = ok and turtle.forward()
    if ok then return 4 end
end
moves.ccw[4] = function ()
    local ok = turtle.turnLeft()
    ok = ok and turtle.turnLeft()
    ok = ok and turtle.forward()
    if ok then return 2 end
end

moves.cw[4] = function ()
    if turtle.down() then return 3 end
end
moves.ccw[3] = function ()
    if turtle.up() then return 4 end
end

moves.cw[3] = function ()
    local ok = turtle.back()
    ok = ok and turtle.turnLeft()
    if ok then return 0 end
end
moves.ccw[0] = function ()
    local ok = turtle.turnRight()
    ok = ok and turtle.forward()
    if ok then return 3 end
end

local nav = {
    [0] = {[1]='cw',  [2]='cw',  [4]='ccw', [3]='ccw'},
    [1] = {[0]='ccw', [2]='cw',  [4]='cw',  [3]='ccw'},
    [2] = {[0]='ccw', [1]='ccw', [4]='cw',  [3]='cw' },
    [4] = {[0]='cw',  [1]='ccw', [2]='ccw', [3]='cw' },
    [3] = {[0]='cw',  [1]='cw',  [2]='ccw', [4]='ccw'},
}

-- Turtles will only craft using the upper-left 3x3, ffs.
local slots = {1,2,3,5,6,7,9,10,11}

-- Delia provides apis for navigating ringsets 
Delia = {}
function Delia:new(is, len)
    if not is then return end
    d = {
        _index = 0,   -- how far down the ringset we are
        _pos = 0,     -- what barrel position we are in for the ring
        _loc = 0,     -- what turtle location we are in (see below)
        _len = len,   -- the index of the ring furthest from the turtle
        tools = {},   -- which tools we have in which slots
        slots = {},
        items = is,   -- the itemset representing currently makeable recipes
        names = {},   -- a LUT of item name to items
    }
    setmetatable(d, self)
    self.__index = self
    d:makeLUT()
    return d
end

function Delia:makeLUT()
    for _, item in pairs(self.items) do
        -- names are not unique, and case-sensitivity sucks.
        local name = string.lower(item.name)
        self.names[name] = self.names[name] or {}
        table.insert(self.names[name], item)
    end
end

function Delia:lookup(name)
    local lname = string.lower(name)
    if not self.names[lname] then return end
    if #self.names[lname] == 1 then return self.names[lname][1] end
    printf('Multiple items match %s, please choose:', name)
    for i, item in ipairs(self.names[lname]) do
        printf('%d: %s', i, item.id)
    end
    local i = tonumber(read())
    while not i or not self.names[lname][i] do
        print('Bad index, please try again.')
        i = read()
    end
    return self.names[lname][i]
end

function Delia:reset()
    -- for use in the lua console when shit breaks
    self._index, self._pos, self._loc = 0, 0, 0
end

function Delia:move(index, pos)
    if not pos and specialLocs[index] then
        index, pos = table.unpack(specialLocs[index])
    end
    local ok = self:index(index)
    return ok and self:pos(pos)
end

function Delia:index(index)
    if index > self._len or index < 0 then return false end
    if self._index == index then return true end
    if self._loc ~= 0 then self:loc(0) end

    local count, move, dir = index - self._index, turtle.forward, 1
    if count < 0 then
        count, move, dir = -count, turtle.back, -1
    end
    
    local ok = true
    for i=1,count do
--        dprintf('Moving from index %d -> %d.',
--            self._index, self._index + dir)
        ok = ok and move()
        if not ok then
            printf('Moving from index %d -> %d failed.',
                self._index, self._index + dir)
            self:move('home')
            break
        end
        self._index = self._index + dir
    end
    return ok
end

function Delia:loc(loc)
    if loc > 4 or loc < 0 then return false end
    if self._loc == loc then return true end

    local ok = true
    while self._loc ~= loc do
--        dprintf('Moving from loc %d -> %d.', self._loc, loc)
        -- assert here because we really *ought* to have a direction.
        local dir = assert(nav[self._loc][loc],
            string.format('No nav for loc %d -> %d.', self._loc, loc))
        local new = moves[dir][self._loc]()
        if not new then
            printf('Moving from loc %d -> %d failed.', self._loc, loc)
            self:move('home')
            break
        end
        self._loc = new
    end
    return ok
end

function Delia:pos(pos)
    if pos > 8 or pos < 0 then return false end
    if (pos == 0 and self:loc(0)) or self:loc(math.ceil(pos/2)) then
        self._pos = pos
        return true
    end
    return false
end

function Delia:pick(n)
    if self._pos == 0 then return false end
    local pick = turtle.suck
    if self._pos % 4 == 1 then
        pick = turtle.suckDown
    elseif self._pos % 4 == 0 then
        pick = turtle.suckUp
    end
    if n then
        if not pick(n) then return false end
        local got = turtle.getItemCount()
        if got ~= n then
            printf('Picked %d at (%d, %d), wanted %d.',
                got, self._index, self._pos, n)
            self:put(got)
            return false
        end
        return true
    end
    return pick()
end

function Delia:put(n)
    if self._pos == 0 then return false end
    local put = turtle.drop
    if self._pos % 4 == 1 then
        put = turtle.dropDown
    elseif self._pos % 4 == 0 then
        put = turtle.dropUp
    end
    if n then
        local got = turtle.getItemCount()
        if got ~= n then
            printf('Trying to put %d at (%d, %d), have %d.',
                n, self._index, self._pos, got)
        end
        return put(n)
    end
    return put()
end

function Delia:refuel()
    local ok = self:move('home')
    turtle.select(16)
    ok = ok and turtle.suckDown(8)
    ok = ok and turtle.refuel()
    turtle.select(1)
    printf('Current fuel level: %d', turtle.getFuelLevel())
    return ok
end

function Delia:get(index, pos, n)
    local ok = self:move(index, pos)
    ok = ok and self:pick(n)
    ok = ok and self:move('out')
    ok = ok and self:put()
    ok = ok and self:move('home')
    return ok
end

function Delia:fetch(name, n)
    local item = self:lookup(name)
    if item and item.index and item.pos then
        if not self:get(item.index, item.pos, n) then
            printf('Failed to get %s', item.name)
            self:move('home')
        end
    else
        printf('No barrel for %s', name)
    end
end

function Delia:craft(n, index, pos)
    -- We have to call turtle.craft() in a loop when using harvestcraft
    -- tools, because it will only craft one output at a time :-(
    self:move(index, pos)
    turtle.select(16)
    for i=1,n do
        if not turtle.craft() then
            return false
        end
        self:put()
    end
    turtle.select(1)
    return true
end

function Delia:empty(errstr, ...)
    if errstr then
        printf(errstr, ...)
        print('Please empty chest and reset me :-(')
    end
    self:move('out')
    for i=1,16 do
        if turtle.getItemCount(i) > 0 then
            turtle.select(i)
            self:put()
        end
    end
    turtle.select(1)
    self:move('home')
end

function Delia:make(name, n)
    local item = self:lookup(name)
    n = n or 1
    if not item then
        printf('Unknown or unmakeable item: %s', name)
        return
    elseif #item.pruned == 0 then
        printf('No recipes for %s', name)
        return
    end
    dprintf('Making %d of %s (%s)', n, item.name, item.id)
    local ms = MakeState:new(item, n)
    if not ms:phase1(self) then
        printf('Cannot make %s', item.name)
        self:move('home')
        return
    end
    ms:phase2(self)
    self:move('home')
end

function Delia:makeSimple(items, n, index, pos)
    if not index then index = 'out' end
    -- all of these items are known to be in barrels
    local tools = {}
    local ok = true
    for i, item in pairs(items) do
        slot = slots[i]
        dprintf('Picking %s to slot %d.', item.name, slot)
        turtle.select(slot)
        ok = ok and self:move(item.index, item.pos)
        if item.istool then
            tools[slot] = item
            ok = ok and self:pick()
        else
            ok = ok and self:pick(n)
        end
        if not ok then
            self:empty('Simple make failed at item %s.', item.name)
            return
        end
    end
    if not self:craft(n, index, pos) then
        self:empty('Simple make failed while crafting.')
        return
    end
    for i, item in pairs(tools) do
        dprintf('Returning %s from slot %d.', item.name, i)
        turtle.select(i)
        ok = ok and self:move(item.index, item.pos)
        ok = ok and self:put()
        if not ok then
            self:empty('Simple make failed while returning %s.', item.name)
            return
        end
    end
    self:empty()
end

function Delia:checkInBarrel(item)
    if not (item.index and item.pos) then return end
    if not self:move(item.index, item.pos) then return end
    if self:pick() then
        local num = turtle.getItemCount()
        self:put()
        return num
    end
    return 0
end
