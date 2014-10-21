#!/usr/bin/env luajit
require 'env' -- TODO: remove
local zmq = require 'lzmq'
local zloop = require 'lzmq.loop'
local zassert = zmq.assert
local json=require 'cjson'
local uuid = require 'uuid'
local tablex = require 'pl.tablex'
local completer = require 'trepl.completer'
require 'paths'
-----------------------------------------
local context = zmq.context()
local exec_count = 0
------------------------------------------
-- load and decode json config
local ipyfile = assert(io.open(arg[1], "rb"), "Could not open iPython config")
local ipyjson = ipyfile:read("*all")
ipyfile:close()
local ipycfg = json.decode(ipyjson)
--------------------------------------------------------------
-- bind 0MQ ports: Heartbeat (REP), Shell (ROUTER), Control (ROUTER), Stdin (ROUTER), IOPub (PUB)
local ip = ipycfg.transport .. '://' .. ipycfg.ip .. ':'
local heartbeat, err = context:socket{zmq.REP,    bind = ip .. ipycfg.hb_port}
zassert(heartbeat, err)
local shell, err     = context:socket{zmq.ROUTER, bind = ip .. ipycfg.shell_port}
zassert(shell, err)
local control, err   = context:socket{zmq.ROUTER, bind = ip .. ipycfg.control_port}
zassert(control, err)
local stdin, err     = context:socket{zmq.ROUTER, bind = ip .. ipycfg.stdin_port}
zassert(stdin, err)
local iopub, err     = context:socket{zmq.PUB,    bind = ip .. ipycfg.iopub_port}
zassert(iopub, err)
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
   if m.blob then o[#o+1] = blob end
   -- print('outgoing:')
   -- print(o)
   zassert(sock:send_all(o))
end
---------------------------------------------------------------------------
-- IOPub router
local iopub_router = {}
-- http://ipython.org/ipython-doc/dev/development/messaging.html#kernel-status
iopub_router.status = function(sock, m, state)
   assert(state, 'state string is nil to iopub_router.status');
   local o = {}
   o.uuid = {'status'};
   if m then o.parent_header = m.header end
   o.header = {};
   o.header.session = '????';
   if m then o.header.session = m.header.session end
   o.header.msg_id = uuid.new()
   o.header.msg_type = 'status';
   o.header.username = 'torchkernel';
   o.content = { execution_state = state }
   ipyEncodeAndSend(sock, o);
end
-- http://ipython.org/ipython-doc/dev/development/messaging.html#streams-stdout-stderr-etc
iopub_router.stream = function(sock, m, stream, text)
   stream = stream or 'stdout'
   local o = {}
   o.uuid = m.uuid
   o.parent_header = m.header
   o.header = {};
   o.header.msg_id = uuid.new();
   o.header.session = m.header.session;
   o.header.msg_type = 'stream';
   o.content = {
      name = stream,
      text = text
   }
   ipyEncodeAndSend(sock, o);
end

---------------------------------------------------------------------------
-- Shell router
local shell_router = {}
shell_router.connect_request = function (sock, msg)
   msg.parent_header = msg.header
   msg.header = tablex.deepcopy(msg.parent_header)
   msg.header.msg_type = 'connect_reply';
   msg.header.msg_id = uuid.new();
   msg.content = ipycfg;
   ipyEncodeAndSend(sock, msg);
end

shell_router.kernel_info_request = function (sock, msg)
   iopub_router.status(sock, msg, 'busy');
   msg.parent_header = msg.header
   msg.header = tablex.deepcopy(msg.parent_header)
   msg.header.msg_type = 'kernel_info_reply';
   msg.header.msg_id = uuid.new();
   msg.content = {
      protocol_version = '5.0',
      implementation = 'itorch',
      implementation_version = '0.1',
      language = 'luajit',
      language_version = '5.1',
      banner = 'Torch 7.0  Copyright (C) 2001-2014 Idiap, NEC, NYU, Deepmind'
   }
   ipyEncodeAndSend(sock, msg);
   iopub_router.status(sock, msg, 'idle');
end

shell_router.execute_request = function (sock, msg)
   iopub_router.status(iopub, msg, 'busy');
   local ok, result = pcall(function() loadstring(msg.content.code)() end); -- TODO: create a session per UUID
   if not ok then print('Error in executed code') end
   if msg.content.store_history then
      exec_count = exec_count + 1; -- TODO: store the code for every call
   end
   local o = {}
   o.uuid = msg.uuid
   o.parent_header = msg.header
   o.header = tablex.deepcopy(msg.header)
   -- execute_input -- iopub
   o.header.msg_id = uuid.new()
   o.header.msg_type = 'execute_input'
   o.content = {
      code = msg.content.code,
      execution_count = exec_count
   }
   ipyEncodeAndSend(iopub, o);
   -- execute_result -- iopub
   o.header.msg_id = uuid.new()
   o.header.msg_type = 'execute_result'
   o.content = {
      data = {},
      metadata = {},
      execution_count = exec_count
   }
   o.content.data['text/plain'] = 'hello' -- TODO: fix
   ipyEncodeAndSend(iopub, o);

   -- execute_reply -- shell
   o.header.msg_type = 'execute_reply'
   o.content = {
      status = 'ok',
      execution_count = exec_count,
      payload = {},
      user_expressions = {}
   }
   ipyEncodeAndSend(sock, o);
   iopub_router.status(iopub, msg, 'idle');
end

shell_router.history_request = function (sock, msg)
   print('WARNING: history_request not handled yet')
end

local function extract_completions(code_string)
   return {
      matches = completer.complete('', code_string, nil, nil),
      matched_text = '' -- e.g. torch.<TAB> should become torch.abs
   }
end

shell_router.complete_request = function(sock, msg)
   msg.parent_header = msg.header
   msg.header = tablex.deepcopy(msg.parent_header)
   msg.header.msg_type = 'complete_reply';
   msg.header.msg_id = uuid.new();
   print("COMPLETING: ", json.encode(msg))
   msg.content = extract_completions(msg.content.line)
   ipyEncodeAndSend(sock, msg);
end

---------------------------------------------------------------------------
local function handleHeartbeat(sock)
   local m = zassert(sock:recv()); zassert(sock:send(m))
end

local function handleShell(sock)
   local msg = ipyDecode(sock)
   assert(shell_router[msg.header.msg_type],
	  'Cannot find appropriate message handler for ' .. msg.header.msg_type)
   return shell_router[msg.header.msg_type](sock, msg);
end

local function handleControl(sock)
   print('ct')
   local buffer = zassert(sock:recv())
   zassert(sock:send(buffer))
end

local function handleStdin(sock)
   print('stdin')
   local buffer = zassert(sock:recv())
   zassert(sock:send(buffer))
end

local function handleIOPub(sock)
   print('io')
   local buffer = zassert(sock:recv())
   zassert(sock:send(buffer))
end

iopub_router.status(iopub, nil, 'starting');

local loop = zloop.new(1, context)
loop:add_socket(heartbeat, handleHeartbeat)
loop:add_socket(shell, handleShell)
loop:add_socket(control, handleControl)
loop:add_socket(stdin, handleStdin)
loop:add_socket(iopub, handleIOPub)
loop:start()

-- cleanup
heartbeat:close()
shell:close()
control:close()
stdin:close()
iopub:close()
