-- scatter plots
-- 1D tensor
local plot = itorch.Plot(torch.randn(400):mul(100))
ifx.draw(plot)
-- 1D table
local plot = itorch.Plot({3,5,1,2,4,5,1,2,3,1,5,3,2,3,4,5,1,2,4})
ifx.draw(plot)
-- 2D tensor (x,y)
local plot = itorch.Plot(torch.randn(400,2):mul(100))
ifx.draw(plot)
-- 2D table
local plot = itorch.Plot({{3,5,1,2,4,5,1,2,3,1,5,3,2,3,4,5,1,2,4},{3,5,1,2,4,5,4,2,5,3,4,5,7,8,4,2,5,1,3}})
ifx.draw(plot)

