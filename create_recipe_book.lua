#! /usr/bin/lua

-- We have input files in recipe dump format, but this is not amazingly
-- helpful, especially when shapeless recipe handling is broken:
-- https://github.com/vitzli/recipedumper/issues/1

-- Load in the dumped list of items from a file.
require 'items'
allitems = ItemSet:fromfile('itemids')
pamitems = allitems:filter(function(item)
    -- All the Pam's HarvestCraft items are clearly marked in the item list.
    return item.class:sub(1, 20) == 'item.PamHarvestCraft'
end)

-- Load in the ore dictionary, resolving IDs to Items.
require 'oredict'
oredict = OreDict:fromfile('oredict', allitems)

-- Load in all the recipes. First from the heap-derived data, then falling back
-- to the dumped data for all non-shapelessore recipes. Note: shapedore recipes
-- may be broken in the same way to shapeless ones.
require 'recipes'
LoadRecipes('shapeless_ore_recipes', allitems, oredict)
LoadRecipes('not_shapeless_ore_recipes', allitems, oredict)

-- for _, item in pairs(pamitems) do
--     print(item)
-- end

