// Generated by CoffeeScript 1.7.1
(function() {
  $(document).ready(function() {
    var $map, $marker, latLngToPx, map, mapx, pos, wargames_map;
    wargames_map = require('./js/wargames_map.js');
    $map = $('#map');
    mapx = {
      w_src: 567,
      h_src: 369,
      w: $(window).width() * 0.95,
      h: $(window).height() * 0.95
    };
    $.merge(mapx, {
      w: $map.width(mapx.w).width(),
      h: $map.height(mapx.h).height()
    });
    $.merge(mapx, {
      w_src_diff: mapx.w_src / mapx.w,
      h_src_diff: mapx.h_src / mapx.h
    });
    map = Raphael($('<div id="map-canvas"/>').appendTo('#map').width(mapx.w).height(mapx.h).get(0), mapx.w, mapx.h);
    map.canvas.setAttribute('viewBox', "0 0 " + mapx.w_src + " " + mapx.h_src);
    map.path(wargames_map.vectors).attr({
      stroke: '#333'
    }).attr({
      'stroke-width': 0.7
    });
    $map.addClass('centered').css({
      'margin-top': '-' + ((mapx.h / 2) + 200) + 'px',
      'margin-left': '-' + (mapx.w / 2) + 'px'
    });
    latLngToPx = function(lat, lng) {
      var x, y, _ref;
      _ref = [parseFloat(lat) * Math.PI / 180, parseFloat(lng)], lat = _ref[0], lng = _ref[1];
      x = (mapx.w * (180 + lng) / 360) % mapx.w;
      y = Math.log(Math.tan((lat / 2) + (Math.PI / 4)));
      y = (mapx.h / 2) - (mapx.w * y / (2 * Math.PI));
      return {
        x: (x - mapx.w * 0.026) * 0.97,
        y: y + mapx.h * 0.141 + 200,
        xRaw: x,
        yRaw: y
      };
    };
    pos = latLngToPx(56.833333, 60.583333);
    return $marker = $('<div class="marker origin"><div class="meta">test</div><img src="images/marker.png"></div>').css({
      left: pos.x + 'px',
      top: pos.y + 'px'
    }).appendTo($map);
  });

}).call(this);
