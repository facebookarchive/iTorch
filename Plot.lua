local itorch = require 'itorch.env'
local ifx = itorch.ifx
local tablex = require 'pl.tablex'

local Plot = {
   name = 'itorch.Plot'
}

setmetatable(Plot, {
		__call = function(self,...)
		   return self.new(...)
		end
});

-- constructor
function Plot.new(data, glyph, options)
   local plot = {}
   for k,v in pairs(Plot) do plot[k] = v end

   plot:data(data);
   if not glyph then
      -- defaults
      glyph = {
	 type = 'circle',
	 x = 'x',
	 y = 'y',
	 radius = 0.3,
	 radius_units = 'data',
	 fill_color = 'red',
	 fill_alpha = 0.6,
	 line_color = nil
      }
   end
   plot:glyph(glyph)

   if not options then
      options = {
	 xaxes = "below",
	 yaxes = "left",
	 tools = true,
	 legend =  false
      }
   end
   plot:options(options)
   
   -- set range automatically to [min, max]
   if not (plot:options().xrange and plot:options().yrange) then
      plot:autoRange()
   end
   
   return plot
end

do
   local help = [[Input expected is a table of two elements (representing x and y) 
or a 2D tensor with Nx2 elements (x and y). 
Examples: x = Plot.new()
x:data({{1,3,2,5},{3,9,3,2}})
x:data({torch.randn(10), torch.randn(10)})
x:data(torch.randn(10,2))
]]
   -- set and/or get data
   function Plot:data(d)
      if not d then return self._data end
      
      -- TODO: make y optional      
      if torch.type(d) == 'table' then      -- d is table
	 -- table has two integer elements which are 1D-tensors or table of numbers
	 if d[1] and d[2] then
	    if torch.isTensor(d[1]) then d[1] = d[1]:clone():storage():totable() end
	    if torch.isTensor(d[2]) then d[2] = d[2]:clone():storage():totable() end
	    assert(#d[1] == #d[2], 'x and y vectors are not the same size: ' .. #d[1] .. ',' .. #d[2])
	    self._data = { x = d[1], y = d[2] }
	 else
	    error(help)
	 end
      elseif torch.isTensor(d) then	 -- d is tensor
	 assert(d:dim() == 2 and d:size(2) == 2, help) -- 2D tensor with 2nd dimension of size 2
	 local x = d[{{},{1}}]:clone():storage():totable()
	 local y = d[{{},{2}}]:clone():storage():totable()
	 self._data = {x = x, y = y}
      else
	 error(help)
      end
      return self._data
   end
end

-- set the type of plot: (scatter/bar/...)
function Plot:type()
end

function Plot:glyph(g)
   if g then self._glyph = g end
   return self._glyph
end

function Plot:options(o)
   if o then self._options = o end
   return self._options
end

function Plot:title(t)
   if t and type(t) == string then
      self.title = t
   end
   return t
end

function Plot:clone()
   return tablex.deepcopy(self)
end

function Plot:draw()
end

function Plot:redraw()
end

function Plot:toHTML()
end

function Plot:xrange(min, max)
   if min and max then
      self._options.xrange = {min, max}
   end
   return self._options.xrange
end

function Plot:yrange(min, max)
   if min and max then
      self._options.yrange = {min, max}
   end
   return self._options.yrange
end

-- set range automatically to [min, max]
function Plot:autoRange()
   local xt = torch.Tensor(self._data.x)
   local xrange = {xt:min(), xt:max()}

   local yt = torch.Tensor(self._data.y)
   local yrange = {yt:min(), yt:max()}
   self._options.xrange = xrange
   self._options.yrange = yrange
end

return Plot
