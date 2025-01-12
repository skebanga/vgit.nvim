local icons = require('vgit.core.icons')
local Window = require('vgit.core.Window')
local loop = require('vgit.core.loop')
local utils = require('vgit.core.utils')
local CodeComponent = require('vgit.ui.components.CodeComponent')
local TableComponent = require('vgit.ui.components.TableComponent')
local CodeDataScreen = require('vgit.ui.screens.CodeDataScreen')
local Scene = require('vgit.ui.Scene')
local dimensions = require('vgit.ui.dimensions')
local console = require('vgit.core.console')
local fs = require('vgit.core.fs')
local Diff = require('vgit.Diff')

local ProjectHunksScreen = CodeDataScreen:extend()

function ProjectHunksScreen:new(...)
  return setmetatable(CodeDataScreen:new(...), ProjectHunksScreen)
end

function ProjectHunksScreen:fetch()
  local git = self.git
  local runtime_cache = self.runtime_cache
  runtime_cache.entries = {}
  local entries = runtime_cache.entries
  local changed_files_err, changed_files = git:ls_changed()
  if changed_files_err then
    console.debug(changed_files_err, debug.traceback())
    runtime_cache.err = changed_files_err
    return self
  end
  if #changed_files == 0 then
    console.debug({ 'No changes found' }, debug.traceback())
    return self
  end
  for i = 1, #changed_files do
    local file = changed_files[i]
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
      runtime_cache.err = lines_err
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
      runtime_cache.err = hunks_err
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
    if not hunks_err then
      for j = 1, #hunks do
        local hunk = hunks[j]
        entries[#entries + 1] = {
          hunk = hunk,
          hunks = hunks,
          filename = filename,
          filetype = fs.detect_filetype(filename),
          dto = dto,
          index = j,
        }
      end
    else
      console.debug(hunks_err, debug.traceback())
    end
  end
  runtime_cache.entries = entries
  return self
end

function ProjectHunksScreen:get_unified_scene_options(options)
  local table_height = math.floor(dimensions.global_height() * 0.15)
  return {
    current = CodeComponent:new(utils.object.assign({
      config = {
        win_options = {
          cursorbind = true,
          scrollbind = true,
          cursorline = true,
        },
        window_props = {
          height = dimensions.global_height() - table_height,
          row = table_height,
        },
      },
    }, options)),
    table = TableComponent:new(utils.object.assign({
      header = { 'Filename', 'Hunk' },
      config = {
        window_props = {
          height = table_height,
          row = 0,
        },
      },
    }, options)),
  }
end

function ProjectHunksScreen:get_split_scene_options(options)
  local table_height = math.floor(dimensions.global_height() * 0.15)
  return {
    previous = CodeComponent:new(utils.object.assign({
      config = {
        win_options = {
          cursorbind = true,
          scrollbind = true,
          cursorline = true,
        },
        window_props = {
          height = dimensions.global_height() - table_height,
          width = math.floor(dimensions.global_width() / 2),
          row = table_height,
        },
      },
    }, options)),
    current = CodeComponent:new(utils.object.assign({
      config = {
        win_options = {
          cursorbind = true,
          scrollbind = true,
          cursorline = true,
        },
        window_props = {
          height = dimensions.global_height() - table_height,
          width = math.floor(dimensions.global_width() / 2),
          col = math.floor(dimensions.global_width() / 2),
          row = table_height,
        },
      },
    }, options)),
    table = TableComponent:new(utils.object.assign({
      header = { 'Filename', 'Hunk' },
      config = {
        window_props = {
          height = table_height,
          row = 0,
        },
      },
    }, options)),
  }
end

ProjectHunksScreen.update = loop.brakecheck(loop.async(function(self, selected)
  local runtime_cache = self.runtime_cache
  self.runtime_cache.last_selected = selected
  self.runtime_cache.data = runtime_cache.entries[selected]
  local data = runtime_cache.data
  loop.await_fast_event()
  self
    :reset()
    :set_title(runtime_cache.title, {
      filename = data.filename,
      filetype = data.filetype,
      stat = data.dto.stat,
    })
    :make_code()
    :paint_code_partially()
    :set_code_cursor_on_mark(data.index, 'top')
    :notify(
      string.format(
        '%s%s/%s Changes',
        string.rep(' ', 1),
        data.index,
        #data.dto.marks
      )
    )
end))

function ProjectHunksScreen:open_file()
  local table = self.scene.components.table
  loop.await_fast_event()
  local selected = table:get_lnum()
  if self.runtime_cache.last_selected == selected then
    local data = self.runtime_cache.data
    self:hide()
    vim.cmd(string.format('e %s', data.filename))
    Window:new(0):set_lnum(data.hunks[data.index].top):call(function()
      vim.cmd('norm! zz')
    end)
    return self
  end
  self:update(selected)
end

function ProjectHunksScreen:make_table()
  self.scene.components.table
    :unlock()
    :make_rows(self.runtime_cache.entries, function(entry)
      local filename = entry.filename
      local filetype = entry.filetype
      local icon, icon_hl = icons.file_icon(filename, filetype)
      if icon then
        return {
          {
            icon_before = {
              icon = icon,
              hl = icon_hl,
            },
            text = filename,
          },
          string.format('%s/%s', entry.index, #entry.dto.marks),
        }
      end
      return {
        {
          text = filename,
        },
        string.format('%s/%s', entry.index, #entry.dto.marks),
      }
    end)
    :set_keymap('n', 'j', 'on_j')
    :set_keymap('n', 'J', 'on_j')
    :set_keymap('n', 'k', 'on_k')
    :set_keymap('n', 'K', 'on_k')
    :set_keymap('n', '<enter>', 'on_enter')
    :focus()
    :lock()
  return self
end

function ProjectHunksScreen:show(title, options)
  local is_inside_git_dir = self.git:is_inside_git_dir()
  if not is_inside_git_dir then
    console.log('Project has no git folder')
    console.debug(
      'project_hunks_preview is disabled, we are not in git store anymore'
    )
    return false
  end
  self:hide()
  local runtime_cache = self.runtime_cache
  runtime_cache.title = title
  runtime_cache.options = options
  console.log('Processing project hunks')
  self:fetch()
  loop.await_fast_event()
  if
    not runtime_cache.err
    and runtime_cache.entries
    and #runtime_cache.entries == 0
  then
    console.log('No hunks found')
    return false
  end
  if runtime_cache.err then
    console.error(runtime_cache.err)
    return false
  end
  self.scene = Scene:new(self:get_scene_options(options)):mount()
  runtime_cache.data = runtime_cache.entries[1]
  self
    :set_title(title, {
      filename = runtime_cache.data.filename,
      filetype = runtime_cache.data.filetype,
      stat = runtime_cache.data.dto.stat,
    })
    :make_code()
    :make_table()
    :set_code_cursor_on_mark(1, 'top')
    :paint_code()
  -- Must be after initial fetch
  runtime_cache.last_selected = 1
  console.clear()
  return true
end

return ProjectHunksScreen
