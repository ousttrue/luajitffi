local utils = require("clangffi.utils")
local Parser = require("clangffi.parser")
local Exporter = require("clangffi.exporter")
local lfs = require("lfs")

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
    return utils.new(Export, {
        header = header,
        link = link,
    })
end

---@class Args
---@field CFLAGS string[]
---@field EXPORTS Export[]
---@field OUT_DIR string
local CommandLine = {
    ---@param self Args
    __tostring = function(self)
        return string.format(
            "CFLAGS:[%s], EXPORT:[%s] => %s",
            table.concat(self.CFLAGS, ", "),
            table.concat(
                utils.map(self.EXPORTS, function(v)
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
CommandLine.parse = function(args)
    local instance = {
        CFLAGS = {},
        EXPORTS = {},
    }
    for i, arg in ipairs(args) do
        if arg:find("-I") == 1 or arg:find("-D") == 1 then
            table.insert(instance.CFLAGS, arg)
        elseif arg:find("-E") == 1 then
            local value = arg:sub(3)
            local export, dll = unpack(utils.split(value, ","))
            table.insert(instance.EXPORTS, Export.new(export, dll))
        elseif arg:find("-O") == 1 then
            local value = arg:sub(3)
            instance.OUT_DIR = value
        end
        i = i + 1
    end

    return utils.new(CommandLine, instance)
end

local function is_exists(path)
    if lfs.attributes(path) then
        return true
    end
end

local function mkdirp(dir)
    local parent, basename = utils.split_basename(dir)
    if parent and parent ~= "." then
        if not is_exists(parent) then
            mkdirp(parent)
        end
    end
    print(string.format("mkdir %s", dir))
    lfs.mkdir(dir)
end

---@param args string[]
local function main(args)
    local usage = [[usage:
lua clangffi.lua
-Iinclude_dir
-Eexport_header,dll_name.dll
-Oout_dir
]]

    -- parse
    local cmd = CommandLine.parse(args)
    local parser = Parser.new()
    parser:parse(cmd.EXPORTS, cmd.CFLAGS)

    -- traverse
    local exporters = {}
    for i, export in ipairs(cmd.EXPORTS) do
        local exporter = exporters[export.link]
        if not exporter then
            exporter = Exporter.new(export.link)
            exporters[exporter.link] = exporter
        end
        table.insert(exporter.headers, export.header)
    end
    local used = {}
    for path, node in parser.root:traverse() do
        if used[node] then
            -- skip
        else
            used[node] = true
            if node.location then
                for link, exporter in pairs(exporters) do
                    local f = exporter:export(node)
                    if f then
                        break
                    end
                end
            end
        end
    end

    -- generate
    -- print(cmd.OUT_DIR)
    if is_exists(cmd.OUT_DIR) then
        print(string.format("rmdir %s", cmd.OUT_DIR))
        lfs.rmdir(cmd.OUT_DIR)
    end
    mkdirp(cmd.OUT_DIR)

    for link, exporter in pairs(exporters) do
        local dir, name, ext = utils.split_ext(link)
        local path = string.format("%s/%s_cdef.lua", cmd.OUT_DIR, name)

        print(string.format("generate: %s ...", path))

        local w = io.open(path, "wb")
        w:write("-- this is generated\n")
        w:write("local ffi = require 'ffi'\n")
        w:write("ffi.cdef[[\n")

        for i, f in ipairs(exporter.functions) do
            w:write(string.format("%s;\n", f))
        end

        w:write("]]")
    end

    -- print(path)
end

main({ ... })
