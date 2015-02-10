--[[
 *  Copyright (c) 2015, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant 
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
]]--
-- external dependencies
local zmq = require 'lzmq'
local zloop = require 'lzmq.loop'
local zassert = zmq.assert
local json=require 'cjson'
local uuid = require 'uuid'
local tablex = require 'pl.tablex'

-- torch ecosystem dependencies
local completer = require 'itorch.completer'
require 'dok' -- for help(function) to work
require 'env' -- TODO: remove

-- itorch requires
require 'itorch'
local util = require 'itorch.util'
-----------------------------------------
local context = zmq.context()
local session = {}
session.create = function(self, uuid)
   local s = {}
   -- history
   s.history = { code = {}, output = {} }
   s.exec_count = 0
   -- set and return
   self[uuid] = s
   return self[uuid]
end
------------------------------------------
-- load and decode json config
local ipyfile = assert(io.open(arg[1], "rb"), "Could not open iPython config")
local ipyjson = ipyfile:read("*all")
ipyfile:close()
local ipycfg = json.decode(ipyjson)
--------------------------------------------------------------
-- bind 0MQ ports: Shell (ROUTER), Control (ROUTER), Stdin (ROUTER), IOPub (PUB)
local ip = ipycfg.transport .. '://' .. ipycfg.ip .. ':'
local shell, err     = context:socket{zmq.ROUTER, bind = ip .. ipycfg.shell_port}
zassert(shell, err)
local control, err   = context:socket{zmq.ROUTER, bind = ip .. ipycfg.control_port}
zassert(control, err)
local stdin, err     = context:socket{zmq.ROUTER, bind = ip .. ipycfg.stdin_port}
zassert(stdin, err)
local iopub, err     = context:socket(zmq.PAIR)
zassert(iopub, err)
do
   -- find a random open port between 10k and 65k with 1000 attempts.
   local port, err = iopub:bind_to_random_port(ipycfg.transport .. '://' .. ipycfg.ip, 
					       10000,65535,1000) 
   zassert(port, err)
   local portnum_f = torch.DiskFile(arg[2],'w')
   portnum_f:writeInt(port)
   portnum_f:close()
end
itorch._iopub = iopub -- for the display functions to have access
arg = nil -- forget the command-line args
--------------------------------------------------------------
-- IOPub router
local iopub_router = {}
-- http://ipython.org/ipython-doc/dev/development/messaging.html#kernel-status
iopub_router.status = function(sock, m, state)
   assert(state, 'state string is nil to iopub_router.status');
   local o = util.msg('status', m)
   o.uuid = {'status'};
   o.content = { execution_state = state }
   util.ipyEncodeAndSend(sock, o);
end
-- http://ipython.org/ipython-doc/dev/development/messaging.html#streams-stdout-stderr-etc
iopub_router.stream = function(sock, m, stream, text)
   stream = stream or 'stdout'
   local o = util.msg('stream', m)
   o.content = {
      name = stream,
      data = text
   }
   util.ipyEncodeAndSend(sock, o);
end

---------------------------------------------------------------------------
-- Shell router
local shell_router = {}
shell_router.connect_request = function (sock, msg)
   local reply = util.msg('connect_reply', msg)
   reply.content = ipycfg;
   util.ipyEncodeAndSend(sock, reply);
end

shell_router.kernel_info_request = function (sock, msg)
   iopub_router.status(sock, msg, 'busy');
   local reply = util.msg('kernel_info_reply', msg)
   reply.content = {
      protocol_version = {4,0},
      language_version = {jit.version_num},
      language = 'lua'
   }
   util.ipyEncodeAndSend(sock, reply);
   iopub_router.status(sock, msg, 'idle');
end

shell_router.shutdown_request = function (sock, msg)
   iopub_router.status(sock, msg, 'busy');
   local reply = util.msg('shutdown_reply', msg)
   util.ipyEncodeAndSend(sock, reply);
   iopub_router.status(sock, msg, 'idle');
   -- cleanup
   print('Shutting down main')
   iopub:send_all({'private_msg', 'shutdown'})
   assert(zassert(iopub:recv()) == 'ACK')
   shell:close()
   control:close()
   stdin:close()
   iopub:close()
   loop:stop()
   os.exit()
end

local function traceback(message)
   local tp = type(message)
   if tp ~= "string" and tp ~= "number" then return message end
   local debug = _G.debug
   if type(debug) ~= "table" then return message end
   local tb = debug.traceback
   if type(tb) ~= "function" then return message end
   return tb(message)
end


io.stdout:setvbuf('no')
io.stderr:setvbuf('no')

shell_router.execute_request = function (sock, msg)
   itorch._msg = msg
   iopub_router.status(iopub, msg, 'busy');
   local s = session[msg.header.session] or session:create(msg.header.session)
   if not msg.content.silent and msg.content.store_history then
      s.exec_count = s.exec_count + 1;
   end
   -- send current session info to IOHandler, blocking-wait for ACK that it received it
   iopub:send_all({'private_msg', 'current_msg', json.encode(msg)})
   assert(zassert(iopub:recv()) == 'ACK')
   iopub:send_all({'private_msg', 'exec_count', s.exec_count})
   assert(zassert(iopub:recv()) == 'ACK')

   local line = msg.content.code
   -- help
   if line and line:find('^%s-?') then
      local pkg = line:gsub('^%s-?','')
      line = 'help(' .. pkg .. ')'
   end
   local cmd = line .. '\n'
   if cmd:sub(1,1) == "=" then cmd = "return "..cmd:sub(2) end

   local pok, func, perr, ok, err, output
   if line:find(';%s-$') or line:find('^%s-print') then
      func, perr = loadstring(cmd) -- syntax error (in semi-colon case)
   else -- syntax error in (non-semicolon, so print out the result case)
      func, perr = loadstring('local f = function() return '.. line ..' end; local res = {f()}; print(unpack(res))')
      if not func then
         func, perr = loadstring(cmd)
      end
   end
   if func then
      pok = true
      -- TODO: for lua outputs to be streamed from the executing command (for example a long for-loop), redefine 'print' to stream-out pyout messages
      ok,err = xpcall(func, traceback)
   else
      ok = false;
      err = perr;
   end

   if not msg.content.silent and msg.content.store_history then
      table.insert(s.history.code, msg.content.code);
      table.insert(s.history.output, output);
   end
   -- pyin -- iopub
   local o = util.msg('pyin', msg)
   o.content = {
      code = msg.content.code,
      execution_count = s.exec_count
   }
   util.ipyEncodeAndSend(iopub, o);

   if ok then
      -- pyout (Now handled by IOHandler.lua)
      
      -- execute_reply -- shell
      o = util.msg('execute_reply', msg)
      o.content = {
         status = 'ok',
         execution_count = s.exec_count,
         payload = {},
         user_variables = {},
         user_expressions = {}
      }
      util.ipyEncodeAndSend(sock, o);
   elseif pok then -- means function execution had error
      -- pyerr -- iopub
      o = util.msg('pyerr', msg)
      o.content = {
         execution_count = s.exec_count,
         ename = err or 'Unknown Error',
         evalue = '',
         traceback = {err}
      }
      util.ipyEncodeAndSend(iopub, o);
      -- execute_reply -- shell
      o = util.msg('execute_reply', msg)
      o.content = {
         status = 'error',
         execution_count = s.exec_count,
         ename = err or 'Unknown Error',
         evalue = '',
         traceback = {err}
      }
      util.ipyEncodeAndSend(sock, o);
   else -- code has syntax error
      -- pyerr -- iopub
      o = util.msg('pyerr', msg)
      o.content = {
         execution_count = s.exec_count,
         ename = err or 'Unknown Error',
         evalue = '',
         traceback = {perr}
      }
      util.ipyEncodeAndSend(iopub, o);
      -- execute_reply -- shell
      o = util.msg('execute_reply', msg)
      o.content = {
         status = 'error',
         execution_count = s.exec_count,
         ename = err or 'Unknown Error',
         evalue = '',
         traceback = {perr}
      }
      util.ipyEncodeAndSend(sock, o);
   end
   iopub_router.status(iopub, msg, 'idle');
end

shell_router.history_request = function (sock, msg)
   print('WARNING: history_request not handled yet');
end

local word_break_characters = '[" \t\n\"\\\'><=;:%+%-%*/%%^~#{}%(%)%[%],"]'

local function extract_completions(text, line, block, pos)
   line = line:sub(1,pos)
   local matches, word
   do -- get matches
      local c_word, c_line
      local lb = line:gsub(word_break_characters, '*')
      local h,p = lb:find('.*%*')
      if h then
         c_line = line:sub(p+1)
      else
         c_line = line
      end
      local h,p = c_line:find('.*%.')
      if h then
         c_word = c_line:sub(p+1)
      else
         c_word = c_line;
         c_line = ''
      end
      matches = completer.complete(c_word, c_line, nil, nil)
      word = c_word
   end
   -- now that we got correct matches, create the proper matched_text
   for i=1,#matches do
      if text ~= '' then
         local r,p = text:find('.*' .. word)
         local t2 = ''
         if r then
            t2 = text:sub(1,p-#word)
         end
         matches[i] = t2 .. matches[i];
      end
   end
   return {
      matches = matches,
      matched_text = word, -- line, -- e.g. torch.<TAB> should become torch.abs
      status = 'ok'
   }
end

shell_router.complete_request = function(sock, msg)
   local reply = util.msg('complete_reply', msg)
   reply.content = extract_completions(msg.content.text, msg.content.line,
                                     msg.content.block, msg.content.cursor_pos)
   util.ipyEncodeAndSend(sock, reply);
end

shell_router.object_info_request = function(sock, msg)
   -- print(msg)
   -- TODO: I dont understand when this thing is called and when it isn't
end

---------------------------------------------------------------------------
local function handleShell(sock)
   local msg = util.ipyDecode(sock)
   assert(shell_router[msg.header.msg_type],
          'Cannot find appropriate message handler for ' .. msg.header.msg_type)
   return shell_router[msg.header.msg_type](sock, msg);
end

local function handleControl(sock)
   local msg = util.ipyDecode(sock);
   assert(shell_router[msg.header.msg_type],
          'Cannot find appropriate message handler for ' .. msg.header.msg_type)
   return shell_router[msg.header.msg_type](sock, msg);
end

local function handleStdin(sock)
   local buffer = zassert(sock:recv_all())
   zassert(sock:send_all(buffer))
end

local function handleIOPub(sock)
   local msg = util.ipyDecode(sock);
   assert(iopub_router[msg.header.msg_type],
          'Cannot find appropriate message handler for ' .. msg.header.msg_type)
   return iopub_router[msg.header.msg_type](sock, msg);
end

iopub_router.status(iopub, nil, 'starting');

loop = zloop.new(1, context)
loop:add_socket(shell, handleShell)
loop:add_socket(control, handleControl)
loop:add_socket(stdin, handleStdin)
loop:add_socket(iopub, handleIOPub)
loop:start()
