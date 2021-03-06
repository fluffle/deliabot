Delia!
------

Delia is a set of lua scripts for a
[ComputerCraft](http://computercraft.info)
[Turtle](http://computercraft.info/wiki/Turtle_%28API%29)
that automates the creation of
[HarvestCraft](http://harvestcraftmod.wikia.com/wiki/HarvestCraft_Wiki)
foods for [FTB Blood 'n' Bones](http://wiki.feed-the-beast.com/BloodNBones).

Given different input data (see the various recipe dump files in `data/`) it
should be possible to use this same code with other mod packs. It's unlikely
anyone will ever bother, since AE is *much* easier. The make code is flexible
enough to craft any shapeless recipe in the game, as long as careful attention
is paid to loops in the dependency graph. Shaped recipes are left as an
exercise to the reader ;-)

Dependencies
============

### Linux:

    sudo apt-get install lua5.2 python2.7 python-numpy python-yaml

### Windows:

Hopefully the EXEs provided will work. `create_recipe_book.exe` was created
with [srlua](https://github.com/LuaDist/srlua) and Daniel Quintela's
[precompiled windows version](http://www.soongsoft.com/lhf/lua/5.1/srlua.tgz).
`barrels.exe` and `install.exe` were created with [py2exe](http://www.py2exe.org/). 

Setting up Delia
================

This set of instructions is probably too long for most people to care :-)

If anyone fancies making a YT video of their build and this thing in action
I'd much appreciate knowing about it so I can link to it here.

Turtles are quite limited. For them to be able to find items for crafting,
the items must be stored in barrels. Delia requires a very particular barrel
structure, a 4x4 cylinder of barrels with a set of chests and a furnace at one
end, with the turtle placed above a fuel barrel at one end. Some screenshots:

https://raw.githubusercontent.com/fluffle/deliabot/master/img/2014-10-12_20.52.22.png
https://raw.githubusercontent.com/fluffle/deliabot/master/img/2014-10-12_20.52.35.png
https://raw.githubusercontent.com/fluffle/deliabot/master/img/2014-10-12_20.52.54.png
https://raw.githubusercontent.com/fluffle/deliabot/master/img/2014-10-12_20.53.32.png

Each ring in the cylinder provides 8 barrels for storage. I recommend placing
the 8 harvestcraft tools in the closest ring to the turtle and having
common items like water, milk, salt, wheat, dough, cheese, butter and stock 
near the turtle too. Other than that, the turtle prefers closer items when
crafting, so if you have items you don't want to get used except for specific
things then place them further down the cylinder.

You can run itemducts along the 4 corners of the cylinder to allow items to be
added to the barrels easily. A reasonable setup will need 6-10 rings of barrels
in the cylinder to be able to create a wide range of food.

Once you have built this cylinder and put items in barrels, place the turtle
and label it. Place a vanilla crafting table into it's inventory slot 1, then
open up the lua console and type `turtle.equipLeft()` then `exit()`. Edit a
script so that the data directory is created, then save and exit the game.
Grab the [latest .zip](https://github.com/fluffle/deliabot/archive/master.zip)
of this code and extract it somewhere, or `git clone` it from here.

If you're running the Python/Lua directly then grab the
[latest .zip](https://github.com/mcedit/pymclevel/archive/master.zip)
of pymclevel and put it in pymclevel, or run `git submodule update --init` to
sync the submodule. The windows EXEs have all their dependencies bundled in and
shouldn't need the local copy of pymclevel.

Run `lua create_recipe_book.lua /path/to/save/folder` (or, on Windows,
`create_recipe_book.exe c:\path\to\save\folder`). This will read in the
item and recipe data, open up your level, locate the ring you have built and
figure out what items are in which barrels. It will then figure out what
HarvestCraft recipes it is possible to make from the set of items you have
in barrels, and write out a recipe book to the local folder. 

It should then copy a bunch of files into your save folder once it is done.
Note: this can (and should) be re-run in the future if you change the
ingredients in your barrels.

Using Delia
===========

Hopefully, if all has gone well, you *should* be able to type, for example:

    make 4 hearty breakfast

... and watch. The upper-left chest is used for temporary crafting storage,
while the lower-left chest is where the finished product gets put. The
upper-right chest feeds into the furnace, which then outputs into the
lower-right chest.

You can also use `fetch` to fetch items from barrels to the output chest:

    fetch 16 salt

And `list` will print out the stuff that Delia can currently make.

Things that won't work
======================

  - Hunger Overhaul's stack size changes for foodstuffs are very awkward.
    Trying to make more than N of an item, where N is the smallest stack size
    of one of it's components, will probably break horribly. The temporary
    crafting chest will have more than one stack of an item in it, and this
    will result in the turtle not pulling out the items it *thinks* it is
    pulling out. To be on the safe side, make items in batches of 4 or 8.

  - Making items that have many intermediate, barrel-less dependencies is
    prone to failure because of the semantics of turtle/chest interaction.
    Inserts go to the first empty chest slot, and retrieval is from the first
    full chest slot, which means that using the temp chest to store
    intermediate ingredients for more than one recipe concurrently is almost
    certainly doomed to failure.
  
  - Probably lots of other things, this has only been minimally tested. Please
    file bugs, feature requests, complaints, flames etc as GitHub issues. I
    reserve the right to unilaterally ignore anything and anyone :-)
    
Disclaimer
==========

No warranty is provided for any of this code. If it destroys your world, sorry,
these things happen. Make backups. Be sensible. Good luck in the harsh world of
Blood 'n' Bones ;-)
