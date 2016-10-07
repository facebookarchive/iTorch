--[[
 *  Copyright (c) 2015, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant 
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
]]--
itorch=require 'itorch._env'
require 'itorch.gfx'
require 'itorch.bokeh'
itorch.Plot=require 'itorch.Plot'

local _class = torch.class
torch.class = function(name, parentName, module)
  if name ~= nil then
    debug.getregistry()[name] = nil
  end
  if module ~= nil then
    return _class(name, parentName, module)
  elseif parentName ~= nil then
    return _class(name, parentName)
  else
    return _class(name)
  end
end

return itorch

