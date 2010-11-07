import itertools as it, operator as op, functools as ft
from PIL import Image, ImageMath, ImageColor


from collections import namedtuple
from sympy.geometry import Point as _Point, Line
import types

class Point(_Point):
	x = property(lambda s: s[0])
	y = property(lambda s: s[1])
	distance_from = lambda s, p: s.distance(s, p)

class Offset(namedtuple('Offset', 'x y')):
	__slots__ = ()
	def from_point(self, *loc):
		return Point(*((loc[i] + self[i]) for i in xrange(2)))
	def on_canvas(self, size):
		return Point(*(( self[i] if self[i] >= 0
			else (size[i] + self[i]+1) ) for i in xrange(2)))

class Color(namedtuple('Color', 'R G B A')):
	__slots__ = ()
	def __new__(cls, *color):
		scons = super(Color, cls).__new__
		if len(color) != 1:
			if len(color) == 3: color = color + (0xff,)
			return scons(cls, *color)
		else:
			color, = color
			if isinstance(color, types.StringTypes): # PIL parses only RGB spec
				return scons(cls, *(ImageColor.getrgb(color) + (0xff,)))
			else:
				return scons(cls, *reversed([
					int(0xff & (color >> x)) for x in xrange(0,32,8) ]))


## Wish I've had geometric algebra at school, so I could use sympy's GA ;)
rel_pos = lambda a,b,c,p: a*p.x + b*p.y + c

def draw_gradient( img,
		p1=Offset(0,0), p2=Offset(-1,-1),
		rgba1=0xff0000ff, rgba2=0x00ff0088 ):
	# Proof-of-concept.
	# PIL doesn't seem to be able to draw arbitrary gradients internally,
	#  guess I'll have to use something like pycairo for that.
	# Horribly slow, to the point of being totally unusable!
	# Not thoroughly tested.

	p1, p2 = (( p.on_canvas(img.size)
		if isinstance(p, Offset) else Point(*p) ) for p in (p1, p2))
	rgba1, rgba2 = it.imap(Color, (rgba1, rgba2))

	vec, dist = Line(p1, p2), p1.distance_from(p2)
	n1, n2 = it.imap(vec.perpendicular_line, (p1, p2))
	n1_pos, n2_pos = (ft.partial(rel_pos, *n.coefficients) for n in (n1, n2))

	gpoint = lambda v2,v1,p: v1 + p * (v2 - v1)
	gpoint = lambda p,bands=list( ft.partial(gpoint, v1, v2)
		for v1,v2 in it.izip(rgba1, rgba2) ): tuple(int(round(f(p),0)) for f in bands)

	for p3 in it.starmap(Point, it.product(*it.imap(xrange, img.size))):
		np1, np2 = n1_pos(p3), n2_pos(p3)
		if np1 <= 0 and np2 <= 0: rgba3 = rgba2
		elif np1 >= 0 and np2 >= 0: rgba3 = rgba1
		else: rgba3 = gpoint(n1.perpendicular_segment(p3).length / dist)
		img.putpixel(p3, rgba3)


img = Image.new('RGBA', (30, 30))
draw_gradient(img, Offset(5,5), p2=Offset(-5,-5))
img.save('image.png')
