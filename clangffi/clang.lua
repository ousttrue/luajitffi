local ffi = require("ffi")
require("clang.CXString")
require("clang.Index")
local utils = require("clangffi.utils")

local M = {
    dll = ffi.load("libclang"),
    C = ffi.C,
}

M.get_spelling_from_cursor = function(cursor)
    local cxString = M.dll.clang_getCursorSpelling(cursor)
    local value = ffi.string(M.dll.clang_getCString(cxString))
    M.dll.clang_disposeString(cxString)
    return value
end

M.get_spelling_from_file = function(file)
    if file == ffi.NULL then
        return
    end
    local cxString = M.dll.clang_getFileName(file)
    local value = ffi.string(M.dll.clang_getCString(cxString))
    M.dll.clang_disposeString(cxString)
    return value
end

---@class Location
---@field path string
---@field line integer
---@field column integer
local Location = {
    __tostring = function(self)
        return string.format("%s:%d", self.path, self.line)
    end,
}

---@return Location
M.get_location = function(cursor)
    local location = M.dll.clang_getCursorLocation(cursor)
    if M.dll.clang_equalLocations(location, M.dll.clang_getNullLocation()) ~= 0 then
        return
    end

    local file = ffi.new("CXFile[1]")
    local line = ffi.new("unsigned[1]")
    local column = ffi.new("unsigned[1]")
    local offset = ffi.new("unsigned[1]")
    M.dll.clang_getSpellingLocation(location, file, line, column, offset)
    local path = M.get_spelling_from_file(file[0])
    if path then
        return utils.new(Location, {
            path = path,
            line = line[0],
            column = column[0],
        })
    end
end

return M
