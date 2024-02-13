-- DOCUMENTATION

---@brief [[
---*dn-perl-nvim.txt*  For Neovim version 0.9  Last change: 2024 February 07
---@brief ]]

---@toc dn_perl.contents

---@mod dn_perl.intro Introduction
---@brief [[
---An auxiliary perl5 plugin that:
---• provides customised |K|-type help mapped to "L" in normal and visual
---  modes
---• inserts a Perl::Critic policy name after the cursor.
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
---
---Insert a Perl::Critic policy name ~
---
---The user selects a Perl::Critic policy from a menu and the minor part of
---the name (the part after the "::") is inserted after the cursor.
---@brief ]]

local dn_perl = {}

-- PRIVATE VARIABLES

-- only load module once
if vim.g.dn_perl_loaded then
	return
end
vim.g.dn_perl_loaded = true

local sf = string.format
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

-- insert_policy_name()

---Select a Perl::Critic policy and insert the minor part (after the "::"
---separator) after the cursor. (This means it is not possible to insert the
---minor part at the beginning of a line.)
---
---Requires that the "perlcritic" executable distributed with perl module
---Perl::Critic is available.
---@return nil _ No return value
function dn_perl.insert_policy_name()
	-- prompt
	local prompt = "Select the policy name to insert"
	-- action on policy selection
	local action = function(policy)
		local major, minor = policy:match("^([^:]+)::([^:]+)$")
		if major == nil or minor == nil then
			error(sf("Unable to parse policy '%s'", policy))
		end
		-- for unknown reason the telescope menu shifts the cursor 1 character to
		-- the right, so this means nvim_put() inserts 1 character too far to the
		-- right, so instead manipulate the line of text directly
		--vim.api.nvim_put({ minor }, "c", false, true)
		local current_line = vim.api.nvim_get_current_line()
		local row, col = unpack(vim.api.nvim_win_get_cursor(0))
		col = col - 1 -- reverse the telescope rightward cursor shift
		local to_cursor = current_line:sub(1, col + 1)
		local after_cursor = current_line:sub(col + 2)
		local replacement_line = to_cursor .. minor .. after_cursor
		vim.api.nvim_buf_set_lines(0, row - 1, row, true, { replacement_line })
		local new_col = col + minor:len() + 2
		vim.api.nvim_win_set_cursor(0, { row, new_col })
	end
	-- policy list (cached in vim.b.dn_perl_critic_policies)
	local ok, policies = pcall(vim.api.nvim_buf_get_var, 0, "dn_perl_critic_policies")
	if not ok then
		-- need to generate list with perlcritic
		local perlcritic = "perlcritic"
		if vim.fn.executable(perlcritic) ~= 1 then
			util.error(sf("Unable to locate '%s' - is it installed?", perlcritic))
			return
		end
		local ret = util.execute_shell_command("perlcritic", "-list")
		if ret.exit_status ~= 0 then
			util.error(ret.stderr)
			return
		end
		-- get lines of output
		local output = util.split(ret.stdout, "\n")
		-- extract policy name from each line
		policies = vim.tbl_map(function(line)
			local policy = line:match("^%d%s+(%S+)")
			return policy
		end, output)
		-- set cache variable
		vim.api.nvim_buf_set_var(0, "dn_perl_critic_policies", policies)
	end
	-- call picker
	util.picker(policies, action, prompt)
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

-- \pc [n]

---@tag dn_perl.<Leader>pc
---@brief [[
---This mapping calls the function |dn_perl.insert_policy_name| in mode "n".
---@brief ]]
vim.keymap.set({ "n" }, "<Leader>pc", dn_perl.insert_policy_name, { desc = "Insert a Perl::Critic policy name" })

-- COMMANDS

---@mod dn_perl.commands Commands

-- InsertPerlCriticPolicyName

---@tag dn_perl.InsertPerlCriticPolicyName
---@brief [[
---User selects a Perl::Critic policy and the policy name is inserted at the
---cursor location.
---@brief ]]
vim.api.nvim_create_user_command("InsertPerlCriticPolicyName", function()
	dn_perl.insert_policy_name()
end, { desc = "Insert a Perl::Critic policy name" })

return dn_perl
