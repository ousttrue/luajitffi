local utils = require("clangffi.utils")
local Parser = require("clangffi.parser")
local Exporter = require("clangffi.exporter")
local ModGenerator = require("clangffi.mod_generator")
local CommandLine = require("clangffi.commandline")

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
                                if export.header:find("imgui_internal.h") then
                                    if node.spelling:find("Dock") then
                                        exporter:push(node)
                                    end
                                else
                                    exporter:push(node)
                                end
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
    for header, export_header in pairs(exporter.map) do
        -- print(string.format("// %s", export_header))
        local _, name, ext = utils.split_ext(export_header.header)
        local path = string.format("%s/%s.lua", cdef_out_dir, name)
        print(path)
        local w = io.open(path, "wb")

        w:write(string.format("-- generated from %s%s\n", name, ext))
        w:write("local ffi = require 'ffi'\n")
        w:write("ffi.cdef[[\n")

        for i, t in ipairs(export_header.types) do
            -- before nested
            if t.nested then
                for j, n in ipairs(t.nested) do
                    local text = n:cdef()
                    w:write(text)
                    w:write(";\n")
                end
            end

            local text = t:cdef()
            w:write(text)
            w:write(";\n")

            if t.methods then
                for i, m in ipairs(t.methods) do
                    if m.dll_export then
                        local text = m:cdef()
                        w:write(text)
                        w:write(";\n")
                    end
                end
            end
        end

        for i, f in ipairs(export_header.functions) do
            if f.dll_export then
                local text = f:cdef()
                w:write(text)
                w:write(";\n")
            end

            -- same name
            if f.same_name then
                for j, sn in ipairs(f.same_name) do
                    if sn.dll_export then
                        local text = sn:cdef(string.format("__%d", j))
                        w:write(text)
                        w:write(";\n")
                    end
                end
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
