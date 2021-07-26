local utils = require("clangffi.utils")
local Parser = require("clangffi.parser")
local Exporter = require("clangffi.exporter")
local ModGenerator = require("clangffi.mod_generator")

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
            export = utils.get_fullpath(export)
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
lua main.lua
-Iinclude_dir
-Eexport_header,dll_name.dll
-Oout_dir
]]

    -- parse
    print("parse...")
    local cmd = CommandLine.parse(args)
    local parser = Parser.new()
    parser:parse(cmd.EXPORTS, cmd.CFLAGS)
    print(parser.node_count)

    print("remove_duplicated...")
    local count = parser.root:remove_duplicated()
    print(count)

    -- export
    print("export...")
    local count = 0
    local exporter = Exporter.new(parser.nodemap)
    local used = {}
    for _, node in parser.root:traverse() do
        if not used[node] then
            used[node] = true
            count = count + 1
            if node.location then
                for i, export in ipairs(cmd.EXPORTS) do
                    if export.header == node.location.path then
                        -- only in export header
                        if node.node_type == "function" then
                            if node.spelling:find("operator") == 1 then
                                -- skip
                            else
                                exporter:push(node)
                            end
                        elseif node.node_type == "enum" then
                            exporter:push(node)
                        end
                    end
                end
            end
        end
    end
    exporter:execute()
    print(count)  

    -- generate
    print("generate...")
    local cdef_out_dir = cmd.OUT_DIR .. "/cdef"
    if not utils.is_exists(cdef_out_dir) then
        utils.mkdirp(cdef_out_dir)
    end

    require("clangffi.cdef")
    for header, export_header in pairs(exporter.headers) do
        -- print(string.format("// %s", export_header))
        local _, name, ext = utils.split_ext(export_header.header)
        local path = string.format("%s/%s.lua", cdef_out_dir, name)
        print(path)
        local w = io.open(path, "wb")

        w:write(string.format("-- %s\n", export_header.header:gsub("\\", "/")))
        w:write("local ffi = require 'ffi'\n")
        w:write("ffi.cdef[[\n")

        for i, t in ipairs(export_header.types) do
            if t.name == "ImFontAtlas" or t.name == "ImFont" then
                -- skip C++ type
            else
                local text = t:cdef()
                w:write(text)
                w:write(";\n")
            end
        end

        for i, f in ipairs(export_header.functions) do
            if f.dll_export then
                local text = f:cdef()
                w:write(text)
                w:write(";\n")
            end
        end

        if name == "Index" then
            w:write("// http://wiki.luajit.org/FFI-Callbacks-with-pass-by-value-structs\n")
            w:write(
                "typedef enum CXChildVisitResult (*CXCursorVisitorP)(CXCursor *cursor, CXCursor *parent, CXClientData client_data);\n"
            )
        end

        w:write("]]\n")

        w:close()
    end

    -- interface
    local generator = ModGenerator.new()
    for i, export in ipairs(cmd.EXPORTS) do
        generator:push(export.link, export.header)
    end
    local path = string.format("%s/mod.lua", cmd.OUT_DIR)
    print(path)
    generator:generate(path, exporter)
end

main({ ... })
