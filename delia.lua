local specialLocs = {
    home = {0, 0}, -- home spot, fuel below.
    out  = {0, 2}, -- output chest to the right of turtle
    temp = {0, 3}, -- intermediate storage
    fin  = {0, 4}, -- chest that feeds items into a furnace
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
    ok = turtle.turnRight()
    ok = ok and turtle.turnRight()
    ok = ok and turtle.forward()
    if ok then return 4 end
end
moves.ccw[4] = function ()
    ok = turtle.turnLeft()
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
    ok = turtle.back()
    ok = ok and turtle.turnLeft()
    if ok then return 0 end
end
moves.ccw[0] = function ()
    ok = turtle.turnRight()
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
    }
    setmetatable(d, self)
    self.__index = self
    return d
end

function Delia:reset()
    -- for use when shit breaks
    self._index, self._pos, self._loc = 0, 0, 0
end

function Delia:move(index, pos)
    if not pos and specialLocs[index] then
        index, pos = table.unpack(specialLocs[index])
    end
    ok = self:index(index)
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
    
    ok = true
    for i=1,count do
        print(string.format('Moving from index %d -> %d.',
            self._index, self._index + dir))
        ok = ok and move()
        if not ok then
            print(string.format('Moving from index %d -> %d failed.',
                self._index, self._index + dir))
            break
        end
        self._index = self._index + dir
    end
    return ok
end

function Delia:loc(loc)
    if loc > 4 or loc < 0 then return false end
    if self._loc == loc then return true end

    ok = true
    while self._loc ~= loc do
        print(string.format('Moving from loc %d -> %d.',
            self._loc, loc))
        -- assert here because we really *ought* to have a direction.
        dir = assert(nav[self._loc][loc],
            string.format('No nav for loc %d -> %d.', self._loc, loc))
        new = moves[dir][self._loc]()
        if not new then
            print(string.format('Moving from loc %d -> %d failed.', self._loc, loc))
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
        return pick(n)
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
        return put(n)
    end
    return put()
end

function Delia:refuel()
    ok = self:move('home')
    ok = ok and turtle.select(16)
    ok = ok and turtle.suckDown(8)
    ok = ok and turtle.refuel()
    ok = ok and turtle.select(1)
    print('Current fuel level: ' .. turtle.getFuelLevel())
    return ok
end

function Delia:fetch(index, pos)
    ok = self:move(index, pos)
    ok = ok and self:pick()
    ok = ok and self:move('out')
    ok = ok and self:put()
    ok = ok and self:move('home')
    return ok
end
