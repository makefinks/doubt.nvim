local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(source))
local plenary_dir = vim.env.PLENARY_DIR or vim.fs.joinpath(root, ".deps", "plenary.nvim")

vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(plenary_dir)

vim.notify = function() end

vim.cmd("runtime plugin/plenary.vim")
