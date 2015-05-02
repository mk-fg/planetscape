# Uses python's sass, jade and yaml/json modules

all: package.json coffee sass jade node_modules/.keep


JS_PATH=js
JS_FILES=$(wildcard $(JS_PATH)/*.js)
CSS_PATH=css
CSS_FILES=$(wildcard $(CSS_PATH)/*.css)
HTML_PATH = .
HTML_FILES = $(wildcard $(HTML_PATH)/*.html)

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


node_modules/.keep: package.yaml
	python -c "import yaml; print '\n'.join(yaml.safe_load(open('$<'))['dependencies'].keys())" |\
		while read n; do [ -d "node_modules/$$n" ] || npm install "$$n"; done
	touch node_modules/.keep

package.json: package.yaml
	python -c "import yaml, json; json.dump(yaml.safe_load(open('$<')), open('$@', 'wb'))"


.PHONY: coffee sass jade
