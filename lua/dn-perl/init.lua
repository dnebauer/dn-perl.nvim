-- DOCUMENTATION

---@brief [[
---*dn-perl-nvim.txt*  For Neovim version 0.9  Last change: 2024 January 15
---@brief ]]

---@toc dn_perl.contents

---@mod dn_perl.intro Introduction
---@brief [[
---An auxiliary perl5 plugin providing:
---• a custom version of the "perlcritic" script
---• customised K help.
---@brief ]]

---@mod dn_perl.depend Dependencies
---@brief [[
---This ftplugin depends on:
---• the dn-utils plugin (https://github.com/dnebauer/dn-utils.nvim)
---• the executable "perlcritic" provided as part of the Perl::Critic perl
---  module (https://metacpan.org/pod/Perl::Critic).
---@brief ]]

---@mod dn_perl.features Features
---@brief [[
---Perlcritic ~
---
---Perl::Critic is a perl module that critiques perl source code for best
---practices. The module can analyse code with varying degress of strictness,
---referred to as severity. The 5 levels of severity are:
---• 5 (gentle)
---• 4 (stern)
---• 3 (harsh)
---• 2 (cruel)
---• 1 (brutal).
---
---The Perl::Critic module provides a convenience script called
---"perlcritic" which is used by this ftplugin. It can be run on the current
---file using:
---• function |dn_perl.critic|
---• command |dn_perl.Critic|
---• mappings |dn_perl.<Leader>c1| to |dn_perl.<Leader>c5|, usually "\c1"
---  to "\c5".
---
---The feedback from perlcritic is displayed in a |location-list|.
---
---Note that perlcritic is not run on the contents of the buffer, but on the
---associated file, so the buffer must be associated with a file. The buffer
---is automatically saved before running perlcritic to ensure it is run on
---the current contents of the buffer.
---
---K looks in more locations for help ~
---
---Change |K| by changing value of 'keywordprg'. Alter default behaviour of
---looking in function help:
--->
---  perldoc -f X
---<
---to look sequentially in function, variable, general and faq help:
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

local sf = string.format
local util = require("dn-utils")

-- PRIVATE FUNCTIONS

-- forward declarations
local _complete_critic_severity

-- _completeCriticSeverity(arg, line, pos)

---@private
---Custom command completion for perlcritic severity values, accepting the
---required arguments of {arg}, {line}, and {pos} although they are not used
---(see |:command-completion-customlist|).
---@param arg string See |:command-completion-customlist| help for "ArgLead"
---@param line string See |:command-completion-customlist| help for "CmdLine"
---@param pos integer See |:command-completion-customlist| help for "CursorPos"
---@return table _ List of severity values:
---• 5=gentle
---• 4=stern
---• 3=harsh
---• 2=cruel
---• 1=brutal
_complete_critic_severity = function(arg, line, pos)
	local _ = { line, pos } -- avoid "unused local '{line,pos}'" errors
	local levels = { "5=gentle", "4=stern", "3=harsh", "2=cruel", "1=brutal" }
	return vim.tbl_filter(function(item)
		return item:match(arg)
	end, levels)
end

-- PUBLIC FUNCTIONS

---@mod dn_perl.functions Functions

-- critic(severity)

---Runs perlcritic and opens provided feedback in a |location-list|.
---@param severity integer|string Severity level from 5 (gentle) to
---1 (harsh), assumed to be an integer from
---1-5 or a string whose first character is
---an integer from 1-5, such as "5=gentle"
---@return boolean _ Indicates whether perlcritic was run successfully
function dn_perl.critic(severity)
	-- process param
	local level
	local arg_type = type(severity)
	if arg_type == "string" then
		-- assume string like "5=gentle" whose first char is an integer 1-5
		local first_char = severity:sub(1, 1)
		level = tonumber(first_char)
		if level == nil then
			util.error(sf("Invalid severity '%s'", severity))
			return false
		end
		if not util.valid_pos_int(level) then
			util.error(sf("First character '%s' is not an integer", first_char))
			return false
		end
	elseif arg_type == "number" then
		level = severity
		if not util.valid_pos_int(level) then
			util.error(sf("Severity (%s) is not an integer", tostring(level)))
			return false
		end
	else
		util.error(sf("Invalid severity data type: %s", arg_type))
		return false
	end
	if level < 1 or level > 5 then
		util.error(sf("Severity level (%d) out of range 1-5", level))
		return false
	end
	-- get filepath
	local fp = vim.api.nvim_buf_get_name(0)
	if fp:len() == 0 then
		util.error("Must be a file associated with the buffer to run perlcritic")
		return false
	end
	-- update file contents
	vim.api.nvim_cmd({ cmd = "update" }, {})
	-- run perlcritic and capture output
	local critic = "perlcritic"
	if vim.fn.executable(critic) ~= 1 then
		util.error(sf("Unable to run %s - is it installed?", critic))
		return false
	end
	-- • because perlcritic can take a long time to run on a large file, I
	--   would like to notify user here that perlcritic is running;
	--   unfortunately all attempts (vim.cmd.echo, print, vim.print, util.info)
	--   only display after perlcritic has completed; this occurs even if
	--   Noice is disabled
	local result = util.execute_shell_command(critic, "--severity", level, fp)
	-- • cannot check exit status because perlcritic has previously exited with
	--   this error even when successful:
	--   "Tests were run but no plan was declared and done_testing()
	--    was not seen."
	--   There is currently no known way to determine whether perlcritic
	--   succeeded, so let's just assume it did
	local output = util.split(result.stdout, "\n")
	output = util.table_remove_empty_end_items(output)
	if vim.tbl_isempty(output) then
		util.info("Perlcritic reported no errors or warnings")
		return true
	end
	-- convert output into location list input
	local bufnr = vim.api.nvim_win_get_buf(0)
	-- • initially save list items to nested dicts indexed on line then col
	local loclist_data = {}
	for _, line in ipairs(output) do
		local text_part1, str_lnum, str_col, text_part2 = line:match("^(.-) at line (%d+), column (%d+)(.+)$")
		local text, lnum, col
		if text_part1 then
			lnum = tonumber(str_lnum)
			col = tonumber(str_col)
			text = text_part1 .. text_part2
		else
			lnum = 1
			col = 1
			text = line
		end
		text = text:gsub("%s+", " ") -- remove double spaces
		local list_item = { bufnr = bufnr, lnum = lnum, col = col, text = text, type = "E" }
		str_lnum = string.format("%016d", lnum)
		str_col = string.format("%016d", col)
		if not loclist_data[str_lnum] then
			loclist_data[str_lnum] = {}
		end
		if not loclist_data[str_lnum][str_col] then
			loclist_data[str_lnum][str_col] = {}
		end
		table.insert(loclist_data[str_lnum][str_col], list_item)
	end
	-- • now build list of loclist input
	local loclist_input = {}
	for _, col_table in util.pairs_by_keys(loclist_data) do
		for _, items in util.pairs_by_keys(col_table) do
			for _, item in ipairs(items) do
				table.insert(loclist_input, item)
			end
		end
	end
	-- display location list
	vim.api.nvim_call_function("setloclist", { 0, loclist_input })
	vim.api.nvim_cmd({ cmd = "lopen" }, {})
	return true
end

-- OPTIONS

---@mod dn_perl.options Options

-- expand |K| searches

---@tag dn_perl.keywordprg
---@brief [[
---'keywordprg' ~
---
---Change |K| to look in more locations for help.
---This is done by adjusting 'keywordprg' from:
--->
---  perldoc -f X
---<
---to look sequentially in function, variable, general and faq help:
--->
---  perldoc -f X || perldoc -v X || perldoc X || perldoc -q X
---<
---@brief ]]
vim.opt_local.keywordprg = "f(){perldoc -f $* || perldoc -v $* || perldoc $* || perldoc -q $*;}; f"
--local bufnr = vim.api.nvim_get_current_buf()
-- setting b:undo_ftplugin with vim.bo[bufnr] causes linter to complain:
-- "Fields cannot be injected into the reference of `vim.bo` for ..."
vim.api.nvim_buf_set_var(vim.api.nvim_get_current_buf(), "undo_ftplugin", "setlocal keywordprg<")

-- MAPPINGS

---@mod dn_perl.mappings Mappings

-- \c1 [n,i]

---@tag dn_perl.\c1
---@tag dn_perl.<Leader>c1
---@brief [[
---<Leader>c1 ~
---
---Run perlcritic with severity level 1 (brutal) in modes "n" and "i".
---@brief ]]
vim.keymap.set({ "n", "i" }, "<Leader>c1", function()
	dn_perl.critic("1=brutal")
end, { buffer = true, desc = "Run perlcritic with severity level 1 (brutal)" })

---@tag dn_perl.\c2
---@tag dn_perl.<Leader>c2
---@brief [[
---<Leader>c2 ~
---
---Run perlcritic with severity level 2 (cruel) in modes "n" and "i".
---@brief ]]
vim.keymap.set({ "n", "i" }, "<Leader>c2", function()
	dn_perl.critic("2=cruel")
end, { buffer = true, desc = "Run perlcritic with severity level 2 (cruel)" })

---@tag dn_perl.\c3
---@tag dn_perl.<Leader>c3
---@brief [[
---<Leader>c3 ~
---
---Run perlcritic with severity level 3 (harsh) in modes "n" and "i".
---@brief ]]
vim.keymap.set({ "n", "i" }, "<Leader>c3", function()
	dn_perl.critic("3=harsh")
end, { buffer = true, desc = "Run perlcritic with severity level 3 (harsh)" })

---@tag dn_perl.\c4
---@tag dn_perl.<Leader>c4
---@brief [[
---<Leader>c4 ~
---
---Run perlcritic with severity level 4 (stern) in modes "n" and "i".
---@brief ]]
vim.keymap.set({ "n", "i" }, "<Leader>c4", function()
	dn_perl.critic("4=stern")
end, { buffer = true, desc = "Run perlcritic with severity level 4 (stern)" })

---@tag dn_perl.\c5
---@tag dn_perl.<Leader>c5
---@brief [[
---<Leader>c5 ~
---
---Run perlcritic with severity level 5 (gentle) in modes "n" and "i".
---@brief ]]
vim.keymap.set({ "n", "i" }, "<Leader>c5", function()
	dn_perl.critic("5=gentle")
end, { buffer = true, desc = "Run perlcritic with severity level 5 (gentle)" })

-- COMMANDS

---@mod dn_perl.commands Commands

-- Critic

---@tag dn_perl.:Critic
---@tag dn_perl.Critic
---@brief [[
---Critic ~
---
---Run perlcritic with a specified severity level. The security level can be
---specified as an integer from 1 to 5, or a string whose first character is
---a digit from 1 to 5.
---Has |:command-completion| with the following values:
---• 5=gentle
---• 4=stern
---• 3=harsh
---• 2=cruel
---• 1=brutal
---@brief ]]
vim.api.nvim_buf_create_user_command(0, "Critic", function(opts)
	dn_perl.critic(opts.args)
end, { nargs = 1, complete = _complete_critic_severity, desc = "Run perlcritic with desired severity level" })

return dn_perl
