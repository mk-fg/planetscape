
'use strict'

u = require('./utils')

path = require('path')
fs = require('fs')
util = require('util')

yaml = require('js-yaml')


load_conf = (path_base, extension_override) ->
	config = null

	conf_merge = (conf, ext) ->
		if not conf
			conf = ext
		else
			for own k, v of ext
				if k of conf
					if Array.isArray(conf[k]) and Array.isArray(v)
						for n in v
							conf[k].push(n)
						v = conf[k]
					else if typeof(conf[k]) == 'object' and typeof(v) == 'object'
						v = conf_merge(conf[k], v)
				conf[k] = v
		return conf

	path_home = process.env[(
		if process.platform == 'win32'
		then 'USERPROFILE' else 'HOME' )]
	[path_conf_order, path_conf_bases, path_conf_abs] = [[path_base], [], []]

	while path_conf_order.length
		[path_conf, path_conf_order] = [path_conf_order[0], path_conf_order[1..]]
		if path_conf.match(/^~\//)
			u.assert(path_home, 'Unable to get user home path from env')
			path_conf = path.join(path_home, path_conf.substr(2))
		path_conf = path.resolve(path_conf)
		# console.log("Loading config: #{path_conf}")
		try path_conf = fs.realpathSync(path_conf)
		catch
			continue
		if path_conf in path_conf_abs then continue

		try
			conf = yaml.safeLoad fs.readFileSync(path_conf, encoding: 'utf-8'),
				filename: path_conf
				strict: true
				schema: yaml.CORE_SCHEMA
		catch err
			util.error("Failed to process configuration file: #{path_conf}\n  #{err}")
			process.exit(1)

		if conf.base and conf.base not in path_conf_bases
			for n in [path_conf, conf.base]
				path_conf_order.unshift(n)
			path_conf_bases.push(conf.base)
			continue

		config = conf_merge(config, conf)
		path_conf_abs.push(path_conf)

		if extension_override
			config.extension = extension_override
			extension_override = null
		if config.extension
			path_conf_order.unshift(config.extension)

		delete config.base
		delete config.extension

	return config


module.exports.load_conf = load_conf
