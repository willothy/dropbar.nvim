local configs = require('dropbar.configs')
local bar = require('dropbar.bar')

---Get icon, icon highlight and name highlight of a path
---@param path string
---@return string icon
---@return string? icon_hl
---@return string? name_hl
local function get_icon_and_hl(path)
  local icon_kind_opts = configs.opts.icons.kinds
  local icon = icon_kind_opts.symbols.File
  local icon_hl = 'DropBarIconKindFile'
  local name_hl = 'DropBarKindFile'
  local stat = vim.loop.fs_stat(path)
  if not stat then
    return icon, icon_hl
  elseif stat.type == 'directory' then
    icon = icon_kind_opts.symbols.Folder
    icon_hl = 'DropBarIconKindFolder'
    name_hl = 'DropBarKindFolder'
  end
  if icon_kind_opts.use_devicons then
    local devicons_ok, devicons = pcall(require, 'nvim-web-devicons')
    if devicons_ok and stat and stat.type ~= 'directory' then
      local devicon, devicon_hl = devicons.get_icon(
        vim.fs.basename(path),
        vim.fn.fnamemodify(path, ':e'),
        { default = true }
      )
      icon = devicon and devicon .. ' ' or icon
      icon_hl = devicon_hl
    end
  end
  return icon, icon_hl, name_hl
end

---@param self dropbar_symbol_t
local function preview_prepare_buf(self, path)
  local buf
  if vim.uv.fs_stat(path).type == 'directory' then
    -- TODO: preview directory entries
    self:preview_restore_view()
    return
  end
  buf = vim.fn.bufnr(path, false)
  if buf == nil or buf == -1 then
    buf = vim.fn.bufadd(path)
    if not buf then
      self:preview_restore_view()
      return
    end
    if not vim.api.nvim_buf_is_loaded(buf) then
      vim.fn.bufload(buf)
    end
  end
  if buf == nil or self.entry.menu == nil or self.entry.menu.win == nil then
    self:preview_restore_view()
    return
  end
  return buf
end

---@param self dropbar_symbol_t
local function preview_open_float(self, path, icon, icon_hl)
  local preview_buf = preview_prepare_buf(self, path)
  if not preview_buf then
    return
  end

  local function make_title()
    local pat = vim.fs.normalize(
      configs.eval(configs.opts.sources.path.relative_to, preview_buf)
    )
    return {
      { icon, icon_hl },
      {
        vim.api
          .nvim_buf_get_name(preview_buf)
          :gsub('' .. pat .. '/', '')
          :gsub('^' .. pat, ''), -- ':~'
        'NormalFloat',
      },
    }
  end
  if
    self.entry.menu.preview_win == nil
    or vim.api.nvim_win_is_valid(self.entry.menu.preview_win) == false
  then
    self.entry.menu.preview_win = vim.api.nvim_open_win(preview_buf, false, {
      -- relative = 'editor',
      relative = 'win',
      style = 'minimal',
      -- focusable = false,
      width = math.min(80, math.floor(vim.o.columns / 2)),
      height = math.min(25, math.floor(vim.o.lines / 2)),
      row = 0,
      col = vim.api.nvim_win_get_width(self.entry.menu.win) + 1,
      border = 'solid',
      title = make_title(),
    })
    vim.api.nvim_create_autocmd('BufLeave', {
      buffer = self.entry.menu.buf,
      callback = function()
        self:preview_restore_view()
      end,
    })
    vim.schedule(function()
      vim.api.nvim_exec_autocmds(
        'CursorMoved',
        { buffer = self.entry.menu.buf }
      )
    end)
  else
    vim.api.nvim_win_set_buf(self.entry.menu.preview_win, preview_buf)
    local config = vim.api.nvim_win_get_config(self.entry.menu.preview_win)
    config.title = make_title()
    vim.api.nvim_win_set_config(self.entry.menu.preview_win, config)
  end
  local last_exit = vim.api.nvim_buf_get_mark(preview_buf, '"')
  if last_exit[1] ~= 0 then
    vim.api.nvim_win_set_cursor(self.entry.menu.preview_win, last_exit)
  else
    vim.api.nvim_win_set_cursor(self.entry.menu.preview_win, { 1, 0 })
  end
  vim.wo[self.entry.menu.preview_win].winbar = ''
  vim.wo[self.entry.menu.preview_win].stc = ''
  vim.wo[self.entry.menu.preview_win].signcolumn = 'no'
  vim.wo[self.entry.menu.preview_win].number = false
  vim.wo[self.entry.menu.preview_win].relativenumber = false
end

---@param self dropbar_symbol_t
local function preview_close_float(self)
  if
    self.entry.menu.preview_win
    and vim.api.nvim_win_is_valid(self.entry.menu.preview_win)
  then
    vim.api.nvim_win_close(self.entry.menu.preview_win, true)
  end
  self.entry.menu.preview_win = nil
end

---@param self dropbar_symbol_t
local function preview_open_previous(self, path)
  local preview_buf = preview_prepare_buf(self, path)
  if not preview_buf then
    return
  end
  local buflisted = vim.bo[preview_buf].buflisted

  self.entry.menu.preview_win = self.entry.menu:root_win()
  self.entry.menu.prev_buf = self.entry.menu.prev_buf
    or vim.api.nvim_win_get_buf(self.entry.menu.preview_win)

  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = self.entry.menu.buf,
    callback = function()
      self:preview_restore_view()
    end,
  })
  vim.api.nvim_win_set_buf(self.entry.menu.preview_win, preview_buf)
  local last_exit = vim.api.nvim_buf_get_mark(preview_buf, '"')
  if last_exit[1] ~= 0 then
    vim.api.nvim_win_set_cursor(self.entry.menu.preview_win, last_exit)
  end

  vim.bo[preview_buf].buflisted = buflisted
  -- ensure dropbar still shows then the preview buffer is opened
  vim.wo[self.entry.menu.preview_win].winbar =
    '%{%v:lua.dropbar.get_dropbar_str()%}'
end

---@param self dropbar_symbol_t
local function preview_close_previous(self)
  if self.win then
    if self.entry.menu.prev_buf then
      vim.api.nvim_win_set_buf(self.win, self.entry.menu.prev_buf)
    end
    if self.view then
      vim.api.nvim_win_call(self.win, function()
        vim.fn.winrestview(self.view)
      end)
    end
  end
end

---Convert a path to a dropbar symbol
---@param path string full path
---@param buf integer buffer handler
---@param win integer window handler
---@return dropbar_symbol_t
local function convert(path, buf, win)
  local path_opts = configs.opts.sources.path
  local icon, icon_hl, name_hl = get_icon_and_hl(path)

  return bar.dropbar_symbol_t:new(setmetatable({
    buf = buf,
    win = win,
    name = vim.fs.basename(path),
    icon = icon,
    name_hl = name_hl,
    icon_hl = icon_hl,
    ---Override the default jump function
    jump = function(_)
      vim.cmd.edit(path)
    end,
    preview = vim.schedule_wrap(function(self)
      if path_opts.preview == 'previous' then
        preview_open_previous(self, path)
      else
        preview_open_float(self, path, icon, icon_hl)
      end
    end),
    preview_restore_view = function(self)
      if path_opts.preview == 'previous' then
        preview_close_previous(self)
      else
        preview_close_float(self)
      end
    end,
  }, {
    ---@param self dropbar_symbol_t
    __index = function(self, k)
      if k == 'children' then
        self.children = {}
        for name in vim.fs.dir(path) do
          if path_opts.filter(name) then
            table.insert(self.children, convert(path .. '/' .. name, buf, win))
          end
        end
        return self.children
      end
      if k == 'siblings' or k == 'sibling_idx' then
        local parent_dir = vim.fs.dirname(path)
        self.siblings = {}
        self.sibling_idx = 1
        if parent_dir then
          for idx, name in vim.iter(vim.fs.dir(parent_dir)):enumerate() do
            if path_opts.filter(name) then
              table.insert(
                self.siblings,
                convert(parent_dir .. '/' .. name, buf, win)
              )
              if name == self.name then
                self.sibling_idx = idx
              end
            end
          end
        end
        return self[k]
      end
    end,
  }))
end

---Get list of dropbar symbols of the parent directories of given buffer
---@param buf integer buffer handler
---@param win integer window handler
---@param _ integer[] cursor position, ignored
---@return dropbar_symbol_t[] dropbar symbols
local function get_symbols(buf, win, _)
  local path_opts = configs.opts.sources.path
  local symbols = {} ---@type dropbar_symbol_t[]
  local current_path = vim.fs.normalize((vim.api.nvim_buf_get_name(buf)))
  local root = vim.fs.normalize(configs.eval(path_opts.relative_to, buf, win))
  while
    current_path
    and current_path ~= '.'
    and current_path ~= root
    and current_path ~= vim.fs.dirname(current_path)
  do
    table.insert(symbols, 1, convert(current_path, buf, win))
    current_path = vim.fs.dirname(current_path)
  end
  if vim.bo[buf].mod then
    symbols[#symbols] = path_opts.modified(symbols[#symbols])
  end
  return symbols
end

return {
  get_symbols = get_symbols,
}
