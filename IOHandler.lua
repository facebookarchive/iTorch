require 'env'
local zmq = require 'lzmq'
local zloop = require 'lzmq.loop'
local zassert = zmq.assert
local json=require 'cjson'
local uuid = require 'uuid'
local ffi = require'ffi'
local util = require 'itorch.util'
local context = zmq.context()
------------------------------------------
-- load and decode json config
local ipyfile = assert(io.open(arg[1], "rb"), "Could not open iPython config")
local ipyjson = ipyfile:read("*all")
ipyfile:close()
local ipycfg = json.decode(ipyjson)
local rawpub_port = arg[4]
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
local io_msgid = ffi.C.open(arg[3], O_NONBLOCK)

local ip = ipycfg.transport .. '://' .. ipycfg.ip .. ':'
local heartbeat, err = context:socket{zmq.REP,    bind = ip .. ipycfg.hb_port}
zassert(heartbeat, err)
local iopub, err = context:socket{zmq.PUB,    bind = ip .. ipycfg.iopub_port}
zassert(iopub, err)
local rawpub, err = context:socket{zmq.SUB,    connect = ip .. rawpub_port}
zassert(rawpub, err)

local function handleHeartbeat(sock)
   local m = zassert(sock:recv_all());
   zassert(sock:send_all(m))
end

function handleSTDO(ev)
   local nbytes = ffi.C.read(io_stdo,buffer,chunk_size)
   if nbytes > 0 then
      print(ffi.string(buffer, nbytes))
   end
   ev:set_interval(1)
end

function handleMSGID(ev)
   local nbytes = ffi.C.read(io_msgid, buffer,chunk_size)
   if nbytes > 0 then
      print('msgid:', ffi.string(buffer, nbytes))
   end
   ev:set_interval(1)
end

function handleRawPub(sock)
   print('rawpub')
   local m = zassert(sock:recv_all());
   print(m)
   zassert(iopub:send_all(m))
end

loop = zloop.new(1, context)
loop:add_socket(heartbeat, handleHeartbeat)
loop:add_socket(rawpub, handleRawPub)
loop:add_interval(1, handleSTDO)
loop:add_interval(1, handleMSGID)
loop:start()
