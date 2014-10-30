local ffi = require 'ffi'
local uuid = require 'uuid'
local json = require 'cjson'
local base64 = require 'base64'
local tablex = require 'pl.tablex'
require 'pl.text'.format_operator()
require 'image'
local itorch = require 'itorch.env'

itorch.ifx = itorch.ifx or {}
local ifx = itorch.ifx

local bokeh_template = [[
<link rel="stylesheet" href="http://cdn.pydata.org/bokeh-0.6.1.min.css" type="text/css" />
<script type="text/javascript">
$.getScript("http://cdn.pydata.org/bokeh-0.6.1.min.js", function() {
  var g = ${glyphspecs}
  var d = ${data}
  var o = ${options}
  $("#${window_id}").html(''); // clear any previous plot in window_id
  var plot = Bokeh.Plotting.make_plot(g,d,o);
  Bokeh.Plotting.show(plot,"#${window_id}");
    });
</script>
<div class="plotdiv" id="${div_id}"></div>
]]

-- Bokeh.Plotting.make_plot = (glyphspecs, data, {nonselected, title, dims, xrange, yrange, xaxes, yaxes, xgrid, ygrid, xdr, ydr, tools, legend})
function ifx.plot(data, glyphspecs, options, window_id)
   assert(itorch.iopub,'ifx.iopub socket not set')
   assert(itorch.msg,'ifx.msg not set')
   local div_id = uuid.new()
   local window_id = window_id or div_id
   local content = {}
   content.source = 'itorch'
   content.data = {}
   content.data['text/html'] = 
      bokeh_template % {
	 window_id = window_id,
	 div_id = div_id,
         glyphspecs = json.encode(glyphspecs),
	 data = json.encode(data),
	 options = json.encode(options)
	};
   content.metadata = {}
   local header = tablex.deepcopy(itorch.msg.header)
   header.msg_id = uuid.new()
   header.msg_type = 'display_data'

   -- send displayData
   local m = { 
      uuid = itorch.msg.uuid, 
      content = content,
      parent_header = itorch.msg.header,
      header = header
   }
   itorch.ipyEncodeAndSend(itorch.iopub, m)
   return window_id
end

-- 2D charts
-- scatter
function ifx.scatter(data, options, window_id)
   
end

-- bar (grouped and stacked)
-- pie
-- histogram
-- area-chart (http://bokeh.pydata.org/docs/gallery/brewer.html)
-- categorical heatmap
-- timeseries
-- confusion matrix
-- image_rgba
-- candlestick
-- vectors
------------------
-- 2D plots
-- line plot
-- log-scale plots
-- semilog-scale plots
-- error-bar / candle-stick plot
-- contour plots
-- polar plots / angle-histogram plot / compass plot (arrowed histogram)
-- vector fields (feather plot, quiver plot, compass plot, 3D quiver plot)
-------------------------
-- 3D plots
-- line plot
-- scatter-3D ************** (important)
-- contour-3D
-- 3D shaded surface plot (surf/surfc)
-- surface normals
-- mesh plot
-- ribbon plot (for fun)

-- create a torch.peaks (useful)
--------------------------------------------------------------------
-- view videos
-- 

function ifx.testplot(window_id)
   -- data
   local x = torch.randn(4000):mul(100):storage():totable()
   local y = torch.randn(4000):mul(100):storage():totable()
   data = {
      x = x,
      y = y
   }

   -- glyph
   local glyph = {
      type = 'circle',
      x = 'x',
      y = 'y',
      radius = 0.3,
      radius_units = 'data',
      fill_color = 'red',
      fill_alpha = 0.6,
      line_color = nil
   }
   if window_id then glyph.fill_color = 'yellow' end

   -- options
   options = {
      title = 'Scatter Demo',
      dims = {600, 600},
      xrange = {0, 100},
      yrange = {0, 100},
      xaxes = "below",
      yaxes = "left",
      tools = true,
      legend =  false
   }
   -- plot
   return ifx.plot(data, glyph, options, window_id)
end

return ifx;
