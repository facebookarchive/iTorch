-- images
-- itorch.lena()
-- itorch.image({image.lena(), image.lena(), image.lena()})

-- html
-- itorch.html('<p><b>Hi there!</b> how are you</p>')
-- window_id = itorch.html('<p>This text will be replaced in 2 seconds</p>')
-- os.execute('sleep 2')
-- itorch.html('<p>magic!</p>', window_id)

-- scatter plots
-- 1D tensor
local Plot = require 'itorch.Plot'
plot = Plot():data(torch.randn(40):mul(100), torch.randn(40):mul(100), 'red'):data(torch.randn(40):mul(100), torch.randn(40):mul(100), 'blue')

-- itorch.html(plot:toHTML())
print(plot:toHTML())
-- plot:draw()

--[[
-- 1D table
local plot = itorch.Plot({3,5,1,2,4,5,1,2,3,1,5,3,2,3,4,5,1,2,4})
itorch.draw(plot)
-- 2D tensor (x,y)
local plot = itorch.Plot(torch.randn(400,2):mul(100))
itorch.draw(plot)
-- 2D table
local plot = itorch.Plot({{3,5,1,2,4,5,1,2,3,1,5,3,2,3,4,5,1,2,4},{3,5,1,2,4,5,4,2,5,3,4,5,7,8,4,2,5,1,3}})
itorch.draw(plot)
]]--
