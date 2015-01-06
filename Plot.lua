local tablex = require 'pl.tablex'
local uuid = require 'uuid'
local json = require 'cjson'
require 'pl.text'.format_operator()
local Plot = {}

setmetatable(Plot, {
                __call = function(self,...)
                   return self.new(...)
                end
});

-- https://github.com/bokeh/Bokeh.jl/blob/master/doc/other/simplest_bokeh_plot.html
-- https://github.com/bokeh/Bokeh.jl/blob/master/doc/other/bokeh_bindings.md

-- constructor
function Plot.new()
   local plot = {}
   for k,v in pairs(Plot) do plot[k] = v end
   return plot
end

--[[
   Bare essential functions needed:
   data (x,y,color,marker,legend)
   title
   scale
   draw
   redraw
   tohtml
]]--

function Plot:data(x,y,color,legend) -- TODO: marker
   -- x and y are [a 1D tensor of N elements or a table of N elements]
   assert(x and (torch.isTensor(x) and x:dim() == 1) 
	     or (torch.type(x) == 'table'), 
	  'x needs to be a 1D tensor of N elements or a table of N elements')
   if torch.type(x) == 'table' then 
      x = torch.DoubleTensor(x)
   elseif torch.isTensor(x) then
      x = torch.DoubleTensor(x:size()):copy(x)
   end
   assert(y and (torch.isTensor(y) and y:dim() == 1) 
	     or (torch.type(y) == 'table'), 
	  'y needs to be a 1D tensor of N elements or a table of N elements')
   if torch.type(y) == 'table' then 
      y = torch.DoubleTensor(y)
   elseif torch.isTensor(y) then
      y = torch.DoubleTensor(y:size()):copy(y)
   end
   -- check if x and y are same number of elements
   assert(x:nElement() == y:nElement(), 'x and y have to have same number of elements')
   
   -- [optional] color is one of: red,blue,green or an html color string (like #FF8932). 
   -- color can either be a single value, or N values (one value per (x,y) point)
   -- if no color is specified, it is defaulted to red for all points.
   -- TODO do color argcheck
   color = color or 'red'

   local N = x:nElement()
   self._data = self._data or {}
   self._data.x = self._data.x or {}
   self._data.y = self._data.y or {}
   self._data.color = self._data.color or {}
   local _d = {}
   _d.x = x
   _d.y = y

   -- if it is a single color, replicate the color for each element
   if type(color) == 'string' then
      _d.color = {}
      for i=1,N do
	 _d.color[i] = color
      end
   else -- color is a table of N strings
      _d.color = color
   end

   if legend then 
      _d.legend = legend 
   end
   table.insert(self._data.x, _d.x)
   table.insert(self._data.y, _d.y)
   table.insert(self._data.color, _d.color)
   return self
end

function Plot:title(t)
   if t then self._title = t end
   return self
end

-- merges multiple tables into one
local function combineTable(x)
   local y = {}
   for i=1,#x do
      local xx = x[i]
      local limit
      if torch.isTensor(xx) then
	 limit = xx:size(1)
      else
	 limit = #xx
      end
      for j=1,limit do
	 table.insert(y, xx[j])
      end
   end
   return y
end

local function newElem(name, docid)
   local c = {}
   c.id = uuid.new()
   c.type = name
   c.attributes = {}
   c.attributes.id = c.id
   c.attributes.doc = docid
   c.attributes.tags = {}
   return c
end

local function createCircleGlyph(docid, line_color, line_alpha, fill_color, fill_alpha, sizeunits, sizevalue)
   local glyph = newElem('Circle', docid)
   glyph.attributes.x = {}
   glyph.attributes.x.units = 'data'
   glyph.attributes.x.field = 'x'
   glyph.attributes.y = {}
   glyph.attributes.y.units = 'data'
   glyph.attributes.y.field = 'y'
   if line_color then
      glyph.attributes.line_color = {}
      glyph.attributes.line_color.value = line_color
   else
      glyph.attributes.line_color = {}
      glyph.attributes.line_color.units = 'data'
      glyph.attributes.line_color.field = 'line_color'
   end
   glyph.attributes.line_alpha = {}
   glyph.attributes.line_alpha.units = 'data'
   glyph.attributes.line_alpha.value = 1.0
   if fill_color then
      glyph.attributes.fill_color = {}
      glyph.attributes.fill_color.value = fill_color
   else
      glyph.attributes.fill_color = {}
      glyph.attributes.fill_color.units = 'data'
      glyph.attributes.fill_color.field = 'fill_color'
   end
   glyph.attributes.fill_alpha = {}
   glyph.attributes.fill_alpha.units = 'data'
   glyph.attributes.fill_alpha.value = 1.0

   glyph.attributes.size = {}
   glyph.attributes.size.units = sizeunits
   glyph.attributes.size.value = sizevalue
   glyph.attributes.tags = {}
   return glyph
end

local function createDataRange1d(docid, cds, col)
   local drx = newElem('DataRange1d', docid)
   drx.attributes.sources = {{}}
   drx.attributes.sources[1].source = {}
   drx.attributes.sources[1].source.id = cds.id
   drx.attributes.sources[1].source.type = cds.type
   drx.attributes.sources[1].columns = {col}
   return drx
end

local function createLinearAxis(docid, plotid, axis_label, tfid, btid)
   local linearAxis1 = newElem('LinearAxis', docid)
   linearAxis1.attributes.plot = {}
   linearAxis1.attributes.plot.subtype = 'Figure'
   linearAxis1.attributes.plot.type = 'Plot'
   linearAxis1.attributes.plot.id = plotid
   linearAxis1.attributes.axis_label = axis_label
   linearAxis1.attributes.formatter = {}
   linearAxis1.attributes.formatter.type = 'BasicTickFormatter'
   linearAxis1.attributes.formatter.id = tfid
   linearAxis1.attributes.ticker = {}
   linearAxis1.attributes.ticker.type = 'BasicTicker'
   linearAxis1.attributes.ticker.id = btid
   return linearAxis1
end

local function createGrid(docid, plotid, dimension, btid)
   local grid1 = newElem('Grid', docid)
   grid1.attributes.plot = {}
   grid1.attributes.plot.subtype = 'Figure'
   grid1.attributes.plot.type = 'Plot'
   grid1.attributes.plot.id = plotid
   grid1.attributes.dimension = dimension
   grid1.attributes.ticker = {}
   grid1.attributes.ticker.type = 'BasicTicker'
   grid1.attributes.ticker.id = btid
   return grid1
end

local function createTool(docid, name, plotid, dimensions)
   local t = newElem(name, docid)
   t.attributes.plot = {}
   t.attributes.plot.subtype = 'Figure'
   t.attributes.plot.type = 'Plot'
   t.attributes.plot.id = plotid
   if dimensions then t.attributes.dimensions = dimensions end
   return t
end

function Plot:_toAllModels()
   self._docid = json.null -- self._docid or uuid.new()
   local all_models = {}

   -- convert data to ColumnDataSource
   local cds = newElem('ColumnDataSource', self._docid)
   cds.attributes.selected = {}
   cds.attributes.cont_ranges = {}
   cds.attributes.discrete_ranges = {}
   cds.attributes.column_names = {'fill_color', 'line_color', 'x', 'y'}
   cds.attributes.data = {}
   cds.attributes.data.x = combineTable(self._data.x)
   cds.attributes.data.y = combineTable(self._data.y)
   cds.attributes.data.line_color = combineTable(self._data.color)
   cds.attributes.data.fill_color = combineTable(self._data.color)
   table.insert(all_models, cds)

   -- create DataRange1d for x and y
   local drx = createDataRange1d(self._docid, cds, 'x')
   local dry = createDataRange1d(self._docid, cds, 'y')
   table.insert(all_models, drx)
   table.insert(all_models, dry)

   -- create Glyph (circle)
   local sglyph = createCircleGlyph(self._docid, nil, 0.1, nil, 0.1, 'screen', 10)
   local nsglyph = createCircleGlyph(self._docid, "#1f77b4", 0.1, 
				     "#1f77b4", 0.1, 'screen', 10)
   table.insert(all_models, sglyph)
   table.insert(all_models, nsglyph)

   -- ToolEvents
   local toolEvents = newElem('ToolEvents', self._docid)
   toolEvents.attributes.geometries = {}
   table.insert(all_models, toolEvents)

   local plot = newElem('Plot', self._docid)
   local renderers = {}

   local tf1 = newElem('BasicTickFormatter', self._docid)
   local bt1 = newElem('BasicTicker', self._docid)
   bt1.attributes.num_minor_ticks = 5
   local linearAxis1 = createLinearAxis(self._docid, plot.id, 
					'Untitled x-axis', tf1.id, bt1.id)
   renderers[1] = linearAxis1
   local grid1 = createGrid(self._docid, plot.id, 0, bt1.id)
   renderers[2] = grid1
   table.insert(all_models, tf1)
   table.insert(all_models, bt1)
   table.insert(all_models, linearAxis1)
   table.insert(all_models, grid1)

   local tf2 = newElem('BasicTickFormatter', self._docid)
   local bt2 = newElem('BasicTicker', self._docid)
   bt2.attributes.num_minor_ticks = 5
   local linearAxis2 = createLinearAxis(self._docid, plot.id, 
					'Untitled y-axis', tf2.id, bt2.id)
   renderers[3] = linearAxis2
   local grid2 = createGrid(self._docid, plot.id, 1, bt2.id)
   renderers[4] = grid2
   table.insert(all_models, tf2)
   table.insert(all_models, bt2)
   table.insert(all_models, linearAxis2)
   table.insert(all_models, grid2)

   -- PanTool
   local tools = {}
   tools[1] = createTool(self._docid, 'PanTool', plot.id, {'width', 'height'})
   tools[2] = createTool(self._docid, 'WheelZoomTool', plot.id, {'width', 'height'})
   tools[3] = createTool(self._docid, 'BoxZoomTool', plot.id, nil)
   tools[4] = createTool(self._docid, 'PreviewSaveTool', plot.id, nil)
   tools[5] = createTool(self._docid, 'ResizeTool', plot.id, nil)
   tools[6] = createTool(self._docid, 'ResetTool', plot.id, nil)
   for i=1,#tools do table.insert(all_models, tools[i]) end

   -- GlyphRenderer 
   local gr = newElem('GlyphRenderer', self._docid)
   gr.attributes.nonselection_glyph = {}
   gr.attributes.nonselection_glyph.type = 'Circle'
   gr.attributes.nonselection_glyph.id = nsglyph.id
   gr.attributes.data_source = {}
   gr.attributes.data_source.type = 'ColumnDataSource'
   gr.attributes.data_source.id = cds.id
   gr.attributes.name = json.null
   gr.attributes.server_data_source = json.null
   gr.attributes.selection_glyph = json.null
   gr.attributes.glyph = {}
   gr.attributes.glyph.type = 'Circle'
   gr.attributes.glyph.id = sglyph.id
   renderers[5] = gr
   table.insert(all_models, gr)

   -- Plot
   plot.attributes.x_range = {}
   plot.attributes.x_range.type = 'DataRange1d'
   plot.attributes.x_range.id = drx.id
   plot.attributes.extra_x_ranges = {}
   plot.attributes.y_range = {}
   plot.attributes.y_range.type = 'DataRange1d'
   plot.attributes.y_range.id = dry.id
   plot.attributes.extra_y_ranges = {}
   plot.attributes.right = {}
   plot.attributes.above = {}
   plot.attributes.below = {{}}
   plot.attributes.below[1].type = 'LinearAxis'
   plot.attributes.below[1].id = linearAxis1.id
   plot.attributes.left = {{}}
   plot.attributes.left[1].type = 'LinearAxis'
   plot.attributes.left[1].id = linearAxis2.id
   plot.attributes.title = self._title or 'Untitled Plot'
   plot.attributes.tools = {}
   for i=1,#tools do
      plot.attributes.tools[i] = {}
      plot.attributes.tools[i].type = tools[i].type
      plot.attributes.tools[i].id = tools[i].id
   end
   plot.attributes.renderers = {}
   for i=1,#renderers do
      plot.attributes.renderers[i] = {}
      plot.attributes.renderers[i].type = renderers[i].type
      plot.attributes.renderers[i].id = renderers[i].id
   end
   plot.attributes.tool_events = {}
   plot.attributes.tool_events.type = 'ToolEvents'
   plot.attributes.tool_events.id = toolEvents.id
   table.insert(all_models, plot)

   return all_models
end

local function encodeAllModels(m)
   local s = json.encode(m)
   local w = {'selected', 'above', 'geometries', 'right', 'tags'}
   for i=1,#w do
      local before = '"' .. w[i] .. '":{}'
      local after = '"' .. w[i] .. '":[]'
      s=string.gsub(s, before, after)
   end
   return s
end

local base_template = 
[[
<script type="text/javascript">
  $(function() {
    var modelid = "${model_id}";
    var modeltype = "Plot";
    var all_models = ${all_models};
    Bokeh.load_models(all_models);
    var model = Bokeh.Collections(modeltype).get(modelid);
    $("#${window_id}").html(''); // clear any previous plot in window_id
    var view = new model.default_view({model: model, el: "#${window_id}"});
  });
</script>
]]

local embed_template = base_template .. [[
<div class="plotdiv" id="${div_id}"></div>
]]

local html_template = [[
<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="utf-8">
        <link rel="stylesheet" href="http://cdn.pydata.org/bokeh-0.7.0.min.css" type="text/css" />
        <script type="text/javascript" src="http://cdn.pydata.org/bokeh-0.7.0.js"></script>
]] .. base_template .. [[
    </head>
    <body>
        <div class="plotdiv" id="${div_id}"></div>
    </body>
</html>
]]

--[[
local bokehcss, bokehjs
do
   local fname = 'bokeh-0.7.0.min'
   local cssf = assert(io.open(paths.concat(paths.dirname(paths.thisfile()), fname .. '.css')))
   bokehcss = cssf:read('*all')
   cssf:close()
   local jsf = assert(io.open(paths.concat(paths.dirname(paths.thisfile()), fname .. '.js')))
   bokehjs = jsf:read('*all')
   jsf:close()
end
]]--

function Plot:toTemplate(template)
   local allmodels = self:_toAllModels()
   local div_id = uuid.new()
   local window_id = div_id
   -- find model_id
   local model_id
   for k,v in ipairs(allmodels) do
      if v.type == 'Plot' then
         model_id = v.id
      end
   end
   assert(model_id, "Could not find Plot element in input allmodels");
   local html = template % {
      window_id = window_id,
      div_id = div_id,
      all_models = encodeAllModels(allmodels),
      model_id = model_id
   };
   return html
end

function Plot:toHTML()
   return self:toTemplate(html_template)
end

function Plot:draw(window_id)
   local util = require 'itorch.util'
   local div_id = uuid.new()
   window_id = window_id or div_id
   self._winid = window_id
   local content = {}
   content.source = 'itorch'
   content.data = {}
   content.data['text/html'] = self:toTemplate(embed_template)
   content.metadata = {}
   local header = tablex.deepcopy(itorch._msg.header)
   header.msg_id = uuid.new()
   header.msg_type = 'display_data'

   -- send displayData
   local m = {
      uuid = itorch._msg.uuid,
      content = content,
      parent_header = itorch._msg.header,
      header = header
   }
   util.ipyEncodeAndSend(itorch._iopub, m)
end

function Plot:redraw()
  self:draw(self._winid)
end



function Plot:save(filename)
end

return Plot
