local utils = require("clangffi.utils")
local Parser = require("clangffi.parser")
local Exporter = require("clangffi.exporter")

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
        local exporter = Exporter.new(export.header, export.link)
        exporters[exporter.header] = exporter
    end
    local used = {}
    for path, node in parser.root:traverse() do
        if used[node] then
            -- skip
        else
            used[node] = true
            if node.location then
                local exporter = exporters[node.location.path]
                if exporter then
                    local f = exporter:export(node)
                    if f then
                        print(f)
                    end
                end
            end
        end
    end

    -- generate
end

main({ ... })
