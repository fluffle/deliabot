#! /usr/bin/lua

-- We have input files in recipe dump format, but this is not amazingly
-- helpful, especially when shapeless recipe handling is broken:
-- https://github.com/vitzli/recipedumper/issues/1

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
    allitems:item('15507:0'),
    allitems:item('15759:0'))

function oredictName(match)
    return function (item)
        if not oredict:names(item) then return false end
        for _, name in ipairs(oredict:names(item)) do
            if name:match(match) then
                return true
            end
        end
    end
end

-- All the Pam's HarvestCraft foods have a one-item oredict entry
-- whose name starts with '@food', so this makes them easy to find.
fooditems = allitems:filter(oredictName('^@food'))
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
    -- Bags introduce nasty graph cycles, as does the sugar cube.
    badoutputs = {
        '12670:0', -- carrot bag
        '12669:0', -- potato bag
        '12675:0', -- bonemeal bag
        '12671:0', -- nether wart bag
        '4049:1',  -- sugar cube
    }
    for _, id in ipairs(badoutputs) do
        if line:match('![^-]+->%('..id..',1%)') then
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
            for _, elem in rcp.inputs:items() do
                if elem ~= kNone then
                    for _, item in ipairs(elem) do
                        item:setusedin(rcp.output)
                    end
                end
            end 
        end
        ::continue::
    end
    fh.close()
end
LoadRecipes('shapeless_ore_recipes', allitems, oredict)
LoadRecipes('not_shapeless_ore_recipes', allitems, oredict)

stopitems = ItemSet:new():mergefrom(toolitems)
stopitems:insert(allitems:item('15508:0')) -- Fresh Water
stopitems:insert(allitems:item('15507:0')) -- Fresh Milk

function recurse(item, indent)
    print(string.rep(' ', indent) .. item.name)
    if stopitems:item(item.id) then return end
    for i, rcp in ipairs(item.recipes) do
        for j, elem in rcp.inputs:items() do 
            if elem and elem ~= kNone then
                for k, it in ipairs(elem) do
                    recurse(it, indent + 2)
                    if elem.name and k < #elem then
                        -- oredict entry
                        print(string.rep(' ', indent + 4) .. 'or...')
                    end
                end
                if j < #rcp.inputs then
                    print(string.rep(' ', indent + 4) .. 'and...')
                end
            end
        end
        if i < #item.recipes then
            print(string.rep(' ', indent + 4) .. 'or...')
        end
    end
end

recurse(allitems:item('15554:0'), 0)
