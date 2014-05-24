
'use strict'

util = require('util')


throw_err = (msg) ->
	throw new Error(msg or 'Unspecified Error')

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


# setInterval interface is beyond atrocious
add_task = (interval, cb) -> setInterval(cb, interval*1000)
add_task_now = (interval, cb) ->
	cb()
	return add_task(interval, cb)


deep_freeze = (layer) ->
	if layer? and typeof(layer) == 'object'
		if Array.isArray(layer)
			for v in layer
				deep_freeze(v)
		else
			for own k, v of layer
				deep_freeze(v)
		Object.freeze(layer)


module.exports.throw_err = throw_err
module.exports.assert = assert
module.exports.dump = dump
module.exports.add_task = add_task
module.exports.add_task_now = add_task_now
module.exports.deep_freeze = deep_freeze
