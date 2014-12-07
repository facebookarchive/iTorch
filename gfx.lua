local ffi = require 'ffi'
local uuid = require 'uuid'
local base64 = require 'base64'
local tablex = require 'pl.tablex'
require 'image'
local itorch = require 'itorch._env'
require 'itorch.bokeh'
local util = require 'itorch.util'

-- Example: require 'image';itorch.image(image.scale(image.lena(),16,16))
function itorch.image(img)
   assert(itorch._iopub,'itorch._iopub socket not set')
   assert(itorch._msg,'itorch._msg not set')
   if torch.typename(img) == 'string' then -- assume that it is path
      img = image.load(img) -- TODO: revamp this to just directly load the blob, infer file prefix, and send.
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
   else
      error('unhandled type in itorch.image:' .. torch.type(img))
   end
end

function itorch.lena()
   itorch.image(image.lena())
end

return itorch;
