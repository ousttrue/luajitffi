require("clang.CXString")
require("clang.Index")
local ffi = require("ffi")
local clang = ffi.load("libclang")
-- print(clang)

---@param str string
---@param ts string
---@return string[]
local function split(str, ts)
    local t = {}
    for s in string.gmatch(str, "([^" .. ts .. "]+)") do
        table.insert(t, s)
    end
    return t
end

---@generic S, T
---@param tbl S[]
---@param f fun(src:S):T
---@return T[]
local function map(tbl, f)
    local t = {}
    for _, v in ipairs(tbl) do
        table.insert(t, f(v))
    end
    return t
end

---@class Export
---@field header string
---@field link string
local Export = {
    ---@param self Export
    __tostring = function(self)
        return string.format("{%s: %s}", self.header, self.link)
    end,
}

---@param header string
---@param link string
---@return Export
Export.new = function(header, link)
    return setmetatable({
        header = header,
        link = link,
    }, Export)
end

---@class Args
---@field CFLAGS string[]
---@field EXPORTS Export[]
---@field OUT_DIR string
local Args = {
    ---@param self Args
    __tostring = function(self)
        return string.format(
            "CFLAGS:[%s], EXPORT:[%s] => %s",
            table.concat(self.CFLAGS, ", "),
            table.concat(
                map(self.EXPORTS, function(v)
                    return tostring(v)
                end),
                ", "
            ),
            self.OUT_DIR
        )
    end,
}

---@param args string[]
---@return Args
Args.parse = function(args)
    local parsed = {
        CFLAGS = {},
        EXPORTS = {},
    }
    for i, arg in ipairs(args) do
        if arg:find("-I") == 1 or arg:find("-D") == 1 then
            table.insert(parsed.CFLAGS, arg)
        elseif arg:find("-E") == 1 then
            local value = arg:sub(3)
            local export, dll = unpack(split(value, ","))
            table.insert(parsed.EXPORTS, Export.new(export, dll))
        elseif arg:find("-O") == 1 then
            local value = arg:sub(3)
            parsed.OUT_DIR = value
        end
        i = i + 1
    end

    setmetatable(parsed, Args)

    for i, cflags in ipairs(parsed.CFLAGS) do
        if cflags:find("-I") == 1 then
            local include = cflags:sub(3)
            for j, v in ipairs(parsed.EXPORTS) do
                if v.header:find(include) == 1 then
                    -- to relative path
                    v.header = v.header:sub(#include + 2)
                end
            end
        end
    end

    return parsed
end

---@param args string[]
local function main(args)
    local usage = [[usage:
    lua clangffi.lua
    -Iinclude_dir
    -Eexport_header,dll_name.dll
    -Oout_dir
    ]]

    local parsed = Args.parse(args)
    print(string.format("%q", parsed))

    -- parse libclang
end

main({ ... })
