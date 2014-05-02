from PIL import Image, ImageMath

def color_to_alpha(image, color=None):
	image = image.convert('RGBA')

	color = map(float, color)
	img_bands = list(band.convert("F") for band in image.split())

	# Find the maximum difference rate between source and color. I had to use two
	# difference functions because ImageMath.eval only evaluates the expression
	# once.
	alpha = ImageMath.eval(
		'''float(
			max(
				max(
					max(
						diff1(red_band, cred_band),
						diff1(green_band, cgreen_band) ),
					diff1(blue_band, cblue_band) ),
				max(
					max(
						diff2(red_band, cred_band),
						diff2(green_band, cgreen_band) ),
					diff2(blue_band, cblue_band) )))''',
		diff1 = lambda source, color: (source - color) / (255.0 - color),
		diff2 = lambda source, color: (color - source) / color,
		red_band = img_bands[0], green_band = img_bands[1], blue_band = img_bands[2],
		cred_band = color[0], cgreen_band = color[1], cblue_band = color[2] )

	# Calculate the new image colors after the removal of the selected color
	new_bands = list( ImageMath.eval(
			"convert((image - color) / alpha + color, 'L')",
			image = img_bands[i], color = color[i], alpha = alpha )
		for i in xrange(3) )

	# Add the new alpha band
	new_bands.append(ImageMath.eval(
		"convert(alpha_band * alpha, 'L')",
		alpha = alpha, alpha_band = img_bands[3] ))

	return Image.merge('RGBA', new_bands)

image = color_to_alpha(Image.open('image.jpg'), (0, 0, 0, 255))
# background = Image.new('RGB', image.size, (255, 255, 255))
# background.paste(image.convert('RGB'), mask=image)
image.save('result.png')

## Ideas:
# Transparent greenish-dark (btw, check if there's a name for this color) glass Sidebar with traced contour-map
# Destinations from pcap (so it'd not be tcp-only)
# Effective dests' transfer (better than 'ssh host ss') from remote host (i.e. damnation)
# Integrate all of this in some clever way - plugins, post-render filters, clients, etc
# Log it all into blog
# Get home-ip and auto-resolve it's coords
# Drop same-location tracepoints, leaving label from the last one
# Rewrite rad_menu
