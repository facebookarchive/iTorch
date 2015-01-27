--[[
 *  Copyright (c) 2015, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
]]--
local Plot = require 'itorch.Plot'

-- images
itorch.image({image.lena(), image.lena(), image.lena()})

require 'nn'
m=nn.SpatialConvolution(3,32,25,25)
itorch.image(m.weight)

-- audio
itorch.audio('volkswagen.mp3')

-- video
itorch.video('small.mp4')

-- html
itorch.html('<p><b>Hi there!</b> this is arbitrary HTML</p>')
-- window_id = itorch.html('<p>This text will be replaced in 2 seconds</p>')
-- os.execute('sleep 2')
-- itorch.html('<p>magic!</p>', window_id)

x1 = torch.randn(40):mul(100)
y1 = torch.randn(40):mul(100)
x2 = torch.randn(40):mul(100)
y2 = torch.randn(40):mul(100)
x3 = torch.randn(40):mul(200)
y3 = torch.randn(40):mul(200)

-- scatter plots
plot = Plot():circle(x1, y1, 'red', 'hi'):circle(x2, y2, 'blue', 'bye'):draw()
plot:circle(x3,y3,'green', 'yolo'):redraw()
plot:title('Scatter Plot Demo'):redraw()
plot:xaxis('length'):yaxis('width'):redraw()
plot:legend(true)
plot:redraw()
-- print(plot:toHTML())
plot:save('out.html')

-- line plots
plot = Plot():line(x1, y1,'red','example'):legend(true):title('Line Plot Demo'):draw()

-- segment plots
plot = Plot():segment(x1, y1, x1+10,y1+10, 'red','demo'):title('Segment Plot Demo'):draw()

-- quiver plots
xx = torch.linspace(-3,3,10)
yy = torch.linspace(-3,3,10)
local function meshgrid(x,y)
   local xx = torch.repeatTensor(x, y:size(1),1)
   local yy = torch.repeatTensor(y:view(-1,1), 1, x:size(1))
    return xx, yy
end
Y, X = meshgrid(xx, yy)
U = -torch.pow(X,2) + Y -1
V =  X - torch.pow(Y,2) +1
plot = Plot():quiver(U,V,'red','',10):title('Quiver Plot Demo'):draw()

-- quads/rectangles
x1=torch.randn(10)
y1=torch.randn(10)
plot = Plot():quad(x1,y1,x1+1,y1+1,'red',''):draw()

-- histogram
plot = Plot():histogram(torch.randn(10000)):draw()
