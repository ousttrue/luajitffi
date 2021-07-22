local utils = require("clangffi.utils")

---@language lua
local template = [[
-- cdef
require('generated.clang.cdef.corecrt')
require('generated.clang.cdef.CXString')
require('generated.clang.cdef.vcruntime')
require('generated.clang.cdef.CXErrorCode')
require('generated.clang.cdef.Index')

local M = {
    consts = {},
    libs = {},
}

-- dll load
local clang = ffi.load('libclang')
M.libs.clang = {}

-- type alias
---@alias CXIndex ffi.cdata

---@class CXCursor
---@field kind integer
---@field xdata integer
---@field data cdata

M.libs.consts.CXCursorKind = {
    CXCursor_UnexposedDecl = ffi.C.CXCursor_UnexposedDecl,
}

-- function accessor with annotation
-- function annotation
---@param excludeDeclarationsFromPCH integer
---@param displayDiagnostics integer
---@return CXIndex
M.libs.clang.clang_createIndex = clang.clang_createIndex

return M   
]]

---@class Interface
---@field libs Table<string, string[]>
local Interface = {

    ---@param self Interface
    ---@param link string
    ---@param header string
    push = function(self, link, header)
        local lib = self.libs[link]
        if not lib then
            lib = {}
            self.libs[link] = lib
        end
        table.insert(lib, header)
    end,

    ---@param self Interface
    ---@param path string
    ---@param exporter Exporter
    generate = function(self, path, exporter)
        local w = io.open(path, "wb")

        w:write([[-- cdef
require('generated.clang.cdef.corecrt')
require('generated.clang.cdef.CXString')
require('generated.clang.cdef.vcruntime')
require('generated.clang.cdef.CXErrorCode')
require('generated.clang.cdef.Index')

local M = {
    consts = {},
    libs = {},
}            
]])

        w:write("return M\n")
        w:close()
    end,
}

---@return Interface
Interface.new = function()
    return utils.new(Interface, {
        libs = {},
    })
end

return Interface
