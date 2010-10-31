#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import unicode_literals, print_function

from contextlib import closing
import cPickle as pickle
from time import time
import os, sys, types, socket, shutil, re

import logging
log = logging.getLogger()



_counters = dict()
def countdown(val, message=None, error=StopIteration):
	if message is None:
		c = 1
		while True:
			c += 1
			name = 'counter_{0}'.format(c)
			if name not in _counters: break
	else: name = message
	if name in _counters:
		raise NameError('Named counter is already in use')
	_counters[name] = val
	def counter():
		_counters[name] -= 1
		if _counters[name] <= 0: raise error(message or 'countdown')
	def reset(to_val=None): _counters[name] = to_val or val
	counter.tick = counter
	counter.reset = reset
	return counter

def str_cat(*argz):
	for arg in argz:
		if not isinstance(arg, (types.StringTypes, int, float)):
			try:
				for arg in str_cat(*arg): yield arg
			except TypeError:
				raise TypeError( 'Uniterable arg'
					' (type: {0!r}): {1!r}'.format(type(arg), arg) )
		else: yield unicode(arg)

filtered_results = lambda results: it.imap(
	op.itemgetter(1), it.ifilter(op.itemgetter(0), results) )


import itertools as it, operator as op, functools as ft

from twisted.internet.task import LoopingCall
from twisted.internet import reactor, defer
from twisted.python import failure


from twisted.internet import protocol

class BufferedExec(protocol.ProcessProtocol):
	_stdout = _stderr = ''
	def connectionMade(self): self.transport.closeStdin()
	def outReceived(self, data): self._stdout += data
	def errReceived(self, data): self._stderr += data
	def processEnded(self, stats): self._stdout = self._stderr = ''

class MTR(BufferedExec):
	def processEnded(self, stats):
		if stats.value.exitCode: self.transport.sentinel.errback(self._stderr)
		else:
			self.transport.sentinel.callback(map( op.itemgetter(0),
				it.groupby(line.split()[-1] for line in self._stdout.splitlines() if line[0] == 'h') ))

class SS(BufferedExec):
	def processEnded(self, stats):
		if stats.value.exitCode: self.transport.sentinel.errback(self._stderr)
		else:
			trace_dsts = list()
			for line in (line.strip().split() for line in self._stdout.splitlines()[1:]):
				dst, dst_port = line[4].rsplit(':', 1)
				dst = dst.split('::ffff:', 1)[-1]
				if ':' in dst: continue # IPv6
				trace_dsts.append((dst, int(dst_port)))
			self.transport.sentinel.callback(trace_dsts)

class XPlanet(BufferedExec):
	def processEnded(self, stats):
		if stats.value.exitCode:
			log.error( 'XPlanet exited with error'
				' (code: {0}):\n{1}'.format(stats.value.exitCode, self._stderr) )
		if optz.oneshot:
			log.debug('Exiting after first run because "oneshot" option was specified')
			reactor.stop()


def proc_skel(*argz, **kwz):
	cmd, proto = kwz.pop('command', None),\
		kwz.pop('protocol', BufferedExec)
	if not cmd: cmd = argz
	elif argz: cmd = cmd(*argz)
	result = reactor.spawnProcess( proto(),
		cmd[0], map(bytes, cmd), **kwz ).sentinel = defer.Deferred()
	return result



from struct import unpack

class UnknownLocation(Exception): pass

_cache_gc_counter = None
def cache_object(key, value=None, ext=None):
	if ext: key = '{0}__{1}'.format(ext, key)
	key, key_hr = buffer(pickle.dumps(key, -1)), key
	cur = geoip_db.cursor()
	if value is None:
		cur.execute('SELECT value, ts FROM object_cache WHERE key = ?', (key,))
		try: value, ts = next(cur)
		except StopIteration: raise KeyError
		if ts < time() - optz.cache_obsoletion: raise KeyError(ts)
		return pickle.loads(bytes(value))
	else:
		log.debug('Caching {0}'.format(key_hr))
		cur.execute( 'INSERT OR REPLACE'
			' INTO object_cache (key, value, ts) VALUES (?, ?, ?)',
			(key, buffer(pickle.dumps(value, -1)), int(time())) )
		# GC
		global _cache_gc_counter
		try: _cache_gc_counter()
		except TypeError:
			_cache_gc_counter = countdown(optz.cache_max_size / 10, 'object_cache')
		except StopIteration:
			cur.execute('SELECT COUNT(*) FROM object_cache')
			log.debug('GC - object_cache oversaturation: {0}'.format(clean_count))
			clean_count = next(cur)[0] - optz.cache_max_size
			if clean_count > 0:
				cur.execute( 'DELETE FROM object_cache'
					' ORDER BY ts LIMIT ?', (clean_count,) )
			_cache_gc_counter.reset()
		geoip_db.commit()
		return value


def _ip_to_loc(ip, cur=None):
	if cur is None: cur = geoip_db.cursor()
	cur.execute('SELECT ip_max, lat, lon FROM ip_blocks'
		' WHERE ip_min <= ? ORDER BY ip_min DESC LIMIT 1', (ip,))
	try: ip_max, lat, lon = next(cur)
	except StopIteration: raise UnknownLocation()
	if ip_max >= ip: return lat, lon
	else: raise UnknownLocation()

def ips_to_locs(ips):
	log.debug('Resolving locs for trace: {0}'.format(ips))
	locs = list()
	cur = geoip_db.cursor()
	for ip in ips:
		log.debug('Resolving IP: {0}'.format(ip))
		ip = unpack(b'!i', socket.inet_aton(ip))[0]
		locs.append(defer.execute(_ip_to_loc, ip, cur))
	return defer.DeferredList(locs, consumeErrors=True)\
		.addCallback(lambda res: cur.close() or res)\
		.addCallback(filtered_results).addCallback(list)


def _trace(ip):
	tracer = optz.trace_tool(ip)
	tracer.addCallback(ips_to_locs)
	return tracer

def trace(ip, port):
	cache = ft.partial(cache_object, ip, ext='trace')
	try: return defer.succeed((ip, port, cache()))
	except KeyError:
		ptr_lookup(ip).addErrback(lambda ign: None) # pre-cache ptr lookup result
		return optz.trace_pool.run(_trace, ip).addCallback(cache)\
			.addCallback(lambda res,ip=ip,port=port: (ip,port,res))


from twisted.names.client import lookupPointer

def _lookup_process(rec):
	try:
		rec = rec[0][0].payload
		if rec.fancybasename != 'PTR': raise IndexError
	except (IndexError, AttributeError): return None
	else: return unicode(rec.name)

_active_lookups = dict() # no gc is necessary here, I hope
def ptr_lookup(*ips):
	results = list()
	for ip in ips:
		if ip in _active_lookups: results.append(_active_lookups[ip])
		else:
			cache = ft.partial(cache_object, ip, ext='ptr')
			try: lookup = defer.succeed(cache())
			except KeyError:
				lookup = '{0}.in-addr.arpa'.format('.'.join(reversed(ip.split('.'))))
				lookup = _active_lookups[ip] = lookupPointer(lookup)
				lookup.addCallback(_lookup_process).addCallback(cache)\
					.addErrback(lambda res,ip=ip: log.debug('Failed to get PTR record for {0}'.format(ip)) or res)\
					.addBoth(lambda res,ip=ip: _active_lookups.pop(ip, True) and res)
			results.append(lookup)
	return defer.DeferredList(results, consumeErrors=True) if len(results) > 1 else results[0]





class PlanetScape(object):

	_last_traces = None

	@defer.inlineCallbacks
	def snap(self):
		traces = yield optz.ns_tool()

		traces_set = set(traces)
		if traces_set != self._last_traces:
			self._last_traces = traces_set
			traces = yield defer.DeferredList(list(it.starmap(trace, traces)))
		else: # skip repeating the same work
			self.render()
			raise StopIteration
		del traces_set

		arcs, markers, endpoints = list(), list(), list()
		markers.append(' '.join(str_cat( optz.home_lat,
			optz.home_lon, '"{0}"'.format(optz.home_label) )))
		for ip,port,geotrace in filtered_results(traces):
			if not geotrace:
				log.debug('Dropped completely unresolved trace to {0}'.format(ip))
				continue
			src = optz.home_lat, optz.home_lon
			color = '0x{0:06x}'.format(optz.svc_colors.get(port) or optz.svc_colors['default'])
			for dst in geotrace:
				arcs.append(' '.join(str_cat(src, dst, 'color={0}'.format(color)))) # spacing, thickness
				markers.append(' '.join(str_cat(dst, 'color={0}'.format(color)))) # radius, font, align
				src = dst
			markers.pop() # last marker will be replaced w/ labeled endpoint
			endpoints.append((ip, port, dst, color))
		labels = yield ptr_lookup(*it.imap(op.itemgetter(0), endpoints))
		for (res,label),(ip,port,dst,color) in it.izip(labels, endpoints):
			label = '{0} ({1})'.format(label if res else ip, optz.svc_names.get(port, port))
			markers.append(' '.join(str_cat(
				dst, '"{0}" color={1}'.format(label, color) ))) # radius, font, align
		with open(optz.instance_arcs, 'wb') as dst:
			try: shutil.copyfileobj(open(optz.arc_base, 'rb'), dst)
			except (OSError, IOError): pass
			dst.write('\n' + '\n'.join(set(arcs)) + '\n')
		with open(optz.instance_markers, 'wb') as dst:
			try: shutil.copyfileobj(open(optz.marker_base, 'rb'), dst)
			except (OSError, IOError): pass
			dst.write('\n' + '\n'.join(set(markers)) + '\n')

		self.render()

	def render(self):
		log.debug('Rendering XPlanet image')
		optz.xplanet(env=os.environ)





def build_geoip_db(from_version=0, link=None, cur=None):
	if from_version < 1: # i.e. from scratch
		## Unzip CSVs
		unzip_root = os.path.join(optz.spool_path, 'mmdb_tmp')
		log.debug('Unpacking MaxMind db (to: {0})'.format(unzip_root))
		if os.path.exists(unzip_root): shutil.rmtree(unzip_root)
		os.mkdir(unzip_root)

		from subprocess import Popen, PIPE
		Popen(['unzip', '-qq', optz.maxmind_db], cwd=unzip_root).wait()
		from glob import glob
		csvs = glob(os.path.join(unzip_root, '*', '*.csv'))
		csv_blocks, = filter(lambda name: 'Blocks' in name, csvs)
		csv_loc, = filter(lambda name: 'Location' in name, csvs)
		log.debug('Unpacked blocks: {0}, blocks-loc: {1}'.format(csv_blocks, csv_loc))

		## Read field headers
		csv_blocks, csv_loc = it.imap(open, (csv_blocks, csv_loc))
		csv_blocks.readline(), csv_loc.readline()
		csv_blocks_key, csv_loc_key = (
			csv.readline().strip().split(',') for csv in (csv_blocks, csv_loc) )
		csv_blocks_key = op.itemgetter(*it.imap(
			csv_blocks_key.index, ('startIpNum', 'endIpNum', 'locId') ))
		csv_loc_key = op.itemgetter(*it.imap(
			csv_loc_key.index, ('locId', 'latitude', 'longitude') ))

		## Unlink paths (shouldn't be adressed again)
		shutil.rmtree(unzip_root)

		## Init src/dst
		import csv
		csv_blocks, csv_loc = it.imap(ft.partial( csv.reader,
			delimiter=b',', quoting=csv.QUOTE_ALL ), (csv_blocks, csv_loc))

		log.debug('Building sqlite geoip db cache')
		if link: link.close()
		link = sqlite3.connect(geoip_db_path)
		cur = link.cursor()

		log.debug('Initializing tables')
		cur.execute( 'CREATE TABLE ip_blocks'
			' (id INTEGER PRIMARY KEY AUTOINCREMENT,'
				' ip_min INT, ip_max INT, lat FLOAT, lon FLOAT)' )
		loc_id = dict()

		# Building/querying same index in sqlite takes a lot more time,
		#  downside is that py-based one would have to fit into RAM.
		# Up to 50M RAM on my machine, but minus minute or two from the process.
		log.debug('Building loc_id index')
		for line in it.imap(csv_loc_key, csv_loc): loc_id[line[0]] = line[1:]
		log.debug('Filling lat/lon for ip ranges')
		for line in it.imap(csv_blocks_key, csv_blocks):
			loc = loc_id.get(line[2])
			if not loc:
				log.debug('Unable to find location for loc_id {0}'.format(line[2]))
				continue
			cur.execute( 'INSERT INTO ip_blocks'
				' (ip_min, ip_max, lat, lon) VALUES (?, ?, ?, ?)', line[:2] + loc )

		log.debug('Dropping overlapping intervals')
		# Overlapping intervals don't make any sense in this context,
		#  plus it's much easier to work w/ non-overlapping stuff (no need for interval trees).
		# Should be pretty fast and non-memory-hungry.
		cur.execute('SELECT id, ip_min, ip_max, lat, lon FROM ip_blocks ORDER BY ip_min')
		prev_rowid = prev_ip_max = prev_loc = None
		for rowid, ip_min, ip_max, lat, lon in cur:
			if prev_rowid is not None and prev_ip_max >= ip_min:
				cur.execute('UPDATE ip_blocks SET ip_max = ? WHERE id = ?', (ip_min-1, prev_rowid))
				if prev_ip_max > ip_max: # one interval is enclosed into another, restore the missing "tail"
					cur.execute( 'INSERT INTO ip_blocks'
						' (ip_min, ip_max, lat, lon) VALUES (?, ?, ?, ?)',
						(ip_max+1, prev_ip_max) + prev_loc )
			prev_rowid, prev_ip_max, prev_loc = rowid, ip_max, (lat, lon)

		log.debug('Adding indexes')
		cur.execute('CREATE UNIQUE INDEX ip_from ON ip_blocks (ip_min)')

		log.debug('Adding metadata table')
		cur.execute('CREATE TABLE meta (var VARCHAR(15), val FLOAT)')
		cur.execute('CREATE UNIQUE INDEX meta_var ON meta (var)')
		cur.execute("INSERT INTO meta (var, val) VALUES ('mmdb_timestamp', ?)", (time(),))

	else:
		if not link: link = sqlite3.connect(geoip_db_path) if not cur else cur.connection
		if not cur: cur = link.cursor()

	if from_version < 2:
		cur.execute('CREATE TABLE trace_cache (dst INT PRIMARY KEY, ts INT, trace BLOB)')
		cur.execute('CREATE INDEX trace_cache_ts ON trace_cache (ts)')

	if from_version < 3:
		cur.execute('DROP TABLE trace_cache')
		cur.execute('CREATE TABLE object_cache (key BLOB PRIMARY KEY, value BLOB, ts INT)')
		cur.execute('CREATE INDEX object_cache_ts ON object_cache (ts)')

	log.debug('Updating db version to {0}'.format(geoip_db_ver))
	cur.execute( 'INSERT OR REPLACE INTO meta'
		" (var, val) VALUES ('db_version', ?)", (geoip_db_ver,) )

	log.debug('Syncing database')
	link.commit()

def geoip_db_var(var, cur=None):
	if cur is None: cur = geoip_db.cursor()
	cur.execute('SELECT val FROM meta WHERE var = ?', (var,))
	try: return next(cur)[0]
	except StopIteration: raise KeyError(var)




if __name__ == '__main__':
	path_base = os.path.dirname(os.path.realpath(__file__))

	from optparse import OptionParser
	parser = OptionParser(usage='%prog [options]',
		description='Render stuff on xplanet and run some hooks')

	parser.add_option('-1', '--oneshot', action='store_true',
		help='Generate single image with a complete set of traces and exit.')
	parser.add_option('-r', '--refresh', action='store', type='int',
		default=60, help='Image refresh or re-generate interval (default: %default).')
	parser.add_option('--display', action='store', type='str',
		help='X display to use (default: auto-determine from env).')

	parser.add_option('-x', '--xplanet', action='store', default='xplanet',
		type='str', help='XPlanet binary (default: %default).')
	parser.add_option('--xplanet-args', action='store', default='',
		type='str', help='Extra arguments to pass to XPlanet binary, separated by spaces.')

	parser.add_option('-n', '--ns-tool', action='store', default='ss',
		type='str', help='Tool to get network connection list: ss, netstat, lsof (default: %default).')
	parser.add_option('--ns-tool-binary', action='store',
		type='str', help='Path to binary for selected netstat-like tool, to override defaults.')

	parser.add_option('-t', '--trace-tool', action='store', default='mtr',
		type='str', help='Traceroute tool to use: mtr, traceroute (default: %default).')
	parser.add_option('-c', '--trace-count', action='store', default=1,
		type='int', help='Number of tracer packets to send (default: %default).')
	parser.add_option('--trace-tool-binary', action='store',
		type='str', help='Path to binary for selected traceroute tool, to override defaults.')
	parser.add_option('--trace-pool-size', action='store', default=20,
		type='int', help='Max number of traceroute'
			' subprocesses to spawn in parallel (default: %default).')

	parser.add_option('--home-label', action='store', default=socket.gethostname(),
		type='str', help='Label of home-location (default: %default).')
	parser.add_option('--home-lat', action='store',
		type='float', help='Latitude of the current location (default: autodetected'
			' from external IP). Should only be specified along with --home-lon.')
	parser.add_option('--home-lon', action='store',
		type='float', help='Longitude of the current location (default: autodetected'
			' from external IP). Should only be specified along with --home-lat.')

	parser.add_option('--arc-base', action='store',
		default=os.path.join(path_base, 'arcs.txt'),
		type='str', help='File with arcs to include into rendered image (default: %default).')
	parser.add_option('--marker-base', action='store',
		default=os.path.join(path_base, 'markers.txt'),
		type='str', help='File with markers to include into rendered image (default: %default).')

	parser.add_option('-d', '--maxmind-db', action='store',
		type='str', help='Path to new MaxMind database zip (look for it here:'
			' http://www.maxmind.com/app/geolitecity). May contain globbing wildcards,'
			' (like * and ?). Must be specified at the first run.')
	parser.add_option('-s', '--spool-path', type='str', default='/var/tmp/planetscape',
		help='Path for various temporary and cache data.'
			' Dont have to be persistent, but it helps performance-wise.')

	parser.add_option('--discard-cache', action='store_true',
		help='Invalidate trace/lookup caches on start.')
	parser.add_option('--cache-obsoletion', action='store', default=3600,
		type='int', help='Time, after which cache entry considered obsolete (default: %default).')
	parser.add_option('--cache-max-size', action='store', default=50000,
		type='int', help='Max number of cached objects (traces, ns lookups) to keep (default: %default).')

	parser.add_option('--debug', action='store_true',
		help='Give extra info on whats going on.')
	optz,argz = parser.parse_args()
	if argz: parser.error('This command takes no arguments')

	logging.basicConfig( level=logging.DEBUG
		if optz.debug else logging.WARNING )

	### Check/expand paths
	os.umask(077) # no need to share cache w/ someone

	if optz.maxmind_db:
		from glob import iglob
		try: optz.maxmind_db = os.path.abspath(sorted(iglob(optz.maxmind_db))[-1]) # latest one
		except IndexError:
			log.warn('Unable to stat MaxMind GeoIP database: {0}'.format(optz.maxmind_db))
			optz.maxmind_db = None
		log.debug('Globbed MaxMind db path: {0}'.format(optz.maxmind_db))

	optz.spool_path = os.path.abspath(optz.spool_path)
	if not os.path.exists(optz.spool_path):
		log.debug('Creating spool path: {0}'.format(optz.spool_path))
		os.mkdir(optz.spool_path)
		os.chdir(optz.spool_path)


	### Instance lock
	optz.display = (optz.display or os.getenv('DISPLAY') or '').lstrip(':')
	if not optz.display:
		parser.error('Unable to determine X display for instance, try setting it explicitly')
	elif not re.match('\d+(\.\d+)?', optz.display):
		parser.error('Incorrect X display specification, expected something like ":1.0"')
	optz.instance = 'planetscape_{0}'.format(optz.display)

	import fcntl
	optz.instance_lock = open(os.path.join(optz.spool_path, '{0}.lock'.format(optz.instance)), 'w+')
	try: fcntl.flock(optz.instance_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
	except (OSError, IOError):
		parser.error('Unable to secure instance lock for display "{0}"'.format(optz.display))
	else:
		optz.instance_lock.seek(0, os.SEEK_SET)
		optz.instance_lock.truncate()
		optz.instance_lock.write(str(os.getpid()) + '\n')
		optz.instance_lock.flush()


	### GeoIP db management
	import sqlite3
	geoip_db_path = os.path.join(optz.spool_path, 'geoip.sqlite')
	geoip_db_ver = 3

	## Path/mtime/schema version checks
	if os.path.exists(geoip_db_path):
		with sqlite3.connect(geoip_db_path) as link:
			with closing(link.cursor()) as cur:
				try:
					if optz.maxmind_db:
						ts = os.stat(optz.maxmind_db).st_mtime
						ts_chk = geoip_db_var('mmdb_timestamp', cur) + 1 # for rounding quirks
						if ts_chk < ts:
							log.debug( 'MaxMind archive seem to be newer'
								' than sqlite db ({0} > {1})'.format(ts_chk, ts) )
							raise KeyError
				except (KeyError, sqlite3.OperationalError):
					log.debug('Dropping sqlite geoip db cache')
					os.unlink(geoip_db_path)
				ts_chk = geoip_db_var('db_version', cur)
				if ts_chk < geoip_db_ver: build_geoip_db(from_version=ts_chk, link=link, cur=cur)
				if optz.discard_cache:
					cur.execute('DELETE FROM object_cache')
					link.commit()

	## (Re)Build, if necessary
	if not os.path.exists(geoip_db_path):
		if not optz.maxmind_db or not os.path.exists(optz.maxmind_db):
			parser.error('No path to MaxMind GeoIP database specified'
				' and no geoip data cached, one of these issues should be addressed.')
		build_geoip_db()

	## Static configuration file
	optz.instance_conf = os.path.join(optz.spool_path, '{0}.conf'.format(optz.instance))
	for k in 'arcs', 'markers':
		path = os.path.join(optz.spool_path, k)
		if not os.path.exists(path):
			os.mkdir(path)
		setattr(optz, 'instance_{0}'.format(k), os.path.join(path, optz.instance))
	del k, path
	with open(optz.instance_conf, 'wb') as conf:
		conf.write('\n'.join([
			'[default]', 'marker_color=red', 'shade=30', 'text_color={255,0,0}', 'twilight=6',
			'[earth]', '"Earth"', 'image=earth.jpg', 'night_map=night.jpg', 'color={28, 82, 110}',
			'arc_file={0}'.format(os.path.basename(optz.instance_arcs)),
			'marker_file={0}'.format(os.path.basename(optz.instance_markers)),
			'marker_fontsize=10' ])+'\n')


	### Home location
	if not optz.home_lat and optz.home_lon and (optz.home_lat or optz.home_lon):
		parser.error('Either both latitude/longitude options should be specified or neither.')
	if not optz.home_lat or not optz.home_lon:
		log.debug('Determining home-location')
		from BeautifulSoup import BeautifulSoup
		from urllib2 import urlopen, URLError, HTTPError
		socket_to = socket.getdefaulttimeout()
		socket.setdefaulttimeout(10)
		try:
			soup = BeautifulSoup(urlopen( 'http://www.geobytes.com/'
				'IpLocator.htm?GetLocation&template=php3.txt' ).read())
			optz.home_lat = soup.find('meta', dict(name='latitude'))['content']
			optz.home_lon = soup.find('meta', dict(name='longitude'))['content']
		except (TypeError, KeyError, URLError, HTTPError):
			parser.error('Unable to determine current location via online lookup')
		finally: socket.setdefaulttimeout(socket_to)
		log.debug('Auto-detected home-location: {0} {1}'.format(optz.home_lat, optz.home_lon))

	### Netstat/trace/xplanet options
	# I don't use raw /proc/net/tcp here because it does not contain v6-mapped
	#  ipv4's, although I guess these should be available somewhere else
	try:
		optz.ns_tool = ft.partial( proc_skel,
			**dict(it.izip((b'protocol', b'command'), dict(
			ss = (SS, (optz.ns_tool_binary or '/sbin/ss', '-tn')) )[optz.ns_tool])) )
	except KeyError:
		parser.error(( 'Netstat-like command {0} protocol'
			' is not implemented (yet?)' ).format(optz.ns_tool))

	try:
		optz.trace_tool = ft.partial( proc_skel,
			**dict(it.izip((b'protocol', b'command'), dict(
			mtr = (MTR, lambda ip: ( optz.trace_tool_binary or '/usr/sbin/mtr',
				'-c{0}'.format(optz.trace_count), '-r', '--raw', '--no-dns', ip )) )[optz.trace_tool])) )
	except KeyError:
		parser.error(( 'Trace command {0} protocol'
			' is not implemented (yet?)' ).format(optz.trace_tool))
	optz.trace_pool = defer.DeferredSemaphore(optz.trace_pool_size)

	optz.xplanet_args = optz.xplanet_args.strip().split()
	if optz.oneshot: optz.xplanet_args += ['-num_times', '1']
	optz.xplanet = ft.partial( proc_skel, protocol=XPlanet,
		command=list(str_cat( optz.xplanet, '-searchdir', optz.spool_path,
			'-config', os.path.basename(optz.instance_conf),
			'-latitude', optz.home_lat, '-longitude', optz.home_lon, optz.xplanet_args )) )


	### Service colors/names
	optz.svc_colors = {
		'default': 0xffffff,
		# basic stuff
		21: 0x00ffff, # ftp
		22: 0xffff00, # ssh
		23: 0xffff00, # telnet
		53: 0x99ff00, # dns
		79: 0x0099ff, # finger
		# web
		80: 0x9900ff, # http
		443: 0x9900ff, # https
		3128: 0x9900ff, # http proxy
		# mail stuff
		25: 0xff00ff, # smtp
		110: 0xff9900, # pop3
		119: 0xff9900, # nntp
		143: 0xff9900, # imap
		993: 0xff9900, # imaps
		995: 0xff9900, # pop3s
		# IM
		5190: 0x009999, # AIM
		5222: 0x009999, # XMPP (Jabber)
		5223: 0x009999, # XMPP with old-fashioned SSL (GMail XMPP)
		# others
		873: 0x999900, # rsync
		6667: 0x990099, # irc
		7000: 0x990099 # ircs
	}

	optz.svc_names = dict()
	for port in optz.svc_colors.iterkeys():
		try: optz.svc_names[port] = socket.getservbyport(port)
		except (TypeError, socket.error): pass


	geoip_db = sqlite3.connect(geoip_db_path)

	planetscape = PlanetScape()
	if optz.oneshot: reactor.callWhenRunning(planetscape.snap)
	else:
		render_task = LoopingCall(planetscape.snap)
		render_task.start(optz.refresh)
	log.debug('Starting eventloop')
	reactor.run()
