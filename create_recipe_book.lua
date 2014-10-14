#! /usr/bin/lua

-- Check commandline arg.

if #arg ~= 1 then
    print('Usage: lua create_recipe_book.lua /path/to/save/folder')
    os.exit(1)
end

fh = assert(io.open(arg[1] .. '/level.dat'))
fh:close()

-- We have input files in recipe dump format, but this is not amazingly
-- helpful, especially when shapeless recipe handling is broken:
-- https://github.com/vitzli/recipedumper/issues/1

-- None is used in many places.
require 'util'

-- Load in the dumped list of items from a file.
require 'items'
allitems = ItemSet:fromfile('data/itemids')

-- Load in the ore dictionary, resolving IDs to Items.
require 'oredict'
oredict = OreDict:fromfile('data/oredict', allitems)

-- Prune some of the oredict entries, since we'll only ever use
-- Harvestcraft water/milk when crafting.
oredict:replace('@listAllwater', allitems:item('15508:0'))
oredict:replace('@listAllmilk',
    allitems:item('15507:0'), -- Fresh Milk
    allitems:item('15759:0')) -- Soy Milk

local function oredictName(match)
    return function (item)
        if not oredict:names(item) then return false end
        for _, name in ipairs(oredict:names(item)) do
            if name:match(match) then
                return true
            end
        end
    end
end
toolitems = allitems:filter(oredictName('^@tool'))
for _, item in pairs(toolitems) do
    item.istool = true
end

-- Load in all the recipes. First from the heap-derived data, then falling back
-- to the dumped data for all non-shapelessore recipes. Note: shapedore recipes
-- may be broken in the same way to shapeless ones.
require 'recipes'

local function ignore(line)
    -- Most Pam's vegetables have a recipe that looks like
    -- (item) + (item) -> 2(item). Skip these because they are pointless.
    if line:match('!%((@crop%w+,1)%)%(%1%)%->') then
        return true
    end
    -- The "replacement" stock recipes don't appear to have overwritten
    -- the old ones that don't require water completely, so skip them.
    if line:match('->%(15777:0,3%)$') then
        return true
    end
    -- We are not going to use the Mutandis recipes to create meats from other
    -- meats, especially because they introduce graph cycles.
    badinputs = {
        '10886:14', -- Mutandis
        '10886:15', -- Mutandis extremis
    }
    for _, id in ipairs(badinputs) do
        if line:match('![^-]*%('..id..',1%)[^-]*->') then
            return true
        end
    end
    -- Bags introduce nasty graph cycles, as does the sugar cube and MFR meat
    badoutputs = {
        '12667:0', -- wheat seed bag
        '12670:0', -- carrot bag
        '12669:0', -- potato bag
        '12675:0', -- bonemeal bag
        '12671:0', -- nether wart bag
        '4049:1',  -- sugar cube
        '3133:12', -- raw meat block
        '3133:13', -- cooked meat block
        '12283:0', -- raw meat nugget
        '12284:0', -- cooked meat nugget
    }
    for _, id in ipairs(badoutputs) do
        if line:match('![^-]+->%('..id..',%d%)') then
            return true
        end
    end
end

-- The recipe loader handles loading recipes from a file and turning the
-- itemset into a graph of recipe dependencies.
function LoadRecipes(file, itemset, oredict)
    local fh = io.open(file, 'r')
    for line in fh:lines() do
        if not ignore(line) then
            local rcp = Recipe:fromline(line, itemset, oredict)
            if rcp then
                rcp.output:addrecipe(rcp)
            end
        end
    end
    fh:close()
end
LoadRecipes('data/shapeless_ore_recipes', allitems, oredict)
LoadRecipes('data/not_shapeless_ore_recipes', allitems, oredict)

-- Load in the set of items we have available in our barrels.
function LoadBarrels(file, itemset)
    local turtle = {}
    local fh = assert(io.open(file, 'r'))
    local _, _, id, x, y, z, len =
        fh:read():find('Turtle id=(%d+) x=([%d-]+) y=([%d-]+) z=([%d-]+) len=(%d+)')
    assert(id, 'Could not load turtle/barrel data.')
    index = 0
    for line in fh:lines() do
        index, pos = index + 1, 0
        for id in line:gmatch('%S+') do
            pos = pos + 1
            if itemset:item(id) then
                item = itemset:item(id)
                item.index = index
                item.pos = pos
            end
        end
        assert(pos == 8, 'Not 8 items in ring line:\n\t' .. line)
    end
    fh:close()
    assert(index == tonumber(len), 'Not '..len..' rings in file.')
    turtle.x, turtle.y, turtle.z = tonumber(x), tonumber(y), tonumber(z)
    turtle.len = tonumber(len)
    turtle.id = id
    return turtle
end
tmpname = os.tmpname()
ok, out, exit = os.execute('python barrels.py "'..arg[1]..'" "'..tmpname..'"')
if not ok then
    print('Failed to execute barrels.py.')
    print(out)
    os.exit(1)
end
turtle = LoadBarrels(tmpname, allitems)
os.remove(tmpname)

stopitems = ItemSet:new():mergefrom(toolitems)
stopitems:insert(allitems:item('15508:0')) -- Fresh Water
stopitems:insert(allitems:item('15507:0')) -- Fresh Milk
stopitems:insert(allitems:item('334:0'))   -- Leather (Yoghurt->)
stopitems:insert(allitems:item('280:0'))   -- Stick (Caramel Apple->)
stopitems:insert(allitems:item('367:0'))   -- Rotten Flesh (Zombie Jerky->)
stopitems:insert(allitems:item('296:0'))   -- Wheat (->Hay Bale)
stopitems:insert(allitems:item('363:0'))   -- Raw Beef (->Cow Essence)
stopitems:insert(allitems:item('352:0'))   -- Bone (->Skeleton Essence)
stopitems:insert(allitems:item('375:0'))   -- Spider Eye (->Spider Essence)
stopitems:insert(allitems:item('332:0'))   -- Snowball (->{Water,Air} Essence)
stopitems:insert(allitems:item('351:1'))   -- Rose Red (->Dye Essence, Rose)
stopitems:insert(allitems:item('351:11'))  -- Dandelion Yellow (->Flower, Goldenrod)
stopitems:insert(allitems:item('351:2'))   -- Cactus Green (->Cactus etc)

for _, item in pairs(stopitems) do
    item:clearrecipes()
end

deps = ItemSet:new()
local function foodDependencies(item)
    if not deps:exists(item) then
        deps:insert(item)
    end
    -- if stopitems:exists(item) then return end
    for _, rcp in ipairs(item.recipes) do
        for _, elem in rcp.inputs:items() do
            if elem and elem ~= kNone then
                for _, it in ipairs(elem) do
                    if not deps:exists(it) then
                        foodDependencies(it)
                    end
                end
            end
        end
    end
end

-- All the Pam's HarvestCraft foods have a one-item oredict entry
-- whose name starts with '@food', so this makes them easy to find.
for _, item in pairs(allitems:filter(oredictName('^@food'))) do
    foodDependencies(item)
end

local function isMakeable(item)
    return item:makeable() or (item.index and item.pos)
end

makeable = deps:filter(isMakeable)
require 'serializer'
s = Serializer:new()
s:write('if turtle then')
s:write('    os.loadAPI(\'lib/items\')')
s:write('    Item = items.Item')
s:write('    ItemSet = items.ItemSet')
s:write('    os.loadAPI(\'lib/recipes\')')
s:write('    Shaped = recipes.Shaped')
s:write('    Shapeless = recipes.Shapeless')
s:write('    Recipe = recipes.Recipe')
s:write('end')
s:write('')
s:write('len = %s', turtle.len)
s:partial('recipes = ')
makeable:serialize(s)
s:write('')
s:write('recipes:resolve()')

fh = io.open('recipebook', 'w')
fh:write(tostring(s))
fh:close()

-- Lua's file handling API is ... poor. Shell out to python again.
ok, out, exit = os.execute('python install.py "'..arg[1]..'" "'..turtle.id..'"')
if not ok then
    print('Failed to execute install.py.')
    print(out)
    os.exit(1)
end
