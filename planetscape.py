#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import unicode_literals, print_function

import itertools as it, operator as op, functools as ft

import logging
log = logging.getLogger()


class PlanetScape(object):
	'One big TODO now ;)'


if __name__ == '__main__':
	from optparse import OptionParser
	parser = OptionParser(usage='%prog [options]',
		description='Render stuff on xplanet and run some hooks')
	parser.add_option('--debug', action='store_true',
		help='Give extra info on whats going on.')
	optz,argz = parser.parse_args()
	if argz: parser.error('This command takes no arguments')

	logging.basicConfig( level=logging.DEBUG
		if optz.debug else logging.WARNING )

	run_teh_loop()
