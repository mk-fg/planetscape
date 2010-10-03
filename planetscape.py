#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import unicode_literals, print_function

from time import time
import os, sys

import logging
log = logging.getLogger()



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

class MTR(BufferedExec):
	def processEnded(self, stats):
		if stats.value.exitCode: self.transport.sentinel.errback(self._stderr)
		else:
			self.transport.sentinel.callback(map( op.itemgetter(0),
				it.groupby(line.split()[-1] for line in self._stdout.splitlines() if line[0] == 'h') ))



from socket import inet_aton
from struct import unpack

class UnknownLocation(Exception): pass

def ip_to_loc(ip, cur):
	log.debug('Resolving IP: {0}'.format(ip))
	ip = unpack(b'!i', inet_aton(ip))[0]
	cur.execute( 'SELECT lat, lon FROM ip_blocks'
		' WHERE ? > ip_min AND ? < ip_max LIMIT 1', (ip, ip) )
	try: return next(iter(cur))
	except StopIteration: raise UnknownLocation()

def ips_to_locs(ips):
	log.debug('Resolving locs for trace: {0}'.format(ips))
	cur = geoip_db.cursor()
	locs = list()
	for ip in ips:
		try: locs.append(ip_to_loc(ip, cur))
		except UnknownLocation: pass
	return locs


# class PlanetScape(object):
# 	'One big TODO now ;)'

# 	def __init__(self): pass
# 	def render(self): pass






def build_geoip_db():
	from shutil import rmtree
	## Unzip CSVs
	unzip_root = os.path.join(optz.spool_path, 'mmdb_tmp')
	log.debug('Unpacking MaxMind db (to: {0})'.format(unzip_root))
	if os.path.exists(unzip_root): rmtree(unzip_root)
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
	rmtree(unzip_root)

	## Init src/dst
	import csv
	csv_blocks, csv_loc = it.imap(ft.partial( csv.reader,
		delimiter=b',', quoting=csv.QUOTE_ALL ), (csv_blocks, csv_loc))
	log.debug('Building sqlite geoip db cache')
	link = sqlite3.connect(geoip_db_path)
	cur = link.cursor()

	log.debug('Initializing tables')
	cur.execute( 'CREATE TABLE ip_blocks (ip_min INT NULL,'
		' ip_max INT NULL, loc_id VARCHAR(15) NULL, lat FLOAT, lon FLOAT)' )
	cur.execute('CREATE UNIQUE INDEX ip_loc ON ip_blocks (loc_id)')

	# This is slow, py-based loc_id -> lat/lan would
	#  probably be faster, but it'd have to fit into RAM
	log.debug('Building loc_id index')
	for line in it.imap(csv_loc_key, csv_loc):
		cur.execute('INSERT INTO ip_blocks (loc_id, lat, lon) VALUES (?, ?, ?)', line)
	log.debug('Filling lat/lon for ip ranges')
	for line in it.imap(csv_blocks_key, csv_blocks):
		cur.execute(
			'INSERT INTO ip_blocks (ip_min, ip_max, lat, lon)'
			' SELECT ? ip_min, ? ip_max, lat, lon'
			' FROM ip_blocks WHERE loc_id = ? LIMIT 1', line )
	log.debug('Dropping loc_id index entries')
	cur.execute('DELETE FROM ip_blocks WHERE ip_min IS NULL AND ip_max IS NULL')

	log.debug('Adding indexes')
	cur.execute('CREATE INDEX ip_from ON ip_blocks (ip_min)')
	cur.execute('CREATE INDEX ip_to ON ip_blocks (ip_max)')

	log.debug('Adding metadata table')
	cur.execute('CREATE TABLE meta (var VARCHAR(15), val INT)')
	cur.execute('CREATE UNIQUE INDEX meta_var ON meta (var)')
	cur.execute("INSERT INTO meta (var, val) VALUES ('timestamp', ?)", (int(time()),))

	log.debug('Syncing database')
	link.commit()
	link.close()



if __name__ == '__main__':
	from optparse import OptionParser
	parser = OptionParser(usage='%prog [options]',
		description='Render stuff on xplanet and run some hooks')

	parser.add_option('-1', '--oneshot', action='store_true',
		help='Generate single image with a complete set of traces and exit.')
	parser.add_option('-r', '--refresh', action='store', type='int',
		default=60, help='Image refresh or re-generate rate (default: %default).')

	parser.add_option('-t', '--trace-tool', action='store', default='mtr',
		type='str', help='Traceroute tool to use: mtr, traceroute (default: %default).')
	parser.add_option('-c', '--trace-count', action='store', default=1,
		type='int', help='Number of tracer packets to send (default: %default).')

	parser.add_option('-d', '--maxmind-db', action='store',
		type='str', help='Path to new MaxMind database zip (look for it here:'
			' http://www.maxmind.com/app/geolitecity). May contain globbing wildcards,'
			' (like * and ?). Must be specified at the first run.')
	parser.add_option('-s', '--spool-path', type='str', default='/var/tmp/planetscape',
		help='Path for various temporary and cache data.'
			' Dont have to be persistent, but it helps performance-wise.')

	parser.add_option('--debug', action='store_true',
		help='Give extra info on whats going on.')
	optz,argz = parser.parse_args()
	if argz: parser.error('This command takes no arguments')

	logging.basicConfig( level=logging.DEBUG
		if optz.debug else logging.WARNING )

	### Trace options
	try:
		trace_proto, trace_cmd = dict(
			mtr = (MTR, lambda ip: ( '/usr/sbin/mtr',
				'-c{0}'.format(optz.trace_count), '-r', '--raw', '--no-dns', ip )) )[optz.trace_tool]
	except KeyError:
		parser.error(( 'Trace command {0} protocol'
			' is not implemented (yet?)' ).format(optz.trace_tool))

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

	### GeoIP db management
	import sqlite3
	geoip_db_path = os.path.join(optz.spool_path, 'geoip.sqlite')

	## Path/mtime checks
	if os.path.exists(geoip_db_path) and optz.maxmind_db:
		ts = os.stat(optz.maxmind_db).st_mtime
		with sqlite3.connect(geoip_db_path) as link:
			cur = link.cursor()
			try:
				cur.execute("SELECT val FROM meta WHERE var = 'timestamp'")
				ts_chk = next(iter(cur))[0]
				if ts_chk < ts:
					log.debug( 'MaxMind archive seem to be newer'
						' than sqlite db ({0} > {1})'.format(ts_chk, ts) )
					raise StopIteration()
			except (StopIteration, sqlite3.OperationalError):
				log.debug('Dropping sqlite geoip db cache')
				os.unlink(geoip_db_path)

	## (Re)Build, if necessary
	if not os.path.exists(geoip_db_path):
		if not optz.maxmind_db or not os.path.exists(optz.maxmind_db):
			parser.error('No path to MaxMind GeoIP database specified'
				' and no geoip data cached, one of these issues should be addressed.')
		build_geoip_db()

	geoip_db = sqlite3.connect(geoip_db_path)

	trace_cmd = trace_cmd('8.8.8.8')
	tracer = reactor.spawnProcess( trace_proto(),
		trace_cmd[0], map(bytes, trace_cmd) ).sentinel = defer.Deferred()
	tracer.addCallback(ips_to_locs)
	tracer.addCallback(print)

	def fail(err):
		raise err
	tracer.addErrback(fail)

	if not optz.oneshot:
		# planescape = PlaneScape()
		# render_task = LoopingCall(optz.refresh, planescape.render)
		reactor.run()
	# else:
	# 	PlaneScape().render()
