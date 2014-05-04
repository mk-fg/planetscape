// Generated by CoffeeScript 1.7.1
(function() {
  var change, graticule, k, menu, opts, p0, path, projection, projectionTween, projections_idx, scale_factor, svg, update, v, _fn, _ref;

  opts = {
    w: window.innerWidth * 0.9,
    h: window.innerHeight * 0.9,
    world: require('./data/world-110m.json'),
    projections: {
      'Aitoff': function() {
        return d3.geo.aitoff();
      },
      'Albers': function() {
        return d3.geo.albers().scale(145).parallels([20, 50]);
      },
      'August': function() {
        return d3.geo.august().scale(60);
      },
      'Baker': function() {
        return d3.geo.baker().scale(100);
      },
      'Boggs': function() {
        return d3.geo.boggs();
      },
      'Bonne': function() {
        return d3.geo.bonne().scale(120);
      },
      'Bromley': function() {
        return d3.geo.bromley();
      },
      'Collignon': function() {
        return d3.geo.collignon().scale(93);
      },
      'Craster Parabolic': function() {
        return d3.geo.craster();
      },
      'Eckert I': function() {
        return d3.geo.eckert1().scale(165);
      },
      'Eckert II': function() {
        return d3.geo.eckert2().scale(165);
      },
      'Eckert III': function() {
        return d3.geo.eckert3().scale(180);
      },
      'Eckert IV': function() {
        return d3.geo.eckert4().scale(180);
      },
      'Eckert V': function() {
        return d3.geo.eckert5().scale(170);
      },
      'Eckert VI': function() {
        return d3.geo.eckert6().scale(170);
      },
      'Eisenlohr': function() {
        return d3.geo.eisenlohr().scale(60);
      },
      'Equirectangular (Plate Carrée)': function() {
        return d3.geo.equirectangular();
      },
      'Goode Homolosine': function() {
        return d3.geo.homolosine();
      },
      'Hammer': function() {
        return d3.geo.hammer().scale(165);
      },
      'Hill': function() {
        return d3.geo.hill();
      },
      'Kavrayskiy VII': function() {
        return d3.geo.kavrayskiy7();
      },
      'Lagrange': function() {
        return d3.geo.lagrange().scale(120);
      },
      'Lambert cylindrical equal-area': function() {
        return d3.geo.cylindricalEqualArea();
      },
      'Larrivée': function() {
        return d3.geo.larrivee().scale(95);
      },
      'Laskowski': function() {
        return d3.geo.laskowski().scale(120);
      },
      'Loximuthal': function() {
        return d3.geo.loximuthal();
      },
      'McBryde–Thomas Flat-Polar Parabolic': function() {
        return d3.geo.mtFlatPolarParabolic();
      },
      'McBryde–Thomas Flat-Polar Quartic': function() {
        return d3.geo.mtFlatPolarQuartic();
      },
      'McBryde–Thomas Flat-Polar Sinusoidal': function() {
        return d3.geo.mtFlatPolarSinusoidal();
      },
      'Miller': function() {
        return d3.geo.miller().scale(100);
      },
      'Mollweide': function() {
        return d3.geo.mollweide().scale(165);
      },
      'Natural Earth': function() {
        return d3.geo.naturalEarth();
      },
      'Nell–Hammer': function() {
        return d3.geo.nellHammer();
      },
      'Polyconic': function() {
        return d3.geo.polyconic().scale(100);
      },
      'Robinson': function() {
        return d3.geo.robinson();
      },
      'Sinu-Mollweide': function() {
        return d3.geo.sinuMollweide();
      },
      'Sinusoidal': function() {
        return d3.geo.sinusoidal();
      },
      'Wagner IV': function() {
        return d3.geo.wagner4();
      },
      'Wagner VI': function() {
        return d3.geo.wagner6();
      },
      'Wagner VII': function() {
        return d3.geo.wagner7();
      },
      'Winkel Tripel': function() {
        return d3.geo.winkel3();
      },
      'van der Grinten': function() {
        return d3.geo.vanDerGrinten().scale(75);
      },
      'van der Grinten IV': function() {
        return d3.geo.vanDerGrinten4().scale(120);
      }
    }
  };

  scale_factor = Math.min(opts.w / 960, opts.h / 500);

  _ref = opts.projections;
  _fn = function(p0) {
    return opts.projections[k] = function() {
      var p, v;
      p = p0().rotate([0, 0, 0]).center([0, 0]);
      return p.scale(p.scale() * scale_factor).translate((function() {
        var _i, _len, _ref1, _results;
        _ref1 = p.translate();
        _results = [];
        for (_i = 0, _len = _ref1.length; _i < _len; _i++) {
          v = _ref1[_i];
          _results.push(v * scale_factor);
        }
        return _results;
      })());
    };
  };
  for (k in _ref) {
    p0 = _ref[k];
    _fn(p0);
  }

  projections_idx = (function() {
    var _ref1, _results;
    _ref1 = opts.projections;
    _results = [];
    for (k in _ref1) {
      v = _ref1[k];
      _results.push(k);
    }
    return _results;
  })();

  projection = opts.projections['Aitoff']();

  path = d3.geo.path().projection(projection);

  graticule = d3.geo.graticule();

  svg = d3.select('.container').append('svg').attr('width', opts.w).attr('height', opts.h).classed('centered', true).style({
    'margin-left': '-' + (opts.w / 2) + 'px',
    'margin-top': '-' + (opts.h / 2) + 'px'
  });

  svg.append('defs').append('path').datum({
    type: 'Sphere'
  }).attr('id', 'sphere').attr('d', path);

  svg.append('use').attr('class', 'stroke').attr('xlink:href', '#sphere');

  svg.append('use').attr('class', 'fill').attr('xlink:href', '#sphere');

  svg.append('path').datum(graticule).attr('class', 'graticule').attr('d', path);

  svg.insert('path', '.graticule').datum(topojson.feature(opts.world, opts.world.objects.land)).attr('class', 'land').attr('d', path);

  change = function() {
    k = projections_idx[this.selectedIndex];
    return update({
      name: k,
      projection: opts.projections[k]()
    });
  };

  update = function(option) {
    return svg.selectAll('path').transition().duration(750).attrTween('d', projectionTween(projection, projection = option.projection));
  };

  projectionTween = function(projection0, projection1) {
    return function(d) {
      var project, t;
      project = function(λ, φ) {
        var p1, _ref1;
        λ *= 180 / Math.PI;
        φ *= 180 / Math.PI;
        _ref1 = [projection0([λ, φ]), projection1([λ, φ])], p0 = _ref1[0], p1 = _ref1[1];
        return [(1 - t) * p0[0] + t * p1[0], (1 - t) * -p0[1] + t * -p1[1]];
      };
      t = 0;
      projection = d3.geo.projection(project).scale(1).translate([opts.w / 2, opts.h / 2]);
      path = d3.geo.path().projection(projection);
      return function(_) {
        t = _;
        return path(d);
      };
    };
  };

  menu = d3.select('#projection-menu').on('change', change);

  menu.selectAll('option').data((function() {
    var _ref1, _results;
    _ref1 = opts.projections;
    _results = [];
    for (k in _ref1) {
      v = _ref1[k];
      _results.push({
        name: k,
        projection: v()
      });
    }
    return _results;
  })()).enter().append('option').text(function(d) {
    return d.name;
  });

}).call(this);
