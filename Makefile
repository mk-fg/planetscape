# Uses python's sass and yaml/json modules

JS_PATH=static/js
JS_FILES=$(wildcard $(JS_PATH)/*.js)

CSS_PATH=static/css
CSS_FILES=$(wildcard $(CSS_PATH)/*.css)

all: coffee sass package.json

coffee: $(JS_FILES)
sass: $(CSS_FILES)

%.js: %.coffee
	coffee -c $<

%.css: %.scss
	sassc -I $(dir $<) $< >$@.new
	mv $@.new $@

package.json: package.yaml
	python -c 'import yaml, json; json.dump(yaml.load(open("package.yaml")), open("package.json", "wb"))'
