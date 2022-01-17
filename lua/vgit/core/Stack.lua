local Object = require('vgit.core.Object')

local Stack = Object:extend()

function Stack:new()
  return setmetatable({
    items = {},
  }, Stack)
end

function Stack:push(ele)
  self.items[#self.items + 1] = ele
  return self
end

function Stack:pop()
  local ele = self.items[#self.items]
  self.items[#self.items] = nil
  return ele
end

function Stack:size()
  return #self.items
end

function Stack:is_empty()
  return self:size() == 0
end

return Stack
