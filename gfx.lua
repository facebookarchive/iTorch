local igfx = {}
local ffi = require 'ffi'
local uuid = require 'uuid'
local json = require 'cjson'
local base64 = require 'base64'
local tablex = require 'pl.tablex'
local itorch = require 'itorch.env'

require 'image'

-- Example: require 'image';igfx.image(image.scale(image.lena(),16,16))
function igfx.image(img)
   assert(itorch.iopub,'igfx.iopub socket not set')
   assert(itorch.msg,'igfx.msg not set')
   if torch.typename(img) == 'string' then -- assume that it is path
      img = image.load(img)
   end
   if torch.isTensor(img) or torch.type(img) == 'table' then
      local imgDisplay = image.toDisplayTensor(img)
      local tmp = os.tmpname() .. '.png'
      image.save(tmp, imgDisplay)
      -------------------------------------------------------------
      -- load the image back as binary blob
      local f = assert(torch.DiskFile(tmp,'r',true)):binary();
      f:seekEnd();
      local size = f:position()-1
      f:seek(1)
      local buf = torch.CharStorage(size);
      assert(f:readChar(buf) == size, 'wrong number of bytes read')
      f:close()
      os.execute('rm -f ' .. tmp)
      ------------------------------------------------------------
      local content = {}
      content.source = 'itorch'
      content.data = {}
      content.data['text/plain'] = 'Console does not support images'
      content.data['image/png'] = base64.encode(ffi.string(torch.data(buf), size))
      content.metadata = { }
      content.metadata['image/png'] = {width = imgDisplay:size(2), height = imgDisplay:size(3)}
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
   else
      error('unhandled type in igfx.image:' .. torch.type(img))
   end
end

function igfx.lena()
   igfx.image(image.lena())
end

local blob = [[

<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="content-type" content="text/html; charset=UTF-8">
  <script type="text/javascript" src="http://fiddle.jshell.net/js/coffeescript/coffeescript.js"></script>
      <script type='text/javascript' src="http://cdn.pydata.org/bokeh-0.6.0.min.js"></script>
      <link rel="stylesheet" type="text/css" href="http://cdn.pydata.org/bokeh-0.6.0.min.css">
  <style type='text/css'>
  </style>
  <script type="text/coffeescript">
#
# Generate the initial data
#

linspace = (start, end, n) ->                
  L = new Array()
  d = (end - start)/(n-1)
  i = 0
  while i < (n-1)
    L.push(start + i*d);
    i++
  L.push(end)
  return L

N = 50 + 1
r_base = 8
theta = linspace(0, 2*Math.PI, N)
r_x = linspace(0, 6*Math.PI, N-1)
rmin = (r_base - Math.cos(r) - 1 for r in r_x)
rmax = (r_base + Math.sin(r) + 1 for r in r_x)

color = _.flatten((["FFFFCC", "#C7E9B4", "#7FCDBB", "#41B6C4", "#2C7FB8", "#253494", "#2C7FB8", "#41B6C4", "#7FCDBB", "#C7E9B4"] for i in [0..4]))

#
# Create the Bokeh plot
# 
window.source = Bokeh.Collections('ColumnDataSource').create(
  data:
    x: (0 for i in [0...rmin.length])
    y: (0 for i in [0...rmin.length])
    inner_radius: rmin
    outer_radius: rmax
    start_angle: theta.slice(0,-1)
    end_angle: theta.slice(1)
    color: color
)

glyph = {
  type: 'annular_wedge'
  x: 'x'
  y: 'y'
  inner_radius: 'inner_radius'
  outer_radius: 'outer_radius'
  start_angle: 'start_angle'
  end_angle: 'end_angle'
  fill_color: 'color'
  line_color: 'black'
}

options = {
  title: "Animation Demo"
  dims: [600, 600]
  xrange: [-11, 11]
  yrange: [-11, 11]
  xaxes: "below"
  yaxes: "left"
  tools: "pan,wheel_zoom,box_zoom,reset,resize"
}

plot = Bokeh.Plotting.make_plot(glyph, window.source, options)
Bokeh.Plotting.show(plot)

#
# Update the plot data on an interval
# 
update = () ->
  data = window.source.get('data')
  rmin = data["inner_radius"]
  tmp = [rmin[rmin.length-1] ].concat(rmin.slice(0, -1))
  data["inner_radius"] = tmp
  rmax = data["outer_radius"]
  tmp = rmax.slice(1).concat([rmax[0] ])
  data["outer_radius"] = tmp
  window.source.set('data', data)
  window.source.trigger('change', source, {})

setInterval(update, 100)
</script>
</head>
<body>
</body>
</html>

   ]]

local blob2 = [[
<html><p>Hello!!!</p></html>
]]

function igfx.plot()
   assert(itorch.iopub,'igfx.iopub socket not set')
   assert(itorch.msg,'igfx.msg not set')
   local content = {}
   content.source = 'itorch'
   content.data = {}
   content.data['text/html'] = blob
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
end

return igfx;
