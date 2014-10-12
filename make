if unpack and not table.unpack then
    table.unpack = unpack
end

os.loadAPI('lib/recipebook')
os.loadAPI('lib/delia')

local args = {...}
if #args < 1 then
    print('Usage: make [num] Food Stuff')
    return
end

local count = 1
if tonumber(args[1]) then
    count = tonumber(args[1])
    table.remove(args, 1)
end
local name = table.concat(args, ' ')
if name:lower() == 'me a sandwich' then
    print('What? Make it yourself!')
    return
end

local d = delia.Delia:new(recipebook.recipes, recipebook.len)
if turtle.getFuelLevel() < 1000 and not d:refuel() then
    print('Couldn\'t get enough fuel from barrel {0,1}.')
    return
end

d:make(name, count)
    

