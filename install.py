#! /usr/bin/python

import os, shutil, sys

LIBS = [
    'delia.lua', 'items.lua', 'recipes.lua', 
    'make.lua', 'recipebook', 'util.lua',
]
BINS = ['debug', 'fetch', 'list', 'make']

def main(args):
    if len(args) != 2:
        print 'Usage: install.py <save folder> <turtle id>'
        return 1
    levelfile = os.path.join(args[0], 'level.dat')
    if not os.path.exists(levelfile):
        print 'Could not find level.dat at %s' % levelfile
        return 2
    turtledir = os.path.join(args[0], 'computer', args[1])
    if not os.path.exists(turtledir):
        os.mkdir(turtledir, 0755)
    libdir = os.path.join(turtledir, 'lib')
    os.mkdir(libdir, 0755)
    for lib in LIBS:
        dest = os.path.join(libdir, os.path.splitext(lib)[0])
        print 'Copying %s -> %s' % (lib, dest)
        shutil.copyfile(lib, dest)
    for exe in BINS:
        dest = os.path.join(turtledir, exe)
        print 'Copying %s -> %s' % (exe, dest)
        shutil.copyfile(exe, dest)
    print 'All done!'


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
