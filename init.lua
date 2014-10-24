require 'env' -- TODO: remove
local zmq = require 'lzmq'
local zloop = require 'lzmq.loop'
local zassert = zmq.assert
local json=require 'cjson'
local uuid = require 'uuid'
local tablex = require 'pl.tablex'
local stringx = require 'pl.stringx'
stringx.import()
local completer = require 'trepl.completer'
require 'paths'
require 'dok'
local luajit_path = arg[2]
local stdof = arg[3]
local stdef = arg[4]
local context = zmq.context()
-----------------------------------------
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
   if m then o.header.session = m.header.session else o.header.session = '????'; end
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
   o.header.msg_type = 'stream';
   o.header.session = m.header.session;
   o.content = {
      name = stream,
      data = text
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
      protocol_version = {4,0},
      language_version = {jit.version_num},
      language = 'luajit'
   }
   ipyEncodeAndSend(sock, msg);
   iopub_router.status(sock, msg, 'idle');
end

shell_router.shutdown_request = function (sock, msg)
   iopub_router.status(sock, msg, 'busy');
   msg.parent_header = msg.header
   msg.header = tablex.deepcopy(msg.parent_header)
   msg.header.msg_type = 'shutdown_reply';
   msg.header.msg_id = uuid.new();
   ipyEncodeAndSend(sock, msg);
   iopub_router.status(sock, msg, 'idle');
   -- cleanup
   heartbeat:close()
   shell:close()
   control:close()
   stdin:close()
   iopub:close()
   loop:stop()
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


local stdo = io.open(stdof, 'r')
local pos_old = stdo:seek('end')
stdo:close()
shell_router.execute_request = function (sock, msg)
   iopub_router.status(iopub, msg, 'busy');
   local s = session[msg.header.session] or session:create(msg.header.session)
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
      func, perr = loadstring(cmd)
   else
      func, perr = loadstring('local f = function() return '.. line ..' end; local res = {f()}; print(unpack(res))')
      if not func then
	 func, perr = loadstring(cmd)
      end
   end
   if func then
      pok = true
      ok,err = xpcall(func, traceback)
      local stdo = io.open(stdof, 'r')
      stdo:seek('set', pos_old)
      output = stdo:read("*all")
      pos_old = stdo:seek('end')
      stdo:close()
   else
      ok = false;
      err = perr;
   end

   local o = {}
   o.uuid = msg.uuid
   o.parent_header = msg.header
   o.header = tablex.deepcopy(msg.header)
   if not msg.content.silent and msg.content.store_history then
      s.exec_count = s.exec_count + 1; 
      table.insert(s.history.code, msg.content.code);
      table.insert(s.history.output, output);
   end
   -- pyin -- iopub
   o.header.msg_id = uuid.new()
   o.header.msg_type = 'pyin'
   o.content = {
      code = msg.content.code,
      execution_count = s.exec_count
   }
   ipyEncodeAndSend(iopub, o);

   if ok then 
      -- pyout -- iopub
      if not msg.content.silent  and output and output ~= '' then
	 o.header.msg_id = uuid.new()
	 o.header.msg_type = 'pyout'
	 o.content = {
	    data = {},
	    metadata = {},
	    execution_count = s.exec_count
	 }
	 o.content.data['text/plain'] = output
	 ipyEncodeAndSend(iopub, o);
      end
      -- execute_reply -- shell
      o.header.msg_id = uuid.new()
      o.header.msg_type = 'execute_reply'
      o.content = {
	 status = 'ok',
	 execution_count = s.exec_count,
	 payload = {},
	 user_variables = {},
	 user_expressions = {}
      }
      ipyEncodeAndSend(sock, o);
   elseif pok then -- means function execution had error
      -- pyerr -- iopub
      o.header.msg_id = uuid.new()
      o.header.msg_type = 'pyerr'
      o.content = {
	 execution_count = s.exec_count,
	 ename = err or 'Unknown Error',
	 evalue = '',
	 traceback = {err}
      }
      ipyEncodeAndSend(iopub, o);
      -- execute_reply -- shell
      o.header.msg_id = uuid.new()
      o.header.msg_type = 'execute_reply'
      o.content = {
	 status = 'error',
	 execution_count = s.exec_count,
	 ename = err or 'Unknown Error',
	 evalue = '',
	 traceback = {err}
      }
      ipyEncodeAndSend(sock, o);
   else -- code has syntax error
      -- pyerr -- iopub
      o.header.msg_id = uuid.new()
      o.header.msg_type = 'pyerr'
      o.content = {
	 execution_count = s.exec_count,
	 ename = err or 'Unknown Error',
	 evalue = '',
	 traceback = {perr}
      }
      ipyEncodeAndSend(iopub, o);
      -- execute_reply -- shell
      o.header.msg_id = uuid.new()
      o.header.msg_type = 'execute_reply'
      o.content = {
	 status = 'error',
	 execution_count = s.exec_count,
	 ename = err or 'Unknown Error',
	 evalue = '',
	 traceback = {perr}
      }
      ipyEncodeAndSend(sock, o);
   end
   iopub_router.status(iopub, msg, 'idle');
end

shell_router.history_request = function (sock, msg)
   print('WARNING: history_request not handled yet');
end

local function extract_completions(text, line, block, pos)
   -- TODO: if text is empty, go check line for the last word-break character (notebook)
   local l = text
   local word_break_characters = '[" \t\n\"\\\'><=;:%+%-%*/%%^~#{}%(%)%[%],"]'
   local lb = l:gsub(word_break_characters, '.')
   -- extract word
   local word = l
   local prefix = ''
   local h,p = lb:find('.*%.')
   if h then 
      if p == #lb then
	 word = ''
	 prefix = l
      else
	 word = l:sub(p+1);
	 prefix = l:sub(1,p)
      end
   end
   local matches = completer.complete(word, l, nil, nil)
   for i=1,#matches do
      matches[i] = prefix .. matches[i]
   end
   return {
      matches = matches,
      matched_text = prefix, -- line, -- e.g. torch.<TAB> should become torch.abs
      status = 'ok'
   }
end

shell_router.complete_request = function(sock, msg)
   msg.parent_header = msg.header
   msg.header = tablex.deepcopy(msg.parent_header)
   msg.header.msg_type = 'complete_reply';
   msg.header.msg_id = uuid.new();
   msg.content = extract_completions(msg.content.text, msg.content.line, 
				     msg.content.block, msg.content.cursor_pos)
   ipyEncodeAndSend(sock, msg);
end

shell_router.object_info_request = function(sock, msg)
   -- print(msg)
   -- TODO: I dont understand when this thing is called and when it isn't
   --[[
   local c = msg.content
   msg.parent_header = msg.header
   msg.header = tablex.deepcopy(msg.parent_header)
   msg.header.msg_type = 'object_info_reply';
   msg.header.msg_id = uuid.new();
   msg.content = {
      name = c.oname,
      found = true,
      ismagic = false,
      isalias = false,
      namespace = '',
      type_name = '',
      string_form = help(c.oname),
      base_class = '',
      length = '',
      file = '',
      definition = '',
      argspect = {},
      init_definition = '',
      docstring = '',
      class_docstring = '',
      call_docstring = '',
      source = ''
   }
   ipyEncodeAndSend(sock, msg);
   ]]--
end

---------------------------------------------------------------------------
local function handleHeartbeat(sock)
   local m = zassert(sock:recv_all()); zassert(sock:send_all(m))
end

local function handleShell(sock)
   local msg = ipyDecode(sock)
   assert(shell_router[msg.header.msg_type],
	  'Cannot find appropriate message handler for ' .. msg.header.msg_type)
   return shell_router[msg.header.msg_type](sock, msg);
end

local function handleControl(sock)
   local msg = ipyDecode(sock);
   assert(shell_router[msg.header.msg_type],
	  'Cannot find appropriate message handler for ' .. msg.header.msg_type)
   return shell_router[msg.header.msg_type](sock, msg);
end

local function handleStdin(sock)
   print('stdin')
   local buffer = zassert(sock:recv_all())
   zassert(sock:send_all(buffer))
end

local function handleIOPub(sock)
   local msg = ipyDecode(sock);
   assert(iopub_router[msg.header.msg_type],
	  'Cannot find appropriate message handler for ' .. msg.header.msg_type)
   return iopub_router[msg.header.msg_type](sock, msg);
end

iopub_router.status(iopub, nil, 'starting');

loop = zloop.new(1, context)
loop:add_socket(heartbeat, handleHeartbeat)
loop:add_socket(shell, handleShell)
loop:add_socket(control, handleControl)
loop:add_socket(stdin, handleStdin)
loop:add_socket(iopub, handleIOPub)
loop:start()

