
'use strict'

# require('nw.gui').Window.get().showDevTools()

u = require('./js/utils')
conntrace = require('./js/conntrace')
config = require('./js/config')

fs = require('fs')
util = require('util')


## Configuration

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
		'Bonne': -> d3.geo.bonne().scale(100)
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

	config_path_base: './data/config.yaml'
	config: null

do ->
	# Scaling factors are straight from http://bl.ocks.org/mbostock/3711652
	scale_factor = Math.min(opts.w / 960, opts.h / 500)
	for k, p0 of opts.projections
		do (p0) ->
			opts.projections[k] = ->
				p = p0().rotate([0, 0, 0]).center([0, 0])
				p.scale(p.scale() * scale_factor)
					.translate(v * scale_factor for v in p.translate())

	opts.config = config.load_conf(opts.config_path_base, process.env['PSC_CONF'])


## Projection

proj =
	name: opts.config.projection.name
	func: null
	path: null

	list: (k for k, v of opts.projections)
	graticule: d3.geo.graticule()

	traces: null
	markers: null

# XXX: these always go together - make proj.func/path reactive
proj.func = opts.projections[proj.name]()
	.translate([opts.w / 2, opts.h / 2])
proj.path = d3.geo.path().projection(proj.func)

svg = d3.select('svg')
	.attr('width', opts.w)
	.attr('height', opts.h)
	.attr('class', 'centered')
	.style(
		'margin-left': '-' + (opts.w / 2) + 'px'
		'margin-top': '-' + (opts.h / 2) + 'px' )

svg.append('defs').append('path')
	.datum(type: 'Sphere')
	.attr('id', 'sphere')
	.attr('d', proj.path)

svg.append('use')
	.attr('class', 'stroke')
	.attr('xlink:href', '#sphere')

svg.append('use')
	.attr('class', 'fill')
	.attr('xlink:href', '#sphere')

svg.append('path')
	.datum(proj.graticule)
	.attr('class', 'graticule')
	.attr('d', proj.path)

svg.insert('path', '.graticule')
	.datum(topojson.feature(opts.world, opts.world.objects.land))
	.attr('class', 'land')
	.attr('d', proj.path)

proj.traces = svg.append('g')
	.attr('id', 'traces')
proj.markers = svg.append('g')
	.attr('id', 'markers')


## Projection options menu

do ->
	projectionTween = (projection0, projection1) ->
		(d) ->
			project = (λ, φ) ->
				λ *= 180 / Math.PI
				φ *= 180 / Math.PI
				[p0, p1] = [projection0([λ, φ]), projection1([λ, φ])]
				[(1 - t) * p0[0] + t * p1[0], (1 - t) * - p0[1] + t * -p1[1]]
			t = 0
			proj.func = d3.geo.projection(project)
				.scale(1)
				.translate([opts.w / 2, opts.h / 2])
			proj.path = d3.geo.path().projection(proj.func)
			(_) ->
				t = _
				proj.path(d)

	update = ->
		k = proj.list[this.selectedIndex]
		[projection0, proj.func] = [proj.func, opts.projections[k]()]
		proj.name = k
		svg.selectAll('path').transition()
			.duration(750)
			.attrTween('d', projectionTween(projection0, proj.func))

	menu_opts = d3.select('#projection-menu')
			.style('display', 'block')
			.on('change', update)
		.selectAll('option')
			.data({name: k, projection: v()} for k, v of opts.projections)

	menu_opts.enter().append('option')
			.text((d) -> d.name)

	menu_opts
			.attr('selected', (d) -> if d.name == proj.name then true else null)


## Main loop

do ->
	tracer = conntrace.Tracer.in_domain()
	ct = conntrace.ConntrackSS.in_domain()

	# XXX: use other connection metadata (e.g. cmd/port for color)
	if ct.polling
		ct.on 'conn_list', (conn_list) ->
			tracer.conn_list(conn.remote.addr for conn in conn_list)
	else
		ct
			.on 'conn_add', (conn) ->
				tracer.conn_add(conn.remote.addr)
			.on 'conn_del', (conn) ->
				tracer.conn_del(conn.remote.addr)

	trace_path = d3.geo.path().projection(proj.func)
	source = opts.config.projection.source

	draw_traces = (traces) ->
		data = ( {ip: ip, trace: trace}\
			for own ip, trace of traces\
			when trace.filter((d) -> d.geo).length != 0 )

		traces = proj.traces.selectAll('path.trace')
			.data(data, (d) -> d.ip)
		traces.enter().append('path')
			.datum((d) ->
				type: 'MultiLineString'
				coordinates: do ->
					p0 = source[..].reverse()
					for node in d.trace
						u.assert(node.geo, [node, d.trace])
						p1 = node.geo[..].reverse()
						[p0, line] = [p1, [p0, p1]]
						line)
			.attr('class', 'trace')
			.attr('d', trace_path)
		traces.exit().remove()

		marker_traces = proj.markers.selectAll('g')
			.data(data, (d) -> d.ip)
		marker_traces.enter().append('g')
		marker_traces.exit().remove()

		markers = marker_traces.selectAll('circle').data((d) -> d.trace)
		markers.enter().append('circle')
			.datum((d) -> proj.func(d.geo[..].reverse()))
			.attr('class','point')
			.attr('cx', (d) -> d[0])
			.attr('cy', (d) -> d[1])
			.attr('r', 2)
		markers.exit().remove()

	if not opts.config.debug.traces.load_from
		ct.start(opts.config.updates.conntrack_poll)
	else
		do ->
			json = fs.readFileSync(opts.config.debug.traces.load_from)
			tracer.conn.active = JSON.parse(json)

	u.add_task_now opts.config.updates.redraw, ->
		traces = tracer.conn.active
		if opts.config.debug.traces.dump
			util.debug(JSON.stringify(traces))
		draw_traces(traces)
