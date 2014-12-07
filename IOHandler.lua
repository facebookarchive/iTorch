require 'env'
local zmq = require 'lzmq'
local zloop = require 'lzmq.loop'
local zassert = zmq.assert
local json=require 'cjson'
local uuid = require 'uuid'
local ffi = require'ffi'
local util = require 'itorch.util'
local context = zmq.context()
local tablex = require 'pl.tablex'
local kvstore = {} -- this stores exclusive key-values passed in by main.lua
------------------------------------------
-- load and decode json config
local ipyfile = assert(io.open(arg[1], "rb"), "Could not open iPython config")
local ipyjson = ipyfile:read("*all")
ipyfile:close()
local ipycfg = json.decode(ipyjson)
local rawpub_port = arg[3]
--------------------------------------------------------------
--- The libc functions used by this process (for non-blocking IO)
ffi.cdef[[
      int open(const char* pathname, int flags);
      int close(int fd);
      int read(int fd, void* buf, size_t count);
 ]]   
local O_NONBLOCK = 0x0004
local chunk_size = 4096
local buffer = ffi.new('uint8_t[?]',chunk_size)
local io_stdo = ffi.C.open(arg[2], O_NONBLOCK)

local ip = ipycfg.transport .. '://' .. ipycfg.ip .. ':'
local heartbeat, err = context:socket{zmq.REP,    bind = ip .. ipycfg.hb_port}
zassert(heartbeat, err)
local iopub, err = context:socket{zmq.PUB,    bind = ip .. ipycfg.iopub_port}
zassert(iopub, err)
local rawpub, err = context:socket{zmq.PAIR,    connect = ip .. rawpub_port}
zassert(rawpub, err)

local function handleHeartbeat(sock)
   local m = zassert(sock:recv_all());
   zassert(sock:send_all(m))
end

function handleSTDO(ev)
   local nbytes = ffi.C.read(io_stdo,buffer,chunk_size)
   if nbytes > 0 then
      local output = ffi.string(buffer, nbytes)
      if kvstore.current_msg then
	 local o = {}
	 o.uuid = kvstore.current_msg.uuid
	 o.parent_header = kvstore.current_msg.header
	 o.header = tablex.deepcopy(kvstore.current_msg.header)
	 o.header.msg_id = uuid.new()
	 o.header.msg_type = 'pyout'
	 o.content = {
	    data = {},
	    metadata = {},
	    execution_count = kvstore.exec_count
	 }
	 o.content.data['text/plain'] = output
	 util.ipyEncodeAndSend(iopub, o)
      else
	 print(output)
      end
   end
   ev:set_interval(1)
end

function handleRawPub(sock)
   local m = zassert(sock:recv_all())
   -- if this message is a key-value from main.lua
   if m[1] == 'private_msg' then
      if m[2] == 'current_msg' then
	 kvstore[m[2]] = json.decode(m[3])
      elseif m[2] == 'exec_count' then
	 kvstore[m[2]] = tonumber(m[3])
      end
      sock:send('ACK')
      return
   end
   -- else, just pass it over to iopub
   zassert(iopub:send_all(m))
end

local function handleIOPub(sock)
   print('Error: IOPub is a Publisher, it cant have incoming requests')
end


loop = zloop.new(1, context)
loop:add_socket(heartbeat, handleHeartbeat)
loop:add_socket(rawpub, handleRawPub)
loop:add_socket(iopub, handleIOPub)
loop:add_interval(1, handleSTDO)
loop:start()
