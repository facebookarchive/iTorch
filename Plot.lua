--[[
   *  Copyright (c) 2015, Facebook, Inc.
   *  All rights reserved.
   *
   *  This source code is licensed under the BSD-style license found in the
   *  LICENSE file in the root directory of this source tree. An additional grant
   *  of patent rights can be found in the PATENTS file in the same directory.
   *
]]--
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

local function tensorValidate(x)
   assert(x and (torch.isTensor(x) and x:dim() == 1)
             or (torch.type(x) == 'table'),
          'input needs to be a 1D tensor/table of N elements')
   if torch.type(x) == 'table' then
      x = torch.DoubleTensor(x)
   elseif torch.isTensor(x) then
      x = torch.DoubleTensor(x:size()):copy(x)
   end
   return x
end

function Plot:_simpleGlyph(x,y,color,legend, name) -- TODO: marker
   -- x and y are [a 1D tensor of N elements or a table of N elements]
   x = tensorValidate(x)
   y = tensorValidate(y)
   -- check if x and y are same number of elements
   assert(x:nElement() == y:nElement(),
          'x and y have to have same number of elements')

   --[[ [optional] color is one of:
      red,blue,green or an html color string (like #FF8932)
      color can either be a single value,
      or N values (one value per (x,y) point)
      if no color is specified, it is defaulted to red for all points.
      TODO do color argcheck
   ]]--
   color = color or 'red'
   legend = legend or 'unnamed'

   self._data = self._data or {}
   local _d = {}
   _d.type = name
   _d.x = x
   _d.y = y
   _d.fill_color = color
   _d.line_color = color
   if legend then
      _d.legend = legend
   end
   table.insert(self._data, _d)
   return self
end

function Plot:circle(x,y,color,legend)
   return self:_simpleGlyph(x,y,color,legend,'Circle')
end

function Plot:line(x,y,color,legend)
   return self:_simpleGlyph(x,y,color,legend,'Line')
end

function Plot:triangle(x,y,color,legend)
   return self:_simpleGlyph(x,y,color,legend,'Triangle')
end

function Plot:segment(x0,y0,x1,y1,color,legend)
   -- x and y are [a 1D tensor of N elements or a table of N elements]
   x0 = tensorValidate(x0)
   x1 = tensorValidate(x1)
   y0 = tensorValidate(y0)
   y1 = tensorValidate(y1)
   -- check if x and y are same number of elements
   assert(x0:nElement() == y0:nElement(),
          'x0 and y0 should have same number of elements')
   assert(x0:nElement() == x1:nElement(),
          'x0 and x1 should have same number of elements')
   assert(x0:nElement() == y1:nElement(),
          'x0 and y1 should have same number of elements')

   color = color or 'red'
   legend = legend or 'unnamed'

   self._data = self._data or {}
   local _d = {}
   _d.type = 'Segment'
   _d.x0 = x0
   _d.y0 = y0
   _d.x1 = x1
   _d.y1 = y1
   _d.fill_color = color
   _d.line_color = color
   if legend then
      _d.legend = legend
   end
   table.insert(self._data, _d)
   return self
end

function Plot:quiver(U,V,color,legend,scaling)
   assert(U:dim() == 2 and V:dim() == 2
             and U:size(1) == V:size(1) and U:size(2) == V:size(2),
          'U and V should be 2D and of same size')
   local xx = torch.linspace(1,U:size(1), U:size(1)):typeAs(U)
   local yy = torch.linspace(1,U:size(2), U:size(2)):typeAs(V)
   local function meshgrid(x,y)
      local xx = torch.repeatTensor(x, y:size(1),1)
      local yy = torch.repeatTensor(y:view(-1,1), 1, x:size(1))
      return xx, yy
   end
   local Y, X = meshgrid(xx, yy)
   X = X:view(-1)
   Y = Y:view(-1)
   U = U:view(-1)
   V = V:view(-1)
   scaling = scaling or 40
   U = U / scaling
   V = V / scaling
   local x0 = X
   local y0 = Y
   local x1 = X + U
   local y1 = Y + V
   self:segment(x0, y0, x1,y1, color,legend)
   ------------------------------------------------------------------
   -- calculate and plot arrow-head
   local ll = (x1 - x0)
   local ll2 = (y1 - y0)
   local len = torch.sqrt(torch.cmul(ll,ll) + torch.cmul(ll2,ll2))
   local h = len / 10 -- arrow length
   local w = len / 20 -- arrow width
   local Ux = torch.cdiv(ll,len)
   local Uy = torch.cdiv(ll2,len)
   -- zero the nans in Ux and Uy
   Ux[Ux:ne(Ux)] = 0
   Uy[Uy:ne(Uy)] = 0
   local Vx = -Uy
   local Vy = Ux
   local v1x = x1 - torch.cmul(Ux,h) + torch.cmul(Vx,w);
   local v1y = y1 - torch.cmul(Uy,h) + torch.cmul(Vy,w);

   local v2x = x1 - torch.cmul(Ux,h) - torch.cmul(Vx,w);
   local v2y = y1 - torch.cmul(Uy,h) - torch.cmul(Vy,w);
   self:segment(v1x,v1y,v2x,v2y,color)
   self:segment(v1x,v1y,x1,y1,color)
   self:segment(v2x,v2y,x1,y1,color)
   return self
end

function Plot:quad(x0,y0,x1,y1,color,legend)
   -- x and y are [a 1D tensor of N elements or a table of N elements]
   x0 = tensorValidate(x0)
   x1 = tensorValidate(x1)
   y0 = tensorValidate(y0)
   y1 = tensorValidate(y1)
   -- check if x and y are same number of elements
   assert(x0:nElement() == y0:nElement(),
          'x0 and y0 should have same number of elements')
   assert(x0:nElement() == x1:nElement(),
          'x0 and x1 should have same number of elements')
   assert(x0:nElement() == y1:nElement(),
          'x0 and y1 should have same number of elements')

   color = color or 'red'
   legend = legend or 'unnamed'

   self._data = self._data or {}
   local _d = {}
   _d.type = 'Quad'
   _d.x0 = x0
   _d.y0 = y0
   _d.x1 = x1
   _d.y1 = y1
   _d.fill_color = color
   _d.line_color = color
   if legend then
      _d.legend = legend
   end
   table.insert(self._data, _d)
   return self
end

function Plot:histogram(x, nBins, min, max, color, legend)
   min = min or x:min()
   max = max or x:max()
   nBins = nBins or 100
   local hist = torch.histc(x, nBins, min, max)
   nBins = hist:size(1)
   local x0 = torch.linspace(min, max, nBins)
   local x1 = x0 + (max-min)/nBins
   self:quad(x0, torch.zeros(nBins), x1, hist, color, legend)
   return self
end

Plot.hist = Plot.histogram

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

local createGlyph = {}
local function createSimpleGlyph(docid, data, name)
   local glyph = newElem(name, docid)
   glyph.attributes.x = {}
   glyph.attributes.x.units = 'data'
   glyph.attributes.x.field = 'x'
   glyph.attributes.y = {}
   glyph.attributes.y.units = 'data'
   glyph.attributes.y.field = 'y'
   glyph.attributes.line_color = {}
   if type(data.line_color) == 'string' then
      glyph.attributes.line_color.value = data.line_color
   else
      glyph.attributes.line_color.units = 'data'
      glyph.attributes.line_color.field = 'line_color'
   end
   glyph.attributes.line_alpha = {}
   glyph.attributes.line_alpha.units = 'data'
   glyph.attributes.line_alpha.value = 1.0
   glyph.attributes.fill_color = {}
   if type(data.fill_color) == 'string' then
      glyph.attributes.fill_color.value = data.fill_color
   else
      glyph.attributes.fill_color.units = 'data'
      glyph.attributes.fill_color.field = 'fill_color'
   end
   glyph.attributes.fill_alpha = {}
   glyph.attributes.fill_alpha.units = 'data'
   glyph.attributes.fill_alpha.value = 0.2

   glyph.attributes.size = {}
   glyph.attributes.size.units = 'screen'
   glyph.attributes.size.value = 10
   glyph.attributes.tags = {}
   return glyph
end
createGlyph['Circle'] = function(docid, data)
   return createSimpleGlyph(docid, data, 'Circle')
end

createGlyph['Line'] = function(docid, data)
   return createSimpleGlyph(docid, data, 'Line')
end

createGlyph['Triangle'] = function(docid, data)
   return createSimpleGlyph(docid, data, 'Triangle')
end

local function addunit(t,f,f2)
   f2 = f2 or f
   t[f] = {}
   t[f].units = 'data'
   t[f].field = f2
end

createGlyph['Segment'] = function(docid, data)
   local glyph = newElem('Segment', docid)
   addunit(glyph.attributes, 'x0')
   addunit(glyph.attributes, 'x1')
   addunit(glyph.attributes, 'y0')
   addunit(glyph.attributes, 'y1')
   if type(data.line_color) == 'string' then
      glyph.attributes.line_color = {}
      glyph.attributes.line_color.value = data.line_color
   else
      addunit(glyph.attributes, 'line_color')
   end
   glyph.attributes.line_alpha = {}
   glyph.attributes.line_alpha.units = 'data'
   glyph.attributes.line_alpha.value = 1.0

   glyph.attributes.line_width = {}
   glyph.attributes.line_width.units = 'data'
   glyph.attributes.line_width.value = 2

   glyph.attributes.size = {}
   glyph.attributes.size.units = 'screen'
   glyph.attributes.size.value = 10
   glyph.attributes.tags = {}
   return glyph
end

createGlyph['Quad'] = function(docid, data)
   local glyph = newElem('Quad', docid)
   addunit(glyph.attributes, 'left', 'x0')
   addunit(glyph.attributes, 'right', 'x1')
   addunit(glyph.attributes, 'bottom', 'y0')
   addunit(glyph.attributes, 'top', 'y1')
   if type(data.line_color) == 'string' then
      glyph.attributes.line_color = {}
      glyph.attributes.line_color.value = data.line_color
   else
      addunit(glyph.attributes, 'line_color')
   end
   glyph.attributes.line_alpha = {}
   glyph.attributes.line_alpha.units = 'data'
   glyph.attributes.line_alpha.value = 1.0

   if type(data.fill_color) == 'string' then
      glyph.attributes.fill_color = {}
      glyph.attributes.fill_color.value = data.fill_color
   else
      addunit(glyph.attributes, 'fill_color')
   end
   glyph.attributes.fill_alpha = {}
   glyph.attributes.fill_alpha.units = 'data'
   glyph.attributes.fill_alpha.value = 0.7

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
      local c = cds[i]
      drx.attributes.sources[i].columns = {}
      for k,cname in ipairs(c.attributes.column_names) do
         if cname:sub(1,1) == col then
            table.insert(drx.attributes.sources[i].columns, cname)
         end
      end
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

local function createLegend(docid, plotid, data, grs)
   local l = newElem('Legend', docid)
   l.attributes.plot = {}
   l.attributes.plot.subtype = 'Figure'
   l.attributes.plot.type = 'Plot'
   l.attributes.plot.id = plotid
   l.attributes.legends = {}
   for i=1,#data do
      l.attributes.legends[i] = {}
      l.attributes.legends[i][1] = data[i].legend
      l.attributes.legends[i][2] = {{}}
      l.attributes.legends[i][2][1].type = 'GlyphRenderer'
      l.attributes.legends[i][2][1].id = grs[i].id
   end
   return l
end

local function createColumnDataSource(docid, data)
   local cds = newElem('ColumnDataSource', docid)
   cds.attributes.selected = {}
   cds.attributes.cont_ranges = {}
   cds.attributes.discrete_ranges = {}
   cds.attributes.column_names = {}
   cds.attributes.data = {}
   for k,v in pairs(data) do
      if k ~= 'legend' and k ~= 'type' and type(v) ~= 'string' then
         table.insert(cds.attributes.column_names, k)
         if torch.isTensor(v) then v = v:contiguous():storage():totable() end
         cds.attributes.data[k] = v
      end
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
   for i=1,#self._data do
      local d = self._data[i]
      local gltype = d.type

      -- convert data to ColumnDataSource
      local cds = createColumnDataSource(self._docid, d)
      table.insert(all_models, cds)
      cdss[#cdss+1] = cds

      -- create Glyph
      local sglyph = createGlyph[gltype](self._docid, d)
      local nsglyph = createGlyph[gltype](self._docid, d)
      table.insert(all_models, sglyph)
      table.insert(all_models, nsglyph)

      -- GlyphRenderer
      local gr = newElem('GlyphRenderer', self._docid)
      gr.attributes.nonselection_glyph = {}
      gr.attributes.nonselection_glyph.type = gltype
      gr.attributes.nonselection_glyph.id = nsglyph.id
      gr.attributes.data_source = {}
      gr.attributes.data_source.type = 'ColumnDataSource'
      gr.attributes.data_source.id = cds.id
      gr.attributes.name = json.null
      gr.attributes.server_data_source = json.null
      gr.attributes.selection_glyph = json.null
      gr.attributes.glyph = {}
      gr.attributes.glyph.type = gltype
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
   tools[2] = createTool(self._docid, 'WheelZoomTool', plot.id,
                         {'width', 'height'})
   tools[3] = createTool(self._docid, 'BoxZoomTool', plot.id, nil)
   tools[4] = createTool(self._docid, 'PreviewSaveTool', plot.id, nil)
   tools[5] = createTool(self._docid, 'ResizeTool', plot.id, nil)
   tools[6] = createTool(self._docid, 'ResetTool', plot.id, nil)
   for i=1,#tools do table.insert(all_models, tools[i]) end

   if self._legend then
      local legend = createLegend(self._docid, plot.id, self._data, grs)
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
   local m = util.msg('display_data', itorch._msg)
   m.content = content
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
