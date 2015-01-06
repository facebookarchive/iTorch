-- images
-- itorch.lena()
-- itorch.image({image.lena(), image.lena(), image.lena()})

-- html
-- itorch.html('<p><b>Hi there!</b> how are you</p>')
-- window_id = itorch.html('<p>This text will be replaced in 2 seconds</p>')
-- os.execute('sleep 2')
-- itorch.html('<p>magic!</p>', window_id)

local x1 = torch.randn(40):mul(100)
local y1 = torch.randn(40):mul(100)
local x2 = torch.randn(40):mul(100)
local y2 = torch.randn(40):mul(100)
local x3 = torch.randn(40):mul(200)
local y3 = torch.randn(40):mul(200)

-- scatter plots
local Plot = require 'itorch.Plot'
plot = Plot():add(x1, y1, 'red'):add(x2, y2, 'blue'):draw()
plot:add(x3,y3,'green'):redraw()
plot:title(' My plot!'):redraw()
plot:xaxis('length'):yaxis('width'):redraw()

-- print(plot:toHTML())
