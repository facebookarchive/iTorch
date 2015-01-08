from __future__ import division

import numpy as np

from bokeh.plotting import *

xx = np.linspace(-3, 3, 100)
yy = np.linspace(-3, 3, 100)

Y, X = np.meshgrid(xx, yy)
U = -1 - X**2 + Y
V = 1 + X - Y**2
speed = np.sqrt(U*U + V*V)
theta = np.arctan(V/U)

x0 = X[::2, ::2].flatten()
y0 = Y[::2, ::2].flatten()
length = speed[::2, ::2].flatten()/40
angle = theta[::2, ::2].flatten()
x1 = x0 + length * np.cos(angle)
y1 = y0 + length * np.sin(angle)

cm = np.array(["#C7E9B4", "#7FCDBB", "#41B6C4", "#1D91C0", "#225EA8", "#0C2C84"])
ix = ((length-length.min())/(length.max()-length.min())*5).astype('int')
colors = cm[ix]

output_file("vector.html", title="vector.py example")

p1 = figure()
p1.segment(x0, y0, x1, y1, color=colors, line_width=2)

show(VBox(p1))  # open a browser
