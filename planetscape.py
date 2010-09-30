#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import unicode_literals, print_function

import logging
log = logging.getLogger()



import itertools as it, operator as op, functools as ft

from twisted.internet.task import LoopingCall
from twisted.internet import reactor, defer
from twisted.python import log, failure


from twisted.internet import protocol

## TODO: check out if scapy (or something else?) does a better job
class Traceroute(protocol.ProcessProtocol):
	def connectionMade(self): self.transport.closeStdin()
	def processEnded(self, stats):
		if stats.value.exitCode: self.transport.sentinel.errback(False)
		else: self.transport.sentinel.callback(True)


class PlanetScape(object):
	'One big TODO now ;)'

	def __init__(self): pass
	def render(self): pass



if __name__ == '__main__':
	from optparse import OptionParser
	parser = OptionParser(usage='%prog [options]',
		description='Render stuff on xplanet and run some hooks')

	parser.add_option('-1', '--oneshot', action='store_true',
		help='Generate single image with a complete set of traces and exit.')
	parser.add_option('-r', '--refresh', action='store', type='int',
		default=60, help='Image refresh or re-generate rate. Default: %default.')

	parser.add_option('--debug', action='store_true',
		help='Give extra info on whats going on.')
	optz,argz = parser.parse_args()
	if argz: parser.error('This command takes no arguments')

	logging.basicConfig( level=logging.DEBUG
		if optz.debug else logging.WARNING )

	if not optz.oneshot:
		planescape = PlaneScape()
		render_task = LoopingCall(optz.refresh, planescape.render)
		reactor.run()
	else:
		PlaneScape().render()
