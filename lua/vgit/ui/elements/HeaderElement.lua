local Namespace = require('vgit.core.Namespace')
local Buffer = require('vgit.core.Buffer')
local Window = require('vgit.core.Window')
local Object = require('vgit.core.Object')

local HeaderElement = Object:extend()

function HeaderElement:new()
  return setmetatable({
    buffer = nil,
    window = nil,
    namespace = nil,
  }, HeaderElement)
end

function HeaderElement:mount(options)
  self.buffer = Buffer:new():create()
  local buffer = self.buffer
  buffer:assign_options({
    modifiable = false,
    buflisted = false,
    bufhidden = 'wipe',
  })
  self.window = Window
    :open(buffer, {
      style = 'minimal',
      focusable = false,
      relative = 'editor',
      row = options.row - HeaderElement:get_height(),
      col = options.col,
      width = options.width,
      height = 1,
      zindex = 100,
    })
    :assign_options({
      cursorbind = false,
      scrollbind = false,
      winhl = 'Normal:GitBackgroundSecondary',
    })
  self.namespace = Namespace:new()
  return self
end

function HeaderElement:get_height()
  return 1
end

function HeaderElement:unmount()
  self.window:close()
  return self
end

function HeaderElement:set_lines(lines)
  self.buffer:set_lines(lines)
  return self
end

function HeaderElement:add_highlight(hl, row, col_start, col_end)
  self.buffer:add_highlight(hl, row, col_start, col_end)
  return self
end

function HeaderElement:transpose_virtual_text(text, hl, row, col, pos)
  self.buffer:transpose_virtual_text(text, hl, row, col, pos)
  return self
end

function HeaderElement:clear_namespace()
  self.buffer:clear_namespace()
  return self
end

function HeaderElement:trigger_notification(text)
  self.namespace:transpose_virtual_text(
    self.buffer,
    text,
    'GitComment',
    0,
    0,
    'eol'
  )
  return self
end

function HeaderElement:clear_notification()
  if self.buffer:is_valid() then
    self.namespace:clear(self.buffer)
  end
  return self
end

function HeaderElement:clear()
  self:set_lines({})
  self:clear_namespace()
  return self
end

return HeaderElement
