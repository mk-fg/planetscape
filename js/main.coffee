# require('nw.gui').Window.get().showDevTools()

opts =

	w: window.innerWidth * 0.9
	h: window.innerHeight * 0.9

	world: require('./data/world-110m.json')

	projections:
		'Aitoff': -> d3.geo.aitoff()
		'Albers': -> d3.geo.albers().scale(145).parallels([20, 50])
		'August': -> d3.geo.august().scale(60)
		'Baker': -> d3.geo.baker().scale(100)
		'Boggs': -> d3.geo.boggs()
		'Bonne': -> d3.geo.bonne().scale(120)
		'Bromley': -> d3.geo.bromley()
		'Collignon': -> d3.geo.collignon().scale(93)
		'Craster Parabolic': -> d3.geo.craster()
		'Eckert I': -> d3.geo.eckert1().scale(165)
		'Eckert II': -> d3.geo.eckert2().scale(165)
		'Eckert III': -> d3.geo.eckert3().scale(180)
		'Eckert IV': -> d3.geo.eckert4().scale(180)
		'Eckert V': -> d3.geo.eckert5().scale(170)
		'Eckert VI': -> d3.geo.eckert6().scale(170)
		'Eisenlohr': -> d3.geo.eisenlohr().scale(60)
		'Equirectangular (Plate Carrée)': -> d3.geo.equirectangular()
		'Goode Homolosine': -> d3.geo.homolosine()
		'Hammer': -> d3.geo.hammer().scale(165)
		'Hill': -> d3.geo.hill()
		'Kavrayskiy VII': -> d3.geo.kavrayskiy7()
		'Lagrange': -> d3.geo.lagrange().scale(120)
		'Lambert cylindrical equal-area': -> d3.geo.cylindricalEqualArea()
		'Larrivée': -> d3.geo.larrivee().scale(95)
		'Laskowski': -> d3.geo.laskowski().scale(120)
		'Loximuthal': -> d3.geo.loximuthal()
		'McBryde–Thomas Flat-Polar Parabolic': -> d3.geo.mtFlatPolarParabolic()
		'McBryde–Thomas Flat-Polar Quartic': -> d3.geo.mtFlatPolarQuartic()
		'McBryde–Thomas Flat-Polar Sinusoidal': -> d3.geo.mtFlatPolarSinusoidal()
		# 'Mercator': -> d3.geo.mercator().scale(490 / 2 / Math.PI)
		'Miller': -> d3.geo.miller().scale(100)
		'Mollweide': -> d3.geo.mollweide().scale(165)
		'Natural Earth': -> d3.geo.naturalEarth()
		'Nell–Hammer': -> d3.geo.nellHammer()
		'Polyconic': -> d3.geo.polyconic().scale(100)
		'Robinson': -> d3.geo.robinson()
		'Sinu-Mollweide': -> d3.geo.sinuMollweide()
		'Sinusoidal': -> d3.geo.sinusoidal()
		'Wagner IV': -> d3.geo.wagner4()
		'Wagner VI': -> d3.geo.wagner6()
		'Wagner VII': -> d3.geo.wagner7()
		'Winkel Tripel': -> d3.geo.winkel3()
		'van der Grinten': -> d3.geo.vanDerGrinten().scale(75)
		'van der Grinten IV': -> d3.geo.vanDerGrinten4().scale(120)

# Scaling factors are straight from http://bl.ocks.org/mbostock/3711652
scale_factor = Math.min(opts.w / 960, opts.h / 500)
for k, p0 of opts.projections
	do (p0) ->
		opts.projections[k] = ->
			p = p0().rotate([0, 0, 0]).center([0, 0])
			p.scale(p.scale() * scale_factor)
				.translate(v * scale_factor for v in p.translate())
projections_idx = (k for k, v of opts.projections)


projection = opts.projections['Aitoff']()
path = d3.geo.path().projection(projection)
graticule = d3.geo.graticule()

svg = d3.select('.container').append('svg')
	.attr('width', opts.w)
	.attr('height', opts.h)
	.classed('centered', true)
	.style(
		'margin-left': '-' + (opts.w / 2) + 'px'
		'margin-top': '-' + (opts.h / 2) + 'px' )
	# .attr('viewBox', "0 0 #{opts.w} #{opts.h}")

svg.append('defs').append('path')
	.datum(type: 'Sphere')
	.attr('id', 'sphere')
	.attr('d', path)

svg.append('use')
	.attr('class', 'stroke')
	.attr('xlink:href', '#sphere')

svg.append('use')
	.attr('class', 'fill')
	.attr('xlink:href', '#sphere')

svg.append('path')
	.datum(graticule)
	.attr('class', 'graticule')
	.attr('d', path)

svg.insert('path', '.graticule')
	.datum(topojson.feature(opts.world, opts.world.objects.land))
	.attr('class', 'land')
	.attr('d', path)


change = ->
	k = projections_idx[this.selectedIndex]
	update(name: k, projection: opts.projections[k]())

update = (option) ->
	svg.selectAll('path').transition()
		.duration(750)
		.attrTween('d', projectionTween(projection, projection = option.projection))

projectionTween = (projection0, projection1) ->
	(d) ->
		project = (λ, φ) ->
			λ *= 180 / Math.PI
			φ *= 180 / Math.PI
			[p0, p1] = [projection0([λ, φ]), projection1([λ, φ])]
			[(1 - t) * p0[0] + t * p1[0], (1 - t) * - p0[1] + t * -p1[1]]
		t = 0
		projection = d3.geo.projection(project)
			.scale(1)
			.translate([opts.w / 2, opts.h / 2])
		path = d3.geo.path()
			.projection(projection)
		(_) ->
			t = _
			path(d)

menu = d3.select('#projection-menu')
	.on('change', change)

menu.selectAll('option')
		.data({name: k, projection: v()} for k, v of opts.projections)
	.enter().append('option')
		.text (d) -> d.name
