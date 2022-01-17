local console = require('vgit.core.console')
local loop = require('vgit.core.loop')
local CodeScreen = require('vgit.ui.screens.CodeScreen')

local CodeDataScreen = CodeScreen:extend()

function CodeDataScreen:new(...)
  return setmetatable(CodeScreen:new(...), CodeDataScreen)
end

CodeDataScreen.update = loop.brakecheck(loop.async(function(self, selected)
  local state = self.state
  state.last_selected = selected
  self:fetch(selected)
  loop.await_fast_event()
  if state.err then
    console.error(state.err)
    return self
  end
  if
    not state.data and not state.data
    or not state.data.dto
  then
    return
  end
  self
    :reset()
    :set_title(state.title, {
      filename = state.data.filename,
      filetype = state.data.filetype,
      stat = state.data.dto.stat,
    })
    :make_code()
    :paint_code_partially()
    :set_code_cursor_on_mark(1)
end))

function CodeDataScreen:table_move(direction)
  self:clear_stated_err()
  local components = self.scene.components
  local table = components.table
  loop.await_fast_event()
  local selected = table:get_lnum()
  if direction == 'up' then
    selected = selected - 1
  elseif direction == 'down' then
    selected = selected + 1
  end
  local total_line_count = table:get_line_count()
  if selected > total_line_count then
    selected = 1
  elseif selected < 1 then
    selected = total_line_count
  end
  if self.state.last_selected == selected then
    return
  end
  loop.await_fast_event()
  table:unlock():set_lnum(selected):lock()
  self:update(selected)
end

return CodeDataScreen
