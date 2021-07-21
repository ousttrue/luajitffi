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

    -- resolve typedef
    while true do
        local count = parser:resolve_typedef()
        if count == 0 then
            break
        end
    end

    -- export
    local exporter = Exporter.new(parser.nodemap)
    for _, node in parser.root:traverse() do
        if node.node_type == "function" then
            -- only function
            for i, export in ipairs(cmd.EXPORTS) do
                if export.header == node.location.path then
                    -- only in export header
                    exporter:export(node)
                end
            end
        end
    end

    -- generate
    if not lfs.attributes(cmd.OUT_DIR) then
        mkdirp(cmd.OUT_DIR)
    end

    require("cdef")
    for header, export_header in pairs(exporter.headers) do
        -- print(string.format("// %s", export_header))
        local _, name, ext = utils.split_ext(export_header.header)
        local path = string.format("%s/%s.lua", cmd.OUT_DIR, name)
        print(path)
        local w = io.open(path, "wb")

        w:write(string.format("-- %s\n", export_header.header:gsub("\\", "/")))
        w:write("local ffi = require 'ffi'\n")
        w:write("ffi.cdef[[\n")

        for i, t in ipairs(export_header.types) do
            local text = t:cdef()
            w:write(text)
        end

        for i, f in ipairs(export_header.functions) do
            if f.dll_export then
                local text = f:cdef()
                w:write(text)
            end
        end

        w:write("]]\n")

        w:close()
    end
end

main({ ... })
