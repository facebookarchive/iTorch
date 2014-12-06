local zmq = require 'lzmq'
local zassert = zmq.assert
local json=require 'cjson'
local uuid = require 'uuid'

local util = {}
--------------------------------------------------------------
-- Common decoder function for all messages (except heartbeats which are just looped back)
local function ipyDecode(sock)
   local m = zassert(sock:recv_all())
   -- print('incoming:')
   -- print(m)
   local o = {}
   o.uuid = {}
   local i = -1
   for k,v in ipairs(m) do
      if v == '<IDS|MSG>' then i = k+1; break; end
      o.uuid[k] = v
   end
   assert(i ~= -1, 'Failed parsing till <IDS|MSG>')
   -- json decode
   for j=i+1,i+4 do if m[j] == '{}' then m[j] = nil; else m[j] = json.decode(m[j]); end; end
      -- populate headers
      o.header        = m[i+1]
      o.parent_header = m[i+2]
      o.metadata      = m[i+3]
      o.content       = m[i+4]
      for j=i+5,#m do o.blob = (o.blob or '') .. m[j] end -- process blobs
      return o
end
-- Common encoder function for all messages (except heartbeats which are just looped back)
local function ipyEncodeAndSend(sock, m)
   local o = {}
   for k,v in ipairs(m.uuid) do o[#o+1] = v end
   o[#o+1] = '<IDS|MSG>'
   o[#o+1] = ''
   o[#o+1] = json.encode(m.header)
   if m.parent_header then o[#o+1] = json.encode(m.parent_header) else o[#o+1] = '{}' end
   if m.metadata then o[#o+1] = json.encode(m.metadata) else o[#o+1] = '{}' end
   if m.content then o[#o+1] = json.encode(m.content) else o[#o+1] = '{}' end
   if m.blob then o[#o+1] = m.blob end
   -- print('outgoing:')
   -- print(o)
   zassert(sock:send_all(o))
end
---------------------------------------------------------------------------

util.ipyDecode = ipyDecode
util.ipyEncodeAndSend = ipyEncodeAndSend

return util
