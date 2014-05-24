
'use strict'
util = require('util')
throw_err = (msg) -> throw new Error(msg or 'Unspecified Error')
assert = (condition, msg) ->
	# console.assert is kinda useless, as it doesn't actually stop the script
	if not condition
		if msg? and typeof(msg) != 'string'
			dump(msg, 'Error Data Context')
		throw_err(msg or 'Assertion failed')
dump = (data, label='unlabeled object', opts={}) ->
	if not opts.colors? then opts.colors = true
	if not opts.depth? then opts.depth = 4
	util.debug("#{label}\n" + util.inspect(data, opts))


# require('nw.gui').Window.get().showDevTools()

domain = require('domain')
events = require('events')
child_process = require('child_process')
stream = require('stream')

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

	config_path_base: './data/config.yaml'
	config_path: [] # populated with other loaded configs
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

	# Load/merge config file(s)
	[path, fs, yaml] = ['path', 'fs', 'js-yaml'].map(require)
	path_home = process.env[(
		if process.platform == 'win32'
		then 'USERPROFILE' else 'HOME' )]

	conf_merge = (conf, ext) ->
		for own k, v of ext
			if k of conf
				if Array.isArray(conf[k]) and Array.isArray(v)
					v = d3.merge([conf[k], v])
				else if typeof(conf[k]) == 'object' and typeof(v) == 'object'
					v = conf_merge(conf[k], v)
			conf[k] = v
		return conf

	path_conf = opts.config_path_base
	while path_conf
		if path_conf.match(/^~\//)
			assert(path_home, 'Unable to get user home path from env')
			path_conf = path.join(path_home, path_conf.substr(2))
		path_conf = path.resolve(path_conf)
		try path_conf = fs.realpathSync(path_conf)
		catch
			break
		if path_conf in opts.config_path then break
		opts.config_path.push(path_conf)
		try
			opts.config = yaml.safeLoad fs.readFileSync(path_conf, encoding: 'utf-8'),
				filename: path_conf
				strict: true
				schema: yaml.CORE_SCHEMA
		catch err
			util.error("Failed to process configuration file: #{path_conf}\n  #{err}")
			process.exit(1)
		if process.env['PSC_CONF']
			opts.config.extension = process.env['PSC_CONF']
			process.env['PSC_CONF'] = null
		path_conf = opts.config.extension or null
		delete opts.config.extension


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


## Geo trace and conntrack classes

class Cache extends events.EventEmitter

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


class Tracer extends events.EventEmitter

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

		mtr
			.on 'hop', (hop) ->
				link_length += 1
				last_hop = hop
				if hop.number == 1 or not hop.ip then return
				geo = geoip.lookup(hop.ip)
				if not geo
					label_buff.push(hop.ip)
					return
				label = hop_label_format(hop)
				loc = if geo.city then "#{geo.city}, #{geo.country}" else "#{geo.country}"
				hops.push
					label: "#{label} (#{loc})"
					geo: geo.ll
					link: link_length # XXX: calculate from rtt or aggregate count thru this IP/range
				[link_length, last_hop] = [0, null]

			.on 'end', ->
				if last_hop
					label = hop_label_format(last_hop)
					hops.push
						label: "#{label}"
						geo: null
						link: link_length
				self.emit('trace', ip, hops)

			.on 'error', (err) ->
				console.log('traceroute error (ip: #{ip}): #{err.message}')

			.traceroute()

	conn_add: (ip) -> @emit('conn_add', ip)
	conn_del: (ip) -> @emit('conn_del', ip)
	conn_list: (ip_list) -> @emit('conn_list', ip_list)

	constructor: ->
		super()

		@conn =
			active: {}
			pending: {}
			cache: new Cache()

		this
			.on 'trace', (ip, hops) ->
				if not @conn.pending[ip] then return
				@conn.active[ip] = hops
				@conn.cache.set(ip, hops)
				delete @conn.pending[ip]

			.on 'conn_add', (ip) ->
				if @conn.active[ip] or @conn.pending[ip] then return
				hops = @conn.cache.get(ip)
				if hops
					@emit('trace', ip, hops)
				else
					@conn.pending[ip] = true
					@geotrace(ip)

			.on 'conn_del', (ip) ->
				if not @conn.active[ip] then return
				delete @conn.active[ip]
				delete @conn.pending[ip]

			.on 'conn_list', (ip_list) ->
				active = {}
				for own ip, hops of @conn.active
					active[k] = v
				for ip in ip_list
					if active[ip]
						delete active[ip]
						continue
					@conn_add(ip)
				for own ip, hops of active
					@conn_del(ip)

	@in_domain: (d) ->
		if not d then d = domain.create()
		return d.run(-> new Tracer())


class ConntrackSS extends events.EventEmitter

	polling: true

	poll: ->
		self = this

		ss = child_process.spawn 'ss',
			['-np', '-A', 'inet', 'state', 'established'],
			stdio: ['ignore', 'pipe', process.stderr]
		[ss_out, ss_err, ss_header, ss_buff] = ['', '', true, []]

		ss.stdout

			.on 'end', ->
				self.emit('conn_list', ss_buff)

			.on 'data', (d) ->
				ss_out += d
				lines = ss_out.split('\n')
				if lines.length < 2 then return
				[ss_out, lines] = [lines[lines.length-1], lines[...-1]]
				if ss_header then lines = lines[1..]

				for line in lines
					line = line.split(/\s+/)
					assert(line.length in [5, 6])
					if line.length == 6
						[props, line] = [line[line.length-1], line[...-1]]
					[proto, q_recv, q_send, s_local, s_remote] = line
					[s_local, s_remote] = for s in [s_local, s_remote]
						[ip, port] = s.match(/^(.+):(\d+)$/)[1..2]
						[ip.replace(/^::ffff:/, ''), port]

					if props
						try
							props = users: (
								p = props.match(/^users:\((.*)\)$/)
								assert(p, "Can't match 'users:...' from: #{props}")
								re = /\("((?:[^\\"]|\\.)*)",(\d+),(\d+)\)(?:,|$)/g # "-quoted voodoo
								while m = re.exec(p[1])
									cmd: m[1], pid: parseInt(m[2]), fd: parseInt(m[3]) )
						catch e
							throw_err("Failed to parse prop-string `#{props}': #{e}")

					conn =
						proto: proto
						queues:
							recv: parseInt(q_recv)
							send: parseInt(q_send)
						local:
							addr: s_local[0]
							port: parseInt(s_local[1])
						remote:
							addr: s_remote[0]
							port: parseInt(s_remote[1])
						props: props
					ss_buff.push(conn)
					# XXX: conntrack should be used with conn_add/conn_del interface
					# XXX: add conn_del here for compat, drop conn_list special-case for polling things... maybe
					# self.emit('conn_add', conn)

			.setEncoding('utf8')

		ss
			.on 'exit', (code, sig) ->
				if not code? or code != 0 or sig
					throw_err("ss - exit with error: #{code}, #{sig}")
			.on 'error', (err) -> throw_err("ss - failed to run: #{err}")

	start: (poll_interval) ->
		assert(not @timer, @timer)
		@timer = do (s=@) -> setInterval((-> s.poll()), poll_interval * 1000)

	stop: -> @timer = @timer and clearInterval(@timer) and null

	@in_domain: (d) ->
		if not d then d = domain.create()
		return d.run(-> new ConntrackSS())


## Main loop

do ->
	tracer = Tracer.in_domain()
	ct = ConntrackSS.in_domain()

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
						assert(node.geo, [node, d.trace])
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

	# draw_traces(geo_mock)

	# ct.poll()
	# setTimeout((-> util.debug(JSON.stringify(tracer.conn.active))), 3000)
	# setTimeout((-> draw_traces(tracer.conn.active)), 3000)

	ct.start(opts.config.updates.conntrack_poll)
	setInterval(
		(-> draw_traces(tracer.conn.active)),
		opts.config.updates.redraw * 1000 )
