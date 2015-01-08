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

-- constructor
function Plot.new()
   local plot = {}
   for k,v in pairs(Plot) do plot[k] = v end
   return plot
end

--[[
   Bare essential functions needed:
   data (x,y,color,legend,marker)
   title
   scale
   draw
   redraw
   tohtml
]]--

function Plot:add(x,y,color,legend) -- TODO: marker
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
   legend = legend or 'unnamed'

   local N = x:nElement()
   self._data = self._data or {}
   self._data.x = self._data.x or {}
   self._data.y = self._data.y or {}
   self._data.color = self._data.color or {}
   self._data.legend = self._data.legend or {}
   local _d = {}
   _d.x = x
   _d.y = y
   _d.color = color
   if legend then 
      _d.legend = legend
   end
   table.insert(self._data.x, _d.x)
   table.insert(self._data.y, _d.y)
   table.insert(self._data.color, _d.color)
   table.insert(self._data.legend, _d.legend)
   return self
end

function Plot:title(t)
   if t then self._title = t end
   return self
end

function Plot:xaxis(t)
   if t then self._xaxis = t end
   return self
end
function Plot:yaxis(t)
   if t then self._yaxis = t end
   return self
end

function Plot:legend(bool)
   if bool then self._legend = bool end
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
   glyph.attributes.line_color = {}
   if line_color then
      glyph.attributes.line_color.value = line_color
   else
      glyph.attributes.line_color.units = 'data'
      glyph.attributes.line_color.field = 'line_color'
   end
   glyph.attributes.line_alpha = {}
   glyph.attributes.line_alpha.units = 'data'
   glyph.attributes.line_alpha.value = 1.0
   glyph.attributes.fill_color = {}
   if fill_color then
      glyph.attributes.fill_color.value = fill_color
   else
      glyph.attributes.fill_color.units = 'data'
      glyph.attributes.fill_color.field = 'fill_color'
   end
   glyph.attributes.fill_alpha = {}
   glyph.attributes.fill_alpha.units = 'data'
   glyph.attributes.fill_alpha.value = 0.2

   glyph.attributes.size = {}
   glyph.attributes.size.units = sizeunits
   glyph.attributes.size.value = sizevalue
   glyph.attributes.tags = {}
   return glyph
end

local function createDataRange1d(docid, cds, col)
   local drx = newElem('DataRange1d', docid)
   drx.attributes.sources = {}
   for i=1,#cds do
      drx.attributes.sources[i] = {}
      drx.attributes.sources[i].source = {}
      drx.attributes.sources[i].source.id = cds[i].id
      drx.attributes.sources[i].source.type = cds[i].type
      drx.attributes.sources[i].columns = {col}
   end
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

local function createLegend(docid, plotid, legends, grs)
   local l = newElem('Legend', docid)
   l.attributes.plot = {}
   l.attributes.plot.subtype = 'Figure'
   l.attributes.plot.type = 'Plot'
   l.attributes.plot.id = plotid
   l.attributes.legends = {}
   for i=1,#legends do
      l.attributes.legends[i] = {}
      l.attributes.legends[i][1] = legends[i]
      l.attributes.legends[i][2] = {{}}
      l.attributes.legends[i][2][1].type = 'GlyphRenderer'
      l.attributes.legends[i][2][1].id = grs[i].id
   end
   return l
end

local function createColumnDataSource(docid, x, y, line_color, fill_color)
   local cds = newElem('ColumnDataSource', docid)
   cds.attributes.selected = {}
   cds.attributes.cont_ranges = {}
   cds.attributes.discrete_ranges = {}
   cds.attributes.column_names = {'x', 'y'}
   if type(line_color) ~= 'string' then 
      cds.attributes.column_names[#cds.attributes.column_names + 1] = 'line_color'
   end
   if type(fill_color) ~= 'string' then 
      cds.attributes.column_names[#cds.attributes.column_names + 1] = 'fill_color'
   end
   cds.attributes.data = {}
   if torch.isTensor(x) then x = x:contiguous():storage():totable() end
   if torch.isTensor(y) then y = y:contiguous():storage():totable() end
   cds.attributes.data.x = x
   cds.attributes.data.y = y
   if type(line_color) ~= 'string' then 
      cds.attributes.data.line_color = line_color
   end
   if type(fill_color) ~= 'string' then 
      cds.attributes.data.fill_color = fill_color
   end
   return cds
end


function Plot:_toAllModels()
   self._docid = json.null -- self._docid or uuid.new()
   local all_models = {}

   local plot = newElem('Plot', self._docid)
   local renderers = {}

   local cdss = {}
   local grs = {}
   for i=1,#self._data.x do
      -- convert data to ColumnDataSource
      local cds = createColumnDataSource(self._docid, self._data.x[i], 
					 self._data.y[i], 
					 self._data.color[i], self._data.color[i])
      table.insert(all_models, cds)
      cdss[#cdss+1] = cds

      -- create Glyph (circle)
      local line_color, fill_color
      if type(self._data.color[i]) == 'string' then 
	 line_color = self._data.color[i]
	 fill_color = self._data.color[i]
      end
      local sglyph = createCircleGlyph(self._docid, line_color, 0.1, fill_color, 0.1, 'screen', 10)
      local nsglyph = createCircleGlyph(self._docid, "#1f77b4", 0.1, 
					"#1f77b4", 0.1, 'screen', 10)
      table.insert(all_models, sglyph)
      table.insert(all_models, nsglyph)

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
      renderers[#renderers+1] = gr
      table.insert(all_models, gr)
      grs[#grs+1] = gr
   end

   -- create DataRange1d for x and y
   local drx = createDataRange1d(self._docid, cdss, 'x')
   local dry = createDataRange1d(self._docid, cdss, 'y')
   table.insert(all_models, drx)
   table.insert(all_models, dry)

   -- ToolEvents
   local toolEvents = newElem('ToolEvents', self._docid)
   toolEvents.attributes.geometries = {}
   table.insert(all_models, toolEvents)

   local tf1 = newElem('BasicTickFormatter', self._docid)
   local bt1 = newElem('BasicTicker', self._docid)
   bt1.attributes.num_minor_ticks = 5
   local linearAxis1 = createLinearAxis(self._docid, plot.id, 
					self._xaxis or json.null, tf1.id, bt1.id)
   renderers[#renderers+1] = linearAxis1
   local grid1 = createGrid(self._docid, plot.id, 0, bt1.id)
   renderers[#renderers+1] = grid1
   table.insert(all_models, tf1)
   table.insert(all_models, bt1)
   table.insert(all_models, linearAxis1)
   table.insert(all_models, grid1)

   local tf2 = newElem('BasicTickFormatter', self._docid)
   local bt2 = newElem('BasicTicker', self._docid)
   bt2.attributes.num_minor_ticks = 5
   local linearAxis2 = createLinearAxis(self._docid, plot.id, 
					self._yaxis or json.null, tf2.id, bt2.id)
   renderers[#renderers+1] = linearAxis2
   local grid2 = createGrid(self._docid, plot.id, 1, bt2.id)
   renderers[#renderers+1] = grid2
   table.insert(all_models, tf2)
   table.insert(all_models, bt2)
   table.insert(all_models, linearAxis2)
   table.insert(all_models, grid2)
   
   local tools = {}
   tools[1] = createTool(self._docid, 'PanTool', plot.id, {'width', 'height'})
   tools[2] = createTool(self._docid, 'WheelZoomTool', plot.id, {'width', 'height'})
   tools[3] = createTool(self._docid, 'BoxZoomTool', plot.id, nil)
   tools[4] = createTool(self._docid, 'PreviewSaveTool', plot.id, nil)
   tools[5] = createTool(self._docid, 'ResizeTool', plot.id, nil)
   tools[6] = createTool(self._docid, 'ResetTool', plot.id, nil)
   for i=1,#tools do table.insert(all_models, tools[i]) end
   
   if self._legend then 
      local legend = createLegend(self._docid, plot.id, self._data.legend, grs)
      renderers[#renderers+1] = legend
      table.insert(all_models, legend)
   end

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

local base_template = [[
<script type="text/javascript">
$(function() {
    if (typeof (window._bokeh_onload_callbacks) === "undefined"){
	window._bokeh_onload_callbacks = [];
    }
    function load_lib(url, callback){
	window._bokeh_onload_callbacks.push(callback);
	if (window._bokeh_is_loading){
	    console.log("Bokeh: BokehJS is being loaded, scheduling callback at", new Date());
	    return null;
	}
	console.log("Bokeh: BokehJS not loaded, scheduling load and callback at", new Date());
	window._bokeh_is_loading = true;
	var s = document.createElement('script');
	s.src = url;
	s.async = true;
	s.onreadystatechange = s.onload = function(){
	    Bokeh.embed.inject_css("http://cdn.pydata.org/bokeh-0.7.0.min.css");
	    window._bokeh_onload_callbacks.forEach(function(callback){callback()});
	};
	s.onerror = function(){
	    console.warn("failed to load library " + url);
	};
	document.getElementsByTagName("head")[0].appendChild(s);
    }

    bokehjs_url = "http://cdn.pydata.org/bokeh-0.7.0.min.js"

    var elt = document.getElementById("${window_id}");
    if(elt==null) {
	console.log("Bokeh: ERROR: autoload.js configured with elementid '${window_id}'"  
		    + "but no matching script tag was found. ")
	return false;
    }
    
    if(typeof(Bokeh) !== "undefined") {
	console.log("Bokeh: BokehJS loaded, going straight to plotting");
	var modelid = "${model_id}";
	var modeltype = "Plot";
	var all_models = ${all_models};
	Bokeh.load_models(all_models);
	var model = Bokeh.Collections(modeltype).get(modelid);
	$("#${window_id}").html(''); // clear any previous plot in window_id
	var view = new model.default_view({model: model, el: "#${window_id}"});
    } else {
	load_lib(bokehjs_url, function() {
	    console.log("Bokeh: BokehJS plotting callback run at", new Date())
	    var modelid = "${model_id}";
	    var modeltype = "Plot";
	    var all_models = ${all_models};
	    Bokeh.load_models(all_models);
	    var model = Bokeh.Collections(modeltype).get(modelid);
	    $("#${window_id}").html(''); // clear any previous plot in window_id
	    var view = new model.default_view({model: model, el: "#${window_id}"});
	});
    }
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

function Plot:toTemplate(template, window_id)
   local allmodels = self:_toAllModels()
   local div_id = uuid.new()
   local window_id = window_id or div_id
   self._winid = window_id
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
   if not itorch then return self end
   local util = require 'itorch.util'
   local content = {}
   content.source = 'itorch'
   content.data = {}
   content.data['text/html'] = self:toTemplate(embed_template, window_id)
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
   return self
end

function Plot:redraw()
  self:draw(self._winid)
  return self
end



function Plot:save(filename)
   assert(filename and not paths.dirp(filename), 
	  'filename has to be provided and should not be a directory')
   local html = self:toHTML()
   local f = assert(io.open(filename, 'w'), 
		    'filename cannot be opened in write mode')
   f:write(html)
   f:close()
   return self
end

return Plot
