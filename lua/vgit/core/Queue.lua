local Object = require('vgit.core.Object')

local Queue = Object:extend()

function Queue:new()
  return setmetatable({
    items = {},
    current_key = 1,
    lowest_key = 1,
  }, Queue)
end

function Queue:enqueue(ele)
  self.items[self.current_key] = ele
  self.current_key = self.current_key + 1
  return self
end

function Queue:dequeue()
  local value = self.items[self.lowest_key]
  self.items[self.lowest_key] = nil
  self.lowest_key = self.lowest_key + 1
  return value
end

function Queue:size()
  return self.current_key - self.lowest_key
end

function Queue:is_empty()
  return self:size() == 0
end

return Queue
