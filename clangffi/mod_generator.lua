local utils = require("clangffi.utils")
local emmy = require("clangffi.emmy")
local types = require("clangffi.types")

local FUNCTION = "fun"

local function get_name(i, name)
    if name and #name > 0 then
        return emmy.escape_symbol(name)
    end
    return string.format("param%s", i)
end

---@param src string
---@return string
local function to_lua(src)
    if src == "NULL" then
        return "nil"
    end
    if src == "true" then
        return "true"
    end
    if src == "false" then
        return "false"
    end
    if src == "FLT_MAX" then
        return "3.402823466e+38"
    end
    if src == "sizeof(float)" then
        return 4
    end

    if src == "ImVec2(0,0)" or src == "ImVec2(0.0f,0.0f)" then
        return "ffi.new('struct ImVec2')"
    end
    if src == "ImVec2(1,1)" then
        return "ffi.new('struct ImVec2', 1, 1)"
    end
    if src == "ImVec2(-FLT_MIN,0)" then
        return "ffi.new('struct ImVec2', -1.175494351e-38, 0)"
    end
    if src == "ImVec4(0,0,0,0)" then
        return "ffi.new('struct ImVec4')"
    end
    if src == "ImVec4(1,1,1,1)" then
        return "ffi.new('struct ImVec4', 1, 1, 1, 1)"
    end

    local m = src:match("^[+-]?(%d+)$")
    if m then
        return m
    end

    local m = src:match("^[+-]?(%d+%.%d+)f?$")
    if m then
        return m
    end

    if src:find('"') == 1 then
        return src
    end

    return src
end

---@param w file*
---@param lib_name string
---@param f Function
---@param suffix string
local function write_function(w, lib_name, f, suffix)
    local has_default = utils.iany(f.params, function(i, x)
        if x.default_value then
            return true
        end
    end)
    local name = f.name .. suffix

    if has_default then
        for j, p in ipairs(f.params) do
            w:write(string.format("    ---@param %s %s\n", get_name(i, p.name), emmy.get_typename(p.type)))
        end
        -- w:write(string.format("    ---@return %s\n", emmy.get_typename(f.result_type)))
        local params = table.concat(
            utils.imap(f.params, function(i, p)
                return get_name(i, p.name)
            end),
            ", "
        )
        w:write(string.format("    %s = function(%s)\n", name, params))
        for j, p in ipairs(f.params) do
            if p.default_value and p.default_value ~= "NULL" then
                local pname = get_name(j, p.name)
                w:write(string.format("        %s = %s or %s\n", pname, pname, to_lua(p.default_value)))
            end
        end

        w:write(string.format("        return %s.%s(%s)\n", lib_name, name, params))
        w:write("    end,\n")
    else
        local params = table.concat(
            utils.imap(f.params, function(i, p)
                local s = string.format("%s:%s", get_name(i, p.name), emmy.get_typename(p.type))
                return s
            end),
            ", "
        )
        if f.is_variadic then
            params = params .. ", ..."
        end
        w:write(string.format("    ---@type fun(%s):%s\n", params, emmy.get_typename(f.result_type)))
        w:write(string.format("    %s = %s.%s,\n", name, lib_name, name))
    end
end

local function generate_require(w, dir_name, export_header)
    for i, include in ipairs(export_header.includes) do
        generate_require(w, dir_name, include)
    end
    if export_header.header then
        local dir, name, ext = utils.split_ext(export_header.header)
        w:write(string.format("require('%s.cdef.%s')\n", dir_name, name))
    end
end

local function get_enum_short_name(enum_name, value_name)
    if value_name:find(enum_name) == 1 then
        local short_name = value_name:sub(#enum_name + 1)
        return short_name
    end
    return value_name
end

local function generate_const(w, export_header)
    for i, include in ipairs(export_header.includes) do
        generate_const(w, include)
    end
    for i, t in ipairs(export_header.types) do
        if getmetatable(t) == types.Enum then
            w:write(string.format("    %s = {\n", t.name))
            for j, v in ipairs(t.values) do
                local short_name = get_enum_short_name(t.name, v.name)
                w:write(string.format("        %s = C.%s,\n", short_name, v.name))
            end
            w:write("    },\n")
        end
    end
end

local function generate_struct_typedef(w, export_header, used)
    for i, include in ipairs(export_header.includes) do
        generate_struct_typedef(w, include, used)
    end
    for i, t in ipairs(export_header.types) do
        if not used[t.name] then
            used[t.name] = true
            local mt = getmetatable(t)
            if mt == types.Typedef then
                w:write(string.format("---@class %s\n", t.name))
            elseif mt == types.Struct then
                w:write(string.format("---@class %s\n", t.name))
            end
        end
    end
end

---@class Lib
---@field link string dll name
---@field name string
---@field basename string
---@field headers string[]
local Lib = {}
---@param link string
Lib.new = function(link)
    local _, basename, ext = utils.split_ext(link)
    local lib_name = basename:sub(1)
    if lib_name:find("lib") == 1 then
        lib_name = lib_name:sub(4)
    end

    return utils.new(Lib, {
        name = lib_name,
        basename = basename,
        link = link,
        headers = {},
    })
end

---@class ModGenerator
---@field libs Lib[]
local ModGenerator = {

    ---@param self ModGenerator
    ---@param link string
    ---@param header string
    push = function(self, link, header)
        for i, lib in ipairs(self.libs) do
            if lib.link == link then
                table.insert(lib.headers, header)
                return
            end
        end
        local lib = Lib.new(link)
        table.insert(self.libs, lib)
        table.insert(lib.headers, header)
    end,

    ---@param self ModGenerator
    ---@param path string
    ---@param exporter Exporter
    generate = function(self, path, exporter)
        local w = io.open(path, "wb")
        local dir = utils.split_ext(path)
        local _, dir_name = utils.split_ext(dir)

        w:write([[-- this is generated by luajitffi
local ffi = require('ffi')
---@type Table<string, integer>
local C = ffi.C

local M = {
    libs = {},
    cache = {},
}

-- cdef
]])

        -- cdef
        generate_require(w, dir_name, exporter.root)

        -- const
        w:write("M.enums = {\n")
        generate_const(w, exporter.root)
        w:write("}\n")

        -- struct, typedef
        local used = {}
        generate_struct_typedef(w, exporter.root, used)

        -- functions
        for i, lib in ipairs(self.libs) do
            w:write(string.format(
                [[
-----------------------------------------------------------------------------
-- %s
-----------------------------------------------------------------------------
---@type Table<string, any>
local %s = ffi.load('%s')
M.cache.%s = %s
M.libs.%s = {
]],
                lib.link,
                lib.name,
                lib.basename,
                lib.name,
                lib.name,
                lib.name
            ))

            ---@param export_header ExportHeader
            local function generate_function(export_header)
                if
                    #utils.ifilter(lib.headers, function(i, x)
                        return x == export_header.header
                    end) > 0
                then
                    for i, f in ipairs(export_header.functions) do
                        if f.dll_export then
                            write_function(w, lib.name, f, "")
                        end
                        if f.same_name then
                            for j, sn in ipairs(f.same_name) do
                                if sn.dll_export then
                                    write_function(w, lib.name, sn, string.format("__%d", j))
                                end
                            end
                        end
                    end
                    for i, s in ipairs(export_header.types) do
                        if s.methods then
                            for j, m in ipairs(s.methods) do
                                if m.dll_export then
                                    write_function(w, lib.name, m, "")
                                end
                            end
                        end
                    end
                end

                for _, include in ipairs(export_header.includes) do
                    generate_function(include)
                end
            end
            generate_function(exporter.root)
            w:write("}\n")
        end

        w:write("return M\n")
        w:close()
    end,
}

---@return ModGenerator
ModGenerator.new = function()
    return utils.new(ModGenerator, {
        libs = {},
    })
end

return ModGenerator
