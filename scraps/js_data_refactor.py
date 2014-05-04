#!/usr/bin/env python
# -*- coding: utf-8 -*-

data = '''
[
{name: "Aitoff", projection: d3.geo.aitoff()},
{name: "Albers", projection: d3.geo.albers().scale(145).parallels([20, 50])},
{name: "August", projection: d3.geo.august().scale(60)},
{name: "Baker", projection: d3.geo.baker().scale(100)},
{name: "Boggs", projection: d3.geo.boggs()},
{name: "Bonne", projection: d3.geo.bonne().scale(120)},
{name: "Bromley", projection: d3.geo.bromley()},
{name: "Collignon", projection: d3.geo.collignon().scale(93)},
{name: "Craster Parabolic", projection: d3.geo.craster()},
{name: "Eckert I", projection: d3.geo.eckert1().scale(165)},
{name: "Eckert II", projection: d3.geo.eckert2().scale(165)},
{name: "Eckert III", projection: d3.geo.eckert3().scale(180)},
{name: "Eckert IV", projection: d3.geo.eckert4().scale(180)},
{name: "Eckert V", projection: d3.geo.eckert5().scale(170)},
{name: "Eckert VI", projection: d3.geo.eckert6().scale(170)},
{name: "Eisenlohr", projection: d3.geo.eisenlohr().scale(60)},
{name: "Equirectangular (Plate Carrée)", projection: d3.geo.equirectangular()},
{name: "Hammer", projection: d3.geo.hammer().scale(165)},
{name: "Hill", projection: d3.geo.hill()},
{name: "Goode Homolosine", projection: d3.geo.homolosine()},
{name: "Kavrayskiy VII", projection: d3.geo.kavrayskiy7()},
{name: "Lambert cylindrical equal-area", projection: d3.geo.cylindricalEqualArea()},
{name: "Lagrange", projection: d3.geo.lagrange().scale(120)},
{name: "Larrivée", projection: d3.geo.larrivee().scale(95)},
{name: "Laskowski", projection: d3.geo.laskowski().scale(120)},
{name: "Loximuthal", projection: d3.geo.loximuthal()},
{name: "Mercator", projection: d3.geo.mercator().scale(490 / 2 / Math.PI)},
{name: "Miller", projection: d3.geo.miller().scale(100)},
{name: "McBryde–Thomas Flat-Polar Parabolic", projection: d3.geo.mtFlatPolarParabolic()},
{name: "McBryde–Thomas Flat-Polar Quartic", projection: d3.geo.mtFlatPolarQuartic()},
{name: "McBryde–Thomas Flat-Polar Sinusoidal", projection: d3.geo.mtFlatPolarSinusoidal()},
{name: "Mollweide", projection: d3.geo.mollweide().scale(165)},
{name: "Natural Earth", projection: d3.geo.naturalEarth()},
{name: "Nell–Hammer", projection: d3.geo.nellHammer()},
{name: "Polyconic", projection: d3.geo.polyconic().scale(100)},
{name: "Robinson", projection: d3.geo.robinson()},
{name: "Sinusoidal", projection: d3.geo.sinusoidal()},
{name: "Sinu-Mollweide", projection: d3.geo.sinuMollweide()},
{name: "van der Grinten", projection: d3.geo.vanDerGrinten().scale(75)},
{name: "van der Grinten IV", projection: d3.geo.vanDerGrinten4().scale(120)},
{name: "Wagner IV", projection: d3.geo.wagner4()},
{name: "Wagner VI", projection: d3.geo.wagner6()},
{name: "Wagner VII", projection: d3.geo.wagner7()},
{name: "Winkel Tripel", projection: d3.geo.winkel3()}
]
'''

import re
data = re.sub(r'(?<=projection: )(d3\..*)(?=\})', r"'\1'", data)

import yaml, operator as op

data = yaml.load(data)
data = sorted(data, key=op.itemgetter('name'))

data_tuple = op.itemgetter('name', 'projection')
for el in data:
	name, projection = data_tuple(el)
	assert "'" not in name
	print u"'{}': -> {}".format(name, projection).encode('utf-8')
