#! /usr/bin/lua

-- We want to produce recipedumper compatible output, so:
-- recipedumper:shapelessore!(@LIST,N)...->(ID,N)
--
-- This is done with a join across four mappings extracted from a heap dump:
--  1) input_arraylist_to_output_id
--  2) minecraft_itemstack_to_output_id
--  3) oredict_id_to_input_arraylist
--  4) oredict_name_to_oredict_id

-- Alternatively we might produce a serialized lua table.

oreid2name = {}
fh = io.open('oredict_name_to_oredict_id', 'r')
for line in fh:lines() do
    if line:sub(1,4) == 'java' then
        s, _, name = line:find('|(%S+)')
        _, _, id = line:find('|(%S+)', s+1)
        if oreid2name[id] ~= nil then
            print('Duplicate id ' .. id .. ' is both ' .. name .. ' and ' .. oreid2name[id])
        end
        oreid2name[id] = name
    end
end
fh:close()

array2orename = {}
fh = io.open('oredict_id_to_input_arraylist')
for line in fh:lines() do
    if line:sub(1,4) == 'java' then
        s, _, id = line:find('|(%S+)')
        _, _, array = line:find('@ (0x%x+)', s+1)
        if oreid2name[id] ~= nil then
            array2orename[array] = oreid2name[id]
        else
            print('No name found for id ' .. id .. ', array ' .. array)
        end
    end
end
fh:close()

-- this one is big because I just dumped all ItemStacks in the game...
is2itemid = {}
fh = io.open('minecraft_itemstack_to_output_id')
for line in fh:lines() do
    if line:sub(1,3) == 'net' then
        s, _, is = line:find('id=(0x%x+)')
        _, _, id = line:find('|(%S+)', s+1)
        is2itemid[is] = id
    end
end
fh:close()

-- now we can resolve the list of heap objects in the input arraylist to 
-- either oredict names or item IDs.
out = io.open('shapeless_ore_recipes', 'w')
fh = io.open('input_arraylist_to_output_id', 'r')
for line in fh:lines() do
    if line:sub(1,1) == '[' then
        local inputs = {}
        -- lua string handling does not make this easy
        s = 2
        while true do
            e, _ = line:find(',', s)
            if e == nil then break end
            substr = line:sub(s, e-1)
            if substr:sub(1,4) == 'null' then break end
            _, _, id = substr:find('id=(0x%x+)')
            if substr:sub(1, 4) == 'java' then
                if array2orename[id] == nil then
                    print('No name found for array ' .. id)
                else
                    table.insert(inputs, "@" .. array2orename[id] .. ',1')
                end
            elseif substr:sub(1,3) == 'net' then
                if is2itemid[id] == nil then
                    print('No output id found for ' .. id)
                else
                    table.insert(inputs, is2itemid[id] .. ',1')
                end
            else
                print('WTF substring ' .. substr)
                break
            end
            s = e + 2
        end
        -- hopefully at this point we have collected all the inputs.
        _, _, output = line:find('|(%S+)', s)
        out:write('recipedumper:shapelessore!')
        for _, thing in ipairs(inputs) do
          out:write('(', thing, ')')
        end
        out:write('->(', output, ')\n')
    end
end
fh:close()
out:close()
        
          
      
      

