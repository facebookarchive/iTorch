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


local bokeh_template = [[
<link rel="stylesheet" href="http://cdn.pydata.org/bokeh-0.6.1.min.css" type="text/css" />
<script type="text/javascript">
    $.getScript("http://cdn.pydata.org/bokeh-0.6.1.min.js", function() {
  var N, d, data, i, image, j, linspace, options, plot, xs, _i, _j, _ref, _ref1;

  linspace = function(d1, d2, n) {
    var L, j, tmp1, tmp2;
    j = 0;
    L = new Array();
    while (j <= (n - 1)) {
      tmp1 = j * (d2 - d1) / (Math.floor(n) - 1);
      tmp2 = Math.ceil((d1 + tmp1) * 10000) / 10000;
      L.push(tmp2);
      j = j + 1;
    }
    return L;
  };

  N = 600;

  d = new Array(N);

  xs = linspace(0, 10, N);

  for (i = _i = 0, _ref = N - 1; 0 <= _ref ? _i <= _ref : _i >= _ref; i = 0 <= _ref ? ++_i : --_i) {
    for (j = _j = 0, _ref1 = N - 1; 0 <= _ref1 ? _j <= _ref1 : _j >= _ref1; j = 0 <= _ref1 ? ++_j : --_j) {
      if (j === 0) {
        d[i] = new Array(N);
      }
      d[i][j] = Math.sin(xs[i]) * Math.cos(xs[j]);
    }
  }

  data = {
    image: [d]
  };

  image = {
    type: 'image',
    x: 0,
    y: 0,
    dw: 10,
    dw_units: 'data',
    dh: 10,
    dh_units: 'data',
    image: 'image',
    palette: 'Spectral-10'
  };

  options = {
    title: "Image Demo",
    dims: [600, 600],
    xrange: [0, 10],
    yrange: [0, 10],
    xaxes: "below",
    yaxes: "left",
    tools: "pan,wheel_zoom,box_zoom,resize,preview",
    legend: false
  };

  plot = Bokeh.Plotting.make_plot(image, data, options);
  Bokeh.Plotting.show(plot,"#${div_id}");
    });
</script>
<div class="plotdiv" id="${div_id}"></div>
]]

require 'pl.text'.format_operator()

function igfx.plot()
   assert(itorch.iopub,'igfx.iopub socket not set')
   assert(itorch.msg,'igfx.msg not set')
   local content = {}
   content.source = 'itorch'
   content.data = {}
   content.data['text/html'] = 
      bokeh_template % {
	 div_id = uuid.new(),
	};
   print(content.data['text/html'])
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
