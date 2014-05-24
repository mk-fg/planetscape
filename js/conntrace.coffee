
'use strict'

u = require('./utils')

domain = require('domain')
events = require('events')
child_process = require('child_process')

mtr = require('mtr')
geoip = require('geoip-lite')



class Cache extends events.EventEmitter

	constructor: (data, @lwm=300, hwm_k=1.5) ->
		super()
		[@data, @hwm] = [{}, @lwm * hwm_k]
		if data
			ts = (new Date()).getTime()
			for own k,v of data
				@set(k, v, ts)
		@on('set', @clean)

	has: (k) -> typeof(@data[k]) != 'undefined'

	get: (k, ts) ->
		v = @data[k]
		if not v? then return v
		if not ts?
			ts = (new Date()).getTime()
		v.ts = ts
		@emit('get', k, v.v, ts)
		return v.v

	set: (k, v, ts) ->
		if not ts?
			ts = (new Date()).getTime()
		@data[k] = {ts: ts, v: v}
		@emit('set', k, v, ts)

	clean: ->
		if Object.keys(@data).length <= @hwm then return
		for e in ([k, v] for own k, v of @data).sort((a, b) -> a[1].ts - b[1].ts)[..@lwm]
			delete @data[e[0]]



class Tracer extends events.EventEmitter

	mtr_cycles: 1

	geotrace: (ip) ->
		mtr = new mtr.Mtr(ip, reportCycles: @mtr_cycles)
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
					u.assert(line.length in [5, 6])
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
								u.assert(p, "Can't match 'users:...' from: #{props}")
								re = /\("((?:[^\\"]|\\.)*)",(\d+),(\d+)\)(?:,|$)/g # "-quoted voodoo
								while m = re.exec(p[1])
									cmd: m[1], pid: parseInt(m[2]), fd: parseInt(m[3]) )
						catch e
							u.throw_err("Failed to parse prop-string `#{props}': #{e}")

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
					u.throw_err("ss - exit with error: #{code}, #{sig}")
			.on 'error', (err) -> u.throw_err("ss - failed to run: #{err}")

	start: (poll_interval, now=true) ->
		u.assert(not @timer, @timer)
		@timer = do (self=@) ->
			scheduler = if now then u.add_task_now else u.add_task
			scheduler poll_interval, -> self.poll()

	stop: -> @timer = @timer and clearInterval(@timer) and null

	@in_domain: (d) ->
		if not d then d = domain.create()
		return d.run(-> new ConntrackSS())


module.exports.Tracer = Tracer
module.exports.ConntrackSS = ConntrackSS
