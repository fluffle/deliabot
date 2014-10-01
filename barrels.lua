RingSet = {}
function RingSet:new()
    local rs = {rings={}, items={}}
    setmetatable(rs, self)
    self.__index = self
    return rs
end

function RingSet:fromfile(file, itemset)
    rs = RingSet:new()
    local fh = assert(io.open(file, 'r'))
    local _, _, x, y, z, axis, orient, len =
        fh:read():find('Turtle ([%d-]+) ([%d-]+) ([%d-]+) ([xz])([+-])(%d+)')
    if not x then return end
    index = 0
    for line in fh:lines() do
        index = index + 1
        local ring = {}
        pos = 0
        for item in line:gmatch('%S+') do
            pos = pos + 1
            if item == kNone then
                table.insert(ring, kNone)
            elseif itemset:item(item) then
                table.insert(ring, itemset:item(item))
                rs.items[itemset:item(item)] = {index, pos}
            else
                table.insert(ring, kNone)
                print('Unknown item ' .. item .. ' in ringset.')
            end
        end
        assert(#ring == 8, 'Not 8 items in ring line:\n\t' .. line)
        table.insert(rs.rings, ring)
    end
    fh.close()
    assert(#rs.rings == tonumber(len), 'Not '..len..' rings in file.')
    rs.x, rs.y, rs.z = tonumber(x), tonumber(y), tonumber(z)
    rs.len = #rs.rings
    
    return rs
end

function RingSet:__tostring()
    strs = {}
    for index, r in ipairs(self.rings) do
        for pos, b in ipairs(r) do
            if b == kNone then
                table.insert(strs, string.format('(%d,%d) None', index, pos))
            else
                table.insert(strs, string.format('(%d,%d) %s', index, pos, b.name))
            end
        end
    end
    return table.concat(strs, '\n')
end
