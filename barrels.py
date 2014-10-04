#! /usr/bin/python

import collections
import itertools
import operator
import sys

from pymclevel import mclevel

X, Y, Z = 'x', 'y', 'z'
O = {Z: X, X: Z}

class Axis(object):
    def __init__(self, axis):
        self.axis = axis
        self.plane = O[axis]
        self._barrels = collections.defaultdict(list)

    def barrel(self, b):
        self._barrels[b[self.axis]].append(b)

    def ringFor(self, b):
        # A single ring along the axis has a fixed axis coordinate
        # and 8 barrels in the plane of that coordinate in this pattern:
        #   37   ^
        #  2  6  |
        #  1T 5  y
        #   04    plane ->
        #   ^-- this barrel is considered to be the index barrel for the ring
        # They are numbered in this order because we convert (x, y, z) linear
        # coords to (axis, index) polar coords to make turtle movement easier.
        # NOTE: if self.axis is Z, then these coords are Z, Y, X!
        yield (b[self.axis], b[Y],     b[self.plane]    )
        yield (b[self.axis], b[Y] + 1, b[self.plane] - 1)
        yield (b[self.axis], b[Y] + 2, b[self.plane] - 1)
        yield (b[self.axis], b[Y] + 3, b[self.plane]    )

        yield (b[self.axis], b[Y],     b[self.plane] + 1)
        yield (b[self.axis], b[Y] + 1, b[self.plane] + 2)
        yield (b[self.axis], b[Y] + 2, b[self.plane] + 2)
        yield (b[self.axis], b[Y] + 3, b[self.plane] + 1)

    def findRings(self):
        # yield all sets of >4 contiguous rings along this axis
        rings = []
        for blist in self._barrels.itervalues():
            if len(blist) < 8:
                continue
            lut = {(b[self.axis], b[Y], b[self.plane]): b for b in blist}
            for i in xrange(len(blist)):
                found = True
                for coords in self.ringFor(blist[i]):
                    found = found and (coords in lut)
                if found:
                    barrels = map(lambda coords: lut[coords],
                                  self.ringFor(blist[i]))
                    rings.append({
                        X: blist[i][X],
                        Y: blist[i][Y],
                        Z: blist[i][Z],
                        'barrels': barrels,
                    })
        rings.sort(key=operator.itemgetter(self.axis))

        start = 0
        for i in xrange(1, len(rings)):
            if rings[i-1][self.axis] + 1 != rings[i][self.axis]:
                if i - start > 3:
                    yield RingSet(self.axis, rings[start:i-1])
                start = i
        if len(rings) - start > 3:
            yield RingSet(self.axis, rings[start:])


class RingSet(object):
    def __init__(self, axis, rings):
        self.axis = axis
        self.plane = O[axis]
        self._rings = rings
        # rings is sorted in ascending order initially
        self.orientation = +1

    def __len__(self):
        return len(self._rings)

    def __iter__(self):
        # Yields a list of the 8 barrels at ring index N for each iter.
        return itertools.imap(operator.itemgetter('barrels'), self._rings)

    def __str__(self):
        # Produces a file for lua to read. The first line contains
        # the absolute coordinates of the turtle and the length and
        # orientation of the ringset from that turtle. Every other line
        # contains 8 item IDs (or 'None') detailing what's in the
        # barrel at that particular position. The first line corresponds
        # to the ring closest to the turtle, the next to the next, etc.
        # The line is ordered as in the doc for ringFor() above.
        s = ['Turtle id=%d x=%d y=%d z=%d len=%d' % (
            self.t['id'], self.t[X], self.t[Y], self.t[Z], len(self))]
        for r in self:
            s.append(' '.join(str(b['item']) for b in r))
        return '\n'.join(s)

    def validate(self, level):
        # A valid ringset has exactly one turtle.
        for x, y, z, invert, reverse in self.turtleLocs():
            t = level.tileEntityAt(x, y, z)
            if t and t['id'].value.startswith('turtle'):
                if invert:
                    # The turtle is facing the rings the "wrong" way, so 
                    # invert each pair of barrels in each ring such
                    # that (T being the turtle's position):
                    #   37      73 
                    #  2  6    6  2
                    #  1 T5 -> 5 T1
                    #   04      40
                    self.invert()
                if reverse:
                    # The turtle is at the "end" of the rings, so reverse
                    # the array such that we are descending along the axis.
                    self.orientation = -1
                    self._rings.reverse()
                self.t = {
                    X: t[X].value,
                    Y: t[Y].value,
                    Z: t[Z].value,
                    'id': t['computerID'].value,
                    'turtle': t,
                }
                return True
        return False

    def turtleLocs(self):
        # A contiguous set of rings has 2 possible turtle locations, at the
        # start, and at the end.
        if self.axis == X:
            yield self._rings[0][X] - 1, self._rings[0][Y] + 1, self._rings[0][Z], False, False
            yield self._rings[-1][X] + 1, self._rings[-1][Y] + 1, self._rings[-1][Z] + 1, True, True
        elif self.axis == Z:
            yield self._rings[0][X] + 1, self._rings[0][Y] + 1, self._rings[0][Z] - 1, True, False
            yield self._rings[-1][X], self._rings[-1][Y] + 1, self._rings[-1][Z] + 1, False, True

    def invert(self):
        for r in self:
            r[0], r[4] = r[4], r[0]
            r[1], r[5] = r[5], r[1]
            r[2], r[6] = r[6], r[2]
            r[3], r[7] = r[7], r[3]

    def barrel(self, index, pos):
        # Having validated the ring, our polar coords are the two-level array
        # indices of self._rings.
        if not self.t:
            return
        return self._rings[index]['barrels'][pos]

def main(args):
    level = mclevel.fromFile(args[0] + '/level.dat')
    byX = Axis(X)
    byZ = Axis(Z)
    # I tried using JABBA/dataN.dat but they are often out-of-date
    # so this goes through all level chunks. This can take a while.
    for x, z in level.allChunks:
        c = level.getChunk(x, z)
        for t in c.TileEntities:
            if t['id'].value == 'TileEntityBarrel':
                s = t['storage']
                i = None
                if 'current_item' in s:
                    i = s['current_item']
                    i = '%s:%s' % (i['id'].value, i['Damage'].value)
                b = {
                    X: int(t[X].value),
                    Y: int(t[Y].value),
                    Z: int(t[Z].value),
                    'item': i,
                }
                byX.barrel(b)
                byZ.barrel(b)

    for ring in byX.findRings():
        if ring.validate(level):
            print ring

    for ring in byZ.findRings():
        if ring.validate(level):
            print ring

if __name__ == '__main__':
    main(sys.argv[1:])
