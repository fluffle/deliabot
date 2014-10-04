#! /usr/bin/lua

-- We have input files in recipe dump format, but this is not amazingly
-- helpful, especially when shapeless recipe handling is broken:
-- https://github.com/vitzli/recipedumper/issues/1

-- None is used in many places.
kNone = 'None'

-- Load in the dumped list of items from a file.
require 'items'
allitems = ItemSet:fromfile('itemids')

-- Load in the ore dictionary, resolving IDs to Items.
require 'oredict'
oredict = OreDict:fromfile('oredict', allitems)

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
        if ignore(line) then goto continue end
        local rcp = Recipe:fromline(line, itemset, oredict)
        if rcp then
            rcp.output:addrecipe(rcp)
        end
        ::continue::
    end
    fh.close()
end
LoadRecipes('shapeless_ore_recipes', allitems, oredict)
LoadRecipes('not_shapeless_ore_recipes', allitems, oredict)

-- Load in the set of items we have available in our barrels.
require 'barrels'
barrels = RingSet:fromfile('barrels_testing', allitems)

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
        if barrels:exists(item) then
           item.barrel = barrels:exists(item) 
        end
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
    return item:makeable() or item.barrel
end

makeable = deps:filter(isMakeable)
require 'serializer'
s = Serializer:new()
makeable:serialize(s)
print('return ' .. tostring(s))
