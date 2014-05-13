# Uses python's sass and yaml/json modules

JS_PATH=js
JS_FILES=$(wildcard $(JS_PATH)/*.js)
CSS_PATH=css
CSS_FILES=$(wildcard $(CSS_PATH)/*.css)
HTML_PATH = .
HTML_FILES = $(wildcard $(HTML_PATH)/*.html)


all: coffee sass jade package.json

coffee: $(JS_FILES)
sass: $(CSS_FILES)
jade: $(HTML_FILES)

%.js: %.coffee
	coffee -c $<

%.css: %.scss
	PYTHONIOENCODING=utf-8 sassc -I $(dir $<) $< >$@.new
	mv $@.new $@

%.html: %.jade
	./_jade_tpl_render.py $< $@


package.json: package.yaml
	python -c 'import yaml, json; json.dump(yaml.load(open("package.yaml")), open("package.json", "wb"))'
