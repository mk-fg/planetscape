# require('nw.gui').Window.get().showDevTools()

# util = require('util')
EventEmitter = require('events').EventEmitter
Mtr = require('mtr').Mtr
geoip = require('geoip-lite')


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

	defaults:
		# XXX: configurable somehow (cli?)
		source: [56.833333, 60.583333]
		projection: 'Equirectangular (Plate Carrée)'


# Scaling factors are straight from http://bl.ocks.org/mbostock/3711652
scale_factor = Math.min(opts.w / 960, opts.h / 500)
for k, p0 of opts.projections
	do (p0) ->
		opts.projections[k] = ->
			p = p0().rotate([0, 0, 0]).center([0, 0])
			p.scale(p.scale() * scale_factor)
				.translate(v * scale_factor for v in p.translate())
projections_idx = (k for k, v of opts.projections)


projection_name = opts.defaults.projection
projection = opts.projections[projection_name]()
	.translate([opts.w / 2, opts.h / 2])
path = d3.geo.path().projection(projection)
graticule = d3.geo.graticule()

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


class Cache extends EventEmitter

	constructor: (data, @lwm=300, hwm_k=1.5) ->
		super()
		[@data, @hwm] = [d3.map(), @lwm * hwm_k]
		if data
			ts = (new Date()).getTime()
			for own k,v of data
				@set(k, v, ts)
		@on('set', @clean)

	has: (k) -> @data.has(k)

	get: (k, ts) ->
		v = @data.get(k)
		if not v? then return v
		if not ts?
			ts = (new Date()).getTime()
		v.ts = ts
		@emit('get', k, v.v, ts)
		return v.v

	set: (k, v, ts) ->
		if not ts?
			ts = (new Date()).getTime()
		@data.set(ts: ts, v: v)
		@emit('set', k, v, ts)

	clean: ->
		if @data.size() <= @hwm then return
		for e in @data.entries().sort((a, b) -> a.ts - b.ts)[..@lwm]
			@data.remove(e.key)


class Tracer extends EventEmitter

	mtr_cycles: 1

	geotrace: (ip) ->
		mtr = new Mtr(ip, reportCycles: @mtr_cycles)
		[self, hops] = [this, []]
		[link_length, last_hop, label_buff] = [0, null, []]

		hop_label_format = (hop) ->
			label = hop.ip # XXX: maybe use hostnames here
			if label_buff.length
				label_buff.push(label)
				label = label_buff.join(' -> ')
				label_buff = []
			return label

		mtr.on 'hop', (hop) ->
			link_length += 1
			last_hop = hop
			if hop.number == 1 or not hop.ip then return
			geo = geoip.lookup(hop.ip)
			if not geo
				label_buff.push(label_addr)
				return
			label = hop_label_format(hop)
			loc = if geo.city then "#{geo.city}, #{geo.country}" else "#{geo.country}"
			hops.push
				label: "#{label} (#{loc})"
				geo: geo.ll
				link: link_length # XXX: calculate from rtt or aggregate count thru this IP/range
			[link_length, last_hop] = [0, null]

		mtr.on 'end', ->
			if last_hop
				label = hop_label_format(last_hop)
				hops.push
					label: "#{label}"
					geo: null
					link: link_length
			self.emit('trace', ip, hops)

		mtr.on 'error', (err) ->
			console.log('traceroute error (ip: #{ip}): #{err.message}')

		mtr.traceroute()

	conn_add: (ip) -> @emit('conn_add', ip)
	conn_del: (ip) -> @emit('conn_del', ip)
	conn_list: (ip_list) -> @emit('conn_list', ip_list)

	constructor: ->
		super()

		@conn =
			active: {}
			pending: {}
			cache: new Cache()

		@on 'trace', (ip, hops) ->
			if not @conn.pending[ip] then return
			@conn.active[ip] = hops
			@conn.cache.set(ip, hops)
			delete @conn.pending[ip]

		@on 'conn_add', (ip) ->
			if @conn.active[ip] then return
			hops = @conn.cache.get(ip)
			if hops
				@emit('trace', ip, hops)
			else
				@conn.pending[ip] = true
				@geotrace(ip)

		@on 'conn_del', (ip) ->
			if not @conn.active[ip] then return
			delete @conn.active[ip]
			delete @conn.pending[ip]

		@on 'conn_list', (ip_list) ->
			active = @conn.active[..]
			for ip in ip_list
				if active[ip]
					delete active.indexOf(ip)
					continue
				@conn_add('conn_add', ip)
			for ip in active
				@conn_del(ip)


# o = projection(opts.defaults.source.reverse())
# svg.append('svg:circle')
# 	.attr('class','point')
# 	.attr('cx', o[0])
# 	.attr('cy', o[1])
# 	.attr('r', 4)
# 	.attr('title', 'source')

# tracer = new Tracer()

# tracer.on 'trace', (ip, hops) ->
# 	console.log('trace')
# 	for hop in hops
# 		console.log(hop)

# tracer.conn_add('8.8.8.8')


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
		path = d3.geo.path().projection(projection)
		(_) ->
			t = _
			path(d)

update = ->
	k = projections_idx[this.selectedIndex]
	[projection0, projection] = [projection, opts.projections[k]()]
	projection_name = k
	svg.selectAll('path').transition()
		.duration(750)
		.attrTween('d', projectionTween(projection0, projection))

menu_opts = d3.select('#projection-menu')
		.style('display', 'block')
		.on('change', update)
	.selectAll('option')
		.data({name: k, projection: v()} for k, v of opts.projections)

menu_opts.enter().append('option')
		.text((d) -> d.name)

menu_opts
		.attr('selected', (d) -> if d.name == projection_name then true else null)
