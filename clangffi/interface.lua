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

        for lib, headers in pairs(self.libs) do
            local _, basename, ext = utils.split_ext(lib)
            local lib_name = basename:sub(1)
            if lib_name:find("lib") == 1 then
                lib_name = lib_name:sub(4)
            end

            w:write(string.format(
                [[
-----------------------------------------------------------------------------
-- %s
-----------------------------------------------------------------------------
local clang = ffi.load('%s')
M.libs.%s = {
]],
                lib,
                basename,
                lib_name
            ))

            for header, export_header in pairs(exporter.headers) do
                if
                    #utils.filter(headers, function(x)
                        return x == header
                    end) > 0
                then
                    for i, f in ipairs(export_header.functions) do
                        for j, p in ipairs(f.params) do
                            w:write(string.format("    ---@param %s %s\n", p.name, p.type))
                        end
                        w:write(string.format("    ---@return %s\n", f.result_type))
                        w:write(string.format("    %s = %s.%s\n", f.name, lib_name, f.name))
                    end
                end
            end
        end

        w:write("}\n")
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
