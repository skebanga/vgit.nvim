local Window = require('vgit.core.Window')
local utils = require('vgit.core.utils')
local loop = require('vgit.core.loop')
local CodeComponent = require('vgit.ui.components.CodeComponent')
local HeaderComponent = require('vgit.ui.components.HeaderComponent')
local FoldableListComponent = require('vgit.ui.components.FoldedListComponent')
local CodeDataScreen = require('vgit.ui.screens.CodeDataScreen')
local Scene = require('vgit.ui.Scene')
local console = require('vgit.core.console')
local fs = require('vgit.core.fs')
local Diff = require('vgit.Diff')

local ProjectDiffScreen = CodeDataScreen:extend()

function ProjectDiffScreen:new(...)
  return setmetatable(CodeDataScreen:new(...), ProjectDiffScreen)
end

function ProjectDiffScreen:fetch(selected)
  selected = selected or 1
  local state = self.state
  local git = self.git
  local changed_files_err, changed_files = git:ls_changed()
  if changed_files_err then
    console.debug(changed_files_err, debug.traceback())
    state.err = changed_files_err
    return self
  end
  if #changed_files == 0 then
    state.data = {
      changed_files = changed_files,
      selected = selected,
    }
    return self
  end
  local file = changed_files[selected]
  if not file then
    selected = #changed_files
    file = changed_files[selected]
  end
  local filename = file.filename
  local status = file.status
  local lines_err, lines
  if status:has('D ') then
    lines_err, lines = git:show(filename, 'HEAD')
  elseif status:has(' D') then
    lines_err, lines = git:show(git:tracked_filename(filename))
  else
    lines_err, lines = fs.read_file(filename)
  end
  if lines_err then
    console.debug(lines_err, debug.traceback())
    state.err = lines_err
    return self
  end
  local hunks_err, hunks
  if status:has_both('??') then
    hunks = git:untracked_hunks(lines)
  elseif status:has_either('DD') then
    hunks = git:deleted_hunks(lines)
  else
    hunks_err, hunks = git:index_hunks(filename)
  end
  if hunks_err then
    console.debug(hunks_err, debug.traceback())
    state.err = hunks_err
    return self
  end
  local dto
  if self.layout_type == 'unified' then
    if status:has_either('DD') then
      dto = Diff:new(hunks):deleted_unified(lines)
    else
      dto = Diff:new(hunks):unified(lines)
    end
  else
    if status:has_either('DD') then
      dto = Diff:new(hunks):deleted_split(lines)
    else
      dto = Diff:new(hunks):split(lines)
    end
  end
  state.data = {
    filename = filename,
    filetype = fs.detect_filetype(filename),
    changed_files = changed_files,
    dto = dto,
    selected = selected,
  }
  return self
end

function ProjectDiffScreen:get_unified_scene_definition()
  return {
    header = HeaderComponent:new({
      config = {
        win_plot = {
          width = '100vw',
        },
      },
    }),
    current = CodeComponent:new({
      config = {
        elements = {
          header = false,
          horizontal_border = false,
        },
        win_options = {
          cursorbind = true,
          scrollbind = true,
          cursorline = true,
        },
        win_plot = {
          row = HeaderComponent:get_height(),
          height = '100vh',
          width = '80vw',
          col = '20vw',
        },
      },
    }),
    table = FoldableListComponent:new({
      config = {
        elements = {
          header = false,
          horizontal_border = false,
        },
        win_plot = {
          row = HeaderComponent:get_height(),
          height = '100vh',
          width = '20vw',
        },
      },
    }),
  }
end

function ProjectDiffScreen:get_split_scene_definition(props)
  return {
    header = HeaderComponent:new(utils.object.assign({
      config = {
        win_plot = {
          width = '100vw',
        },
      },
    }, props)),
    previous = CodeComponent:new(utils.object.assign({
      config = {
        elements = {
          header = false,
          horizontal_border = false,
        },
        win_options = {
          cursorbind = true,
          scrollbind = true,
          cursorline = true,
        },
        win_plot = {
          row = HeaderComponent:get_height(),
          height = '100vh',
          width = '40vw',
          col = '20vw',
        },
      },
    }, props)),
    current = CodeComponent:new(utils.object.assign({
      config = {
        elements = {
          header = false,
          horizontal_border = false,
        },
        win_options = {
          cursorbind = true,
          scrollbind = true,
          cursorline = true,
        },
        win_plot = {
          row = HeaderComponent:get_height(),
          height = '100vh',
          width = '40vw',
          col = '60vw',
        },
      },
    }, props)),
    table = FoldableListComponent:new(utils.object.assign({
      config = {
        elements = {
          header = false,
          horizontal_border = false,
        },
        win_plot = {
          row = HeaderComponent:get_height(),
          height = '100vh',
          width = '20vw',
        },
      },
    }, props)),
  }
end

function ProjectDiffScreen:run_command(command) end

function ProjectDiffScreen:refresh()
  self:run_command()
  return self
end

function ProjectDiffScreen:git_reset()
  return self:run_command(function(filename)
    return self.git:reset(filename)
  end)
end

function ProjectDiffScreen:git_stage()
  return self:run_command(function(filename)
    return self.git:stage_file(filename)
  end)
end

function ProjectDiffScreen:git_unstage()
  return self:run_command(function(filename)
    return self.git:unstage_file(filename)
  end)
end

function ProjectDiffScreen:table_move(direction)
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
  loop.await_fast_event()
  table:unlock():set_lnum(selected):lock()
  local lnum = table:get_lnum()
  local item = table:get_list_item(lnum)
  local state = self.state
  local last_selected = state.last_selected
  if item.lnum and last_selected ~= item.lnum then
    state.last_selected = last_selected
    self:update(item.lnum)
  end
  return self
end

function ProjectDiffScreen:open_file()
  local components = self.scene.components
  local table = components.table
  loop.await_fast_event()
  local item = table:get_list_item(table:get_lnum())
  local selected = item.lnum
  local focused_component_name = self.scene:get_focused_component_name()
  local is_in_code_window = focused_component_name == 'current'
    or focused_component_name == 'previous'
  if not is_in_code_window then
    table:toggle_list_item(item)
    table:render()
    if not selected then
      return self
    end
  end
  local state = self.state
  selected = selected or state.data.selected
  if selected and state.last_selected == selected then
    local data = state.data
    local dto = data.dto
    local marks = dto.marks
    local filename = data.changed_files[selected].filename
    local mark = marks[state.mark_index]
    if is_in_code_window then
      local component = components[focused_component_name]
      loop.await_fast_event()
      local current_lnum = component:get_lnum()
      for i = 1, #marks do
        local current_mark = marks[i]
        if
          current_lnum >= current_mark.top
          and current_lnum <= current_mark.bot
        then
          mark = current_mark
          break
        end
      end
    end
    local lnum = mark and mark.top_lnum
    self:hide()
    vim.cmd(string.format('e %s', filename))
    if lnum then
      Window:new(0):set_lnum(lnum):call(function()
        vim.cmd('norm! zz')
      end)
    end
  end
end

function ProjectDiffScreen:define_foldable_list()
  local foldable_list = {
    {
      value = 'Changes',
      open = true,
      items = {},
    },
  }
  local changed_files = self.state.data.changed_files
  local changes_fold = foldable_list[1].items
  for i = 1, #changed_files do
    local file = changed_files[i]
    changes_fold[#changes_fold + 1] = {
      value = string.format(
        '%s %s',
        fs.short_filename(file.filename),
        file.status:to_string()
      ),
      lnum = i,
    }
  end
  return foldable_list
end

function ProjectDiffScreen:make_table()
  self.scene.components.table
    :unlock()
    :define(self:define_foldable_list())
    :set_keymap('n', 'j', 'on_j')
    :set_keymap('n', 'J', 'on_j')
    :set_keymap('n', 'k', 'on_k')
    :set_keymap('n', 'K', 'on_k')
    :set_keymap('n', '<enter>', 'on_enter')
    :render()
    :focus()
    :lock()
  return self
end

function ProjectDiffScreen:set_code_keymap(mode, key, action)
  local components = self.scene.components
  components.current:set_keymap(mode, key, action)
  if self.layout_type == 'split' then
    components.previous:set_keymap(mode, key, action)
  end
  return self
end

function ProjectDiffScreen:show(title, props)
  local is_inside_git_dir = self.git:is_inside_git_dir()
  if not is_inside_git_dir then
    console.log('Project has no git folder')
    console.debug(
      'project_diff_preview is disabled, we are not in git store anymore'
    )
    return false
  end
  self:hide()
  local state = self.state
  state.title = title
  state.props = props
  console.log('Processing project diff')
  self:fetch()
  loop.await_fast_event()
  if not state.err and state.data and #state.data.changed_files == 0 then
    console.log('No changes found')
    return false
  end
  if state.err then
    console.error(state.err)
    return false
  end
  self.scene = Scene:new(self:get_scene_definition(props)):mount()
  local data = state.data
  local filename = data.filename
  local filetype = data.filetype
  self
    :set_title(title, {
      filename = filename,
      filetype = filetype,
      stat = data.dto.stat,
    })
    :make_code()
    :make_table()
    :set_code_cursor_on_mark(1)
    :set_code_keymap('n', '<enter>', 'on_enter')
    :paint_code()
  -- Must be after initial fetch
  state.last_selected = 1
  console.clear()
  return true
end

return ProjectDiffScreen
