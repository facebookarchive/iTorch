local ffi = require 'ffi'
local uuid = require 'uuid'
local base64 = require 'base64'
require 'pl.text'.format_operator()
require 'image'
local itorch = require 'itorch._env'
require 'itorch.bokeh'
local util = require 'itorch.util'

-- Example: require 'image';itorch.image(image.scale(image.lena(),16,16))
function itorch.image(img, opts)
   assert(itorch._iopub,'itorch._iopub socket not set')
   assert(itorch._msg,'itorch._msg not set')
   if torch.typename(img) == 'string' then -- assume that it is path
      img = image.load(img, 3) -- TODO: revamp this to just directly load the blob, infer file prefix, and send.
   end
   if torch.isTensor(img) or torch.type(img) == 'table' then
      opts = opts or {padding=2}
      opts.input = img
      local imgDisplay = image.toDisplayTensor(opts)
      if imgDisplay:dim() == 2 then 
	 imgDisplay = imgDisplay:view(1, imgDisplay:size(1), imgDisplay:size(2))
      end
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
      content.metadata['image/png'] = {width = imgDisplay:size(3), height = imgDisplay:size(2)}

      local m = util.msg('display_data', itorch._msg)
      m.content = content
      util.ipyEncodeAndSend(itorch._iopub, m)
   else
      error('unhandled type in itorch.image:' .. torch.type(img))
   end
end

local audio_template = [[
<div id="${div_id}"><audio controls src="data:audio/${extension};base64,${base64audio}" /></div>   
]]
-- Example: itorch.audio('hello.mp3')
function itorch.audio(fname)
   assert(itorch._iopub,'itorch._iopub socket not set')
   assert(itorch._msg,'itorch._msg not set')
   
   -- get prefix
   local pos = fname:reverse():find('%.')
   local ext = fname:sub(#fname-pos + 2)
   assert(ext == 'mp3' or ext == 'wav' or ext == 'ogg' or ext == 'aac', 
	  'mp3, wav, ogg, aac files supported. But found extension: ' .. ext)
   -- load the audio as binary blob
   local f = assert(torch.DiskFile(fname,'r',true), 
		    'File could not be opened: ' .. fname):binary();
   f:seekEnd();
   local size = f:position()-1
   f:seek(1)
   local buf = torch.CharStorage(size);
   assert(f:readChar(buf) == size, 'wrong number of bytes read')
   f:close()
   local base64audio = base64.encode(ffi.string(torch.data(buf), size))
   local div_id = uuid.new()
   local content = {}
   content.source = 'itorch'
   content.data = {}
   content.data['text/html'] =
      audio_template % {
         div_id = div_id,
         extension = ext,
	 base64audio = base64audio
      };
   content.metadata = {}
   local m = util.msg('display_data', itorch._msg)
   m.content = content
   util.ipyEncodeAndSend(itorch._iopub, m)
   return window_id
end

local video_template = [[
<div id="${div_id}"><video controls src="data:video/${extension};base64,${base64video}" /></div>   
]]
-- Example: itorch.video('hello.mp4')
function itorch.video(fname)
   assert(itorch._iopub,'itorch._iopub socket not set')
   assert(itorch._msg,'itorch._msg not set')
   
   -- get prefix
   local pos = fname:reverse():find('%.')
   local ext = fname:sub(#fname-pos + 2)
   if ext == 'ogv' then ext = 'ogg' end
   assert(ext == 'mp4' or ext == 'wav' or ext == 'ogg' or ext == 'webm',
	  'mp4, ogg, webm files supported. But found extension: ' .. ext)

   -- load the video as binary blob
   local f = assert(torch.DiskFile(fname,'r',true), 
		    'File could not be opened: ' .. fname):binary();
   f:seekEnd();
   local size = f:position()-1
   f:seek(1)
   local buf = torch.CharStorage(size);
   assert(f:readChar(buf) == size, 'wrong number of bytes read')
   f:close()
   local base64video = base64.encode(ffi.string(torch.data(buf), size))
   local div_id = uuid.new()
   local content = {}
   content.source = 'itorch'
   content.data = {}
   content.data['text/html'] =
      video_template % {
         div_id = div_id,
         extension = ext,
	 base64video = base64video
      };
   content.metadata = {}
   local m = util.msg('display_data', itorch._msg)
   m.content = content
   util.ipyEncodeAndSend(itorch._iopub, m)
   return window_id
end

function itorch.lena()
   itorch.image(image.lena())
end

local html_template = 
[[
<script type="text/javascript">
  $(function() {
    $("#${window_id}").html('${html_content}'); // clear any previous plot in window_id     
  });
</script>
<div id="${div_id}"></div>
]]

local function escape_js(s)
   -- single quite
   s = s:gsub("'","\\'")
   -- double quote
   s = s:gsub('"','\\"')
   -- backslash
   s = s:gsub("\\","\\\\")
   -- newline
   s = s:gsub("\n","\\n")
   -- carriage return
   s = s:gsub("\r","\\r")
   -- tab
   s = s:gsub("\t","\\t")
   -- backspace
   s = s:gsub("\b","\\b")
   -- form feed
   s = s:gsub("\f","\\f")
   return s
end
function itorch.html(html, window_id)
   html = escape_js(html)
   assert(itorch._iopub,'itorch._iopub socket not set')
   assert(itorch._msg,'itorch._msg not set')

   local div_id = uuid.new()
   window_id = window_id or div_id
   local content = {}
   content.source = 'itorch'
   content.data = {}
   content.data['text/html'] =
      html_template % {
	 html_content = html,
         window_id = window_id,
         div_id = div_id
      };
   content.metadata = {}

   -- send displayData
   local m = util.msg('display_data', itorch._msg)
   m.content = content
   util.ipyEncodeAndSend(itorch._iopub, m)
   return window_id
end


local ok,err = pcall(function() require 'xlua' end)
if ok then
   local progress_warning = false
   local last = os.clock()
   xlua.progress = function(i, n)
      -- make progress bar really slow in itorch
      if os.clock() - last > 15 then -- 15 seconds
	 print('Progress: ' ..  i .. ' / ' ..  n)
	 last = os.clock()
      end
      -- local m = util.msg('clear_output', itorch._msg)
      -- m.content = {}
      -- m.content.wait = true
      -- m.content.display = true
      -- util.ipyEncodeAndSend(itorch._iopub, m)
      -- itorch.html(progress_template % {})
   end
end

return itorch;
