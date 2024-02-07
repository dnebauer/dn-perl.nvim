-- DOCUMENTATION

---@brief [[
---*dn-perl-nvim.txt*  For Neovim version 0.9  Last change: 2024 February 07
---@brief ]]

---@toc dn_perl.contents

---@mod dn_perl.intro Introduction
---@brief [[
---An auxiliary perl5 plugin providing customised |K|-type help mapped to "L"
---in normal and visual modes
---@brief ]]

---@mod dn_perl.depend Dependencies
---@brief [[
---This ftplugin depends on the dn-utils plugin
---(https://github.com/dnebauer/dn-utils.nvim).
---@brief ]]

---@mod dn_perl.features Features
---@brief [[
---Customised K-style help mapped to "L" ~
---
---In a modern, properly configured nvim with a perl |LSP| language server
---running, the |K| mapping is used by the language server to provide hover
---information (see |vim.lsp.buf.hover()|).
---
---For that reason K-like functionality is provided by the "L" key in normal
---and visual modes. The result is displayed in a floating window, similar
---to how a language server displays hover information, except that the
---window content is displayed without syntax highlighting.
---
---Before language servers the usual K behaviour, which was provided by
---'keywordprg', was to look in perldoc's function help with the command:
--->
---  perldoc -f X
---<
---where "X" was the search term.
---
---The functionality this ftplugin provides for "L" is to look sequentially
---in perldoc's function, variable, general and faq help. It is the
---equivalent of running the shell command:
--->
---  perldoc -f X || perldoc -v X || perldoc X || perldoc -q X
---<
---@brief ]]

local dn_perl = {}

-- PRIVATE VARIABLES

-- only load module once
if vim.g.dn_perl_loaded then
  return
end
vim.g.dn_perl_loaded = true

local util = require("dn-utils")

-- PRIVATE FUNCTIONS

-- PUBLIC FUNCTIONS

---@mod dn_perl.functions Functions

-- perldoc_help()

---Gets the search term from selected text, if in visual mode, or from the
---|<cword>| under the cursor, if in normal mode.
---
---Then check sequentially in perl function, variable, general and faq help
---for documentation on the search term. The first successful search is
---accepted and the output captured. Note: while search terms may contain
---spaces, punctuation and even newlines in visual mode, such search terms
---are unlikely to retrieve information.
---
---If information on the desired term is retrieved it is displayed in a
---floating window with <CR> and <Esc> keys mapped to close the display
---window.
---
---If no information is retrieved on the search term a notification to that
---effect is displayed.
---@return nil _ No return value
function dn_perl.perldoc_help()
  -- obtain search term
  local term
  if util.in_visual_mode() then
    term = util.visual_selection()
  else
    term = vim.fn.expand("<cword>")
  end
  -- • an empty line can be a <cWORD> --
  --   not sure about <cword> but why take a chance?
  if term:match("^%s*$") ~= nil then
    return
  end
  -- get perldoc help
  local cmds = { { "perldoc", "-f" }, { "perldoc", "-v" }, { "perldoc" }, { "perldoc", "-q" } }
  local matched = false
  local output
  for _, cmd in ipairs(cmds) do
    table.insert(cmd, util.shell_escape(term))
    local ret = util.execute_shell_command(unpack(cmd))
    if ret.exit_status == 0 then
      matched = true
      output = ret.stdout
      break
    end
  end
  if not matched then
    vim.notify("No information available", vim.log.levels.INFO)
    return
  end
  -- display help text in floating window
  local lines = util.split(output, "\n")
  local opts = { relative = "editor", row = 1, col = 0 }
  util.floating_window(lines, opts)
end

-- MAPPINGS

---@mod dn_perl.mappings Mappings

-- L [n,v]

---@tag dn_perl.L
---@brief [[
---L ~
---
---Display perldoc help for search term under cursor or highlighted.
---Works in normal and visual modes.
---@brief ]]
vim.keymap.set({ "n", "v" }, "L", function()
  dn_perl.perldoc_help()
end, { buffer = true, desc = "Display perldoc help for search term" })

return dn_perl
