## This file is "not quite" node.js, but all things require()'ed here are
# see https://github.com/rogerwang/node-webkit/wiki/Differences-of-JavaScript-contexts

'use strict'

# require('nw.gui').Window.get().showDevTools()

u = require('./js/utils')
conntrace = require('./js/conntrace')
config = require('./js/config')

fs = require('fs')
util = require('util')


## Configuration
# All this stuff is static after init

opts =
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

	world: require('./data/world-110m.json')

	w: window.innerWidth * 0.9
	h: window.innerHeight * 0.9

	conf_path_base: './data/config.yaml'
	conf: null

do ->
	# Scaling factors are straight from http://bl.ocks.org/mbostock/3711652
	scale_factor = Math.min(opts.w / 960, opts.h / 500) # XXX: hard-coded values
	for k, p0 of opts.projections
		do (p0) ->
			opts.projections[k] = ->
				p = p0().rotate([0, 0, 0]).center([0, 0])
				p.scale(p.scale() * scale_factor)
					.translate(v * scale_factor for v in p.translate())
	opts.conf = config.load_conf(opts.conf_path_base, process.env['PSC_CONF'])
	u.deep_freeze(opts)


## Projection

proj =
	name: opts.conf.projection.name
	func: null
	path: null

	traces: null
	markers: null

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

# XXX: group for bg
# proj.bg = svg.append('g')
# 	.attr('id', 'bg')
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
	.datum(d3.geo.graticule())
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
	proj_names = (k for k, v of opts.projections)

	proj_tween = (proj0, proj1) ->
		(d) ->
			project = (λ, φ) ->
				λ *= 180 / Math.PI
				φ *= 180 / Math.PI
				[p0, p1] = [proj0([λ, φ]), proj1([λ, φ])]
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
		k = proj_names[this.selectedIndex]
		[proj0, proj.func] = [proj.func, opts.projections[k]()]
		proj.name = k
		svg.selectAll('path').transition()
			.duration(750)
			.attrTween('d', proj_tween(proj0, proj.func))

	menu_opts = d3.select('#projection-menu')
			.style('display', 'block')
			.on('change', update)
		.selectAll('option')
			.data(proj_names)
	menu_opts.enter().append('option')
		.text((d) -> d)
	menu_opts
		.attr('selected', (d) -> if d == proj.name then true else null)


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

	draw_helpers =
		fade_in: (selection) ->
			selection
				.style('opacity', 1e-6)
				.transition()
					.duration(opts.conf.style.traces.fade_time * 1000)
					.style('opacity', 1.0)
		fade_out: (selection) ->
			selection
				.transition()
					.duration(opts.conf.style.traces.fade_time * 1000)
					.style('opacity', 1e-6)
					.remove()

	draw_traces = (traces) ->
		data = ( {ip: ip, trace: trace}\
			for own ip, trace of traces\
			when trace.filter((d) -> d.geo).length != 0 )

		traces = proj.traces.selectAll('path.trace')
			.data(data, (d) -> d.ip)
		draw_helpers.fade_in \
			traces.enter().append('path')\
				.datum((d) ->
					type: 'MultiLineString'
					coordinates: do ->
						p0 = opts.conf.projection.source[..].reverse()
						for node in d.trace
							u.assert(node.geo, [node, d.trace])
							p1 = node.geo[..].reverse()
							[p0, line] = [p1, [p0, p1]]
							line)
				.attr('class', 'trace')
				.attr('d', d3.geo.path().projection(proj.func))
		draw_helpers.fade_out \
			traces.exit()

		marker_traces = proj.markers.selectAll('g')
			.data(data, (d) -> d.ip)
		marker_traces.enter().append('g')
		marker_traces.exit().remove()

		# XXX: marker -> expanding yellowish spot with a gradient
		markers = marker_traces.selectAll('circle').data((d) -> d.trace)
		draw_helpers.fade_in \
			markers.enter().append('circle')\
				.datum((d) -> proj.func(d.geo[..].reverse()))
				.attr('class','point')
				.attr('cx', (d) -> d[0])
				.attr('cy', (d) -> d[1])
				.attr('r', 2)
		draw_helpers.fade_out \
			markers.exit()

	if not opts.conf.debug.traces.load_from
		ct.start(opts.conf.updates.conntrack_poll)
	else
		do ->
			json = fs.readFileSync(opts.conf.debug.traces.load_from)
			tracer.conn.active = JSON.parse(json)

	do ->
		redraw =
			timer: null
			last_ts: 0
			last_change_id: null
			delay_min: 0.2 # used when updates are sparse

		tracer.on 'conn_change', ->
			if redraw.timer then return
			ts = (new Date()).getTime()
			delay = if ts - redraw.last_ts > opts.conf.updates.redraw * 1.5\
				then redraw.delay_min else opts.conf.updates.redraw

			u.schedule delay, ->
				[redraw.timer, redraw.last_ts] = [null, ts]
				change_id = tracer.conn.active_change_id
				if redraw.last_change_id != change_id
					traces = tracer.conn.active
					if opts.conf.debug.traces.dump
						util.debug(JSON.stringify(traces))
					draw_traces(traces)
					redraw.last_change_id = change_id

		draw_traces(tracer.conn.active)
