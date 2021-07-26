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
        w:write(string.format("    ---@type fun(%s):%s\n", params, emmy.get_typename(f.result_type)))
        w:write(string.format("    %s = %s.%s,\n", name, lib_name, name))
    end
end

---@class ModGenerator
---@field libs Table<string, string[]>
local ModGenerator = {

    ---@param self ModGenerator
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
        for header, export_header in pairs(exporter.headers) do
            local dir, name, ext = utils.split_ext(header)
            w:write(string.format("require('%s.cdef.%s')\n", dir_name, name))
        end

        -- const
        w:write("M.enums = {\n")
        for header, export_header in pairs(exporter.headers) do
            for i, t in ipairs(export_header.types) do
                if getmetatable(t) == types.Enum then
                    w:write(string.format("    %s = {\n", t.name))
                    for j, v in ipairs(t.values) do
                        w:write(string.format("        %s = C.%s,\n", v.name, v.name))
                    end
                    w:write("    },\n")
                end
            end
        end
        w:write("}\n")

        -- string, typedef
        local used = {}
        for header, export_header in pairs(exporter.headers) do
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

        -- functions
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
---@type Table<string, any>
local %s = ffi.load('%s')
M.cache.%s = %s
M.libs.%s = {
]],
                lib,
                lib_name,
                basename,
                lib_name,
                lib_name,
                lib_name
            ))

            for header, export_header in pairs(exporter.headers) do
                if
                    #utils.ifilter(headers, function(i, x)
                        return x == header
                    end) > 0
                then
                    for i, f in ipairs(export_header.functions) do
                        if f.dll_export then
                            write_function(w, lib_name, f, "")
                        end
                        if f.same_name then
                            for j, sn in ipairs(f.same_name) do
                                if sn.dll_export then
                                    write_function(w, lib_name, sn, string.format("__%d", j))
                                end
                            end
                        end
                    end
                end
            end
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
