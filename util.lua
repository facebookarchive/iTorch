--[[
 *  Copyright (c) 2015, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant 
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
]]--
local zmq = require 'lzmq'
local zassert = zmq.assert
local json=require 'cjson'
local uuid = require 'uuid'

local util = {}
--------------------------------------------------------------
-- Common decoder function for all messages (except heartbeats which are just looped back)
local function ipyDecode(sock, m)
   m = m or zassert(sock:recv_all())
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

local session_id = uuid.new()
-- function for creating a new message object
local function msg(msg_type, parent)
   local m = {}
   m.header = {}
   if parent then
      m.uuid = parent.uuid
      m.parent_header = parent.header
   else
      m.parent_header = {}
   end
   m.header.msg_id = uuid.new()
   m.header.msg_type = msg_type
   m.header.session = session_id
   m.header.date = os.date("%Y-%m-%dT%H:%M:%S")
   m.header.username = 'itorch'
   m.content = {}
   return m
end

---------------------------------------------------------------------------

util.ipyDecode = ipyDecode
util.ipyEncodeAndSend = ipyEncodeAndSend
util.msg = msg

return util
