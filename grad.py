import itertools as it, operator as op, functools as ft


from collections import namedtuple
import types

class Color(namedtuple('Color', 'R G B A')):
	__slots__ = ()
	def __new__(cls, *color):
		scons = super(Color, cls).__new__
		if len(color) > 2:
			if len(color) == 3: color = color + (0xff,)
			return scons(cls, *color)
		elif len(color) == 2:
			color, alpha = color
			if isinstance(alpha, float): alpha = int(alpha * 255)
		else: (color,), alpha = color, None
		if isinstance(color, types.StringTypes):
			cs = str(color).lstrip('#').split('0x', 1)[-1]
			cl = len(cs)
			if cl not in (3,4,6,8): raise ValueError(color)
			if alpha is None and cl in (3,6): alpha = 0xff
			if cl in (3,4):
				color = int( ''.join(it.chain.from_iterable((cs[i], cs[i]) for i in xrange(cl)))
					+ '{0:02x}'.format(alpha) if alpha is not None else '', 16 )
			else:
				color = int(cs, 16)
				if cl == 6: color = (color << 8) + alpha
			alpha = None # it's already taken into account
		cl, alpha = (4, list()) if alpha is None else (3, [alpha])
		return scons(cls, *(list(reversed([
			int(0xff & (color >> x*8)) for x in xrange(cl) ])) + alpha))

class CairoColor(Color):
	__slots__ = ()
	def __new__(cls, *color):
		color = super(CairoColor, cls).__new__(cls, *color)
		return super(Color, cls).__new__(cls, *(cs/255.0 for cs in color))


from collections import Iterable, Iterator

def flatten(*vals):
	for val in vals:
		if isinstance(val, (Iterable, Iterator))\
				and not isinstance(val, types.StringTypes):
			for val in flatten(*val): yield val
		else: yield val


import cairo as c

img = c.ImageSurface(c.FORMAT_ARGB32, 512, 768)
ctx = c.Context(img)
ctx.scale(img.get_width(), img.get_height())

# Main pattern
p1, p2 = (.75, .25), (.5, 1)
grad = c.LinearGradient(*flatten(p1, p2))
grad.add_color_stop_rgba(.25, *CairoColor('001200', 1.0))
grad.add_color_stop_rgba(.5, *CairoColor('001000', .9))
grad.add_color_stop_rgba(.8, *CairoColor('000a00', .7))
grad.add_color_stop_rgba(1, *CairoColor('000', .5))
ctx.rectangle(0, 0, 1, 1)
ctx.set_source(grad)
ctx.fill()

# Edge fades
ctx.set_operator(c.OPERATOR_DEST_OUT)
p1 = 0,0
for p2 in ((1,0),(0,1)):
	grad = c.LinearGradient(*flatten(p1, p2))
	grad.add_color_stop_rgba(0, *CairoColor(0, .1))
	grad.add_color_stop_rgba(.15, *CairoColor(0, 0))
	grad.add_color_stop_rgba(.85, *CairoColor(0, 0))
	grad.add_color_stop_rgba(1, *CairoColor(0, .1))
	ctx.rectangle(0, 0, 1, 1)
	ctx.set_source(grad)
	ctx.fill()
ctx.set_operator(c.OPERATOR_OVER)

# Light spot
p1, p2 = (.75, .25), (.5, .5)
grad = c.RadialGradient(*flatten(p1, 0, p2, .5))
grad.add_color_stop_rgba(0, *CairoColor('fff', 0.1))
grad.add_color_stop_rgba(1, *CairoColor('fff', 0))
ctx.rectangle(0, 0, 1, 1)
ctx.set_source(grad)
ctx.fill()

img.write_to_png('image.png')
img.finish()
