local Node = require("node")
local Exporter = require("exporter")
local utils = require("utils")

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

---@class Clang
---@field ffi ffilib
---@field clang any
---@field root Node
---@field node_map table<integer, Node>
local Parser = {
    ---@param self Clang
    ---@param exports Export[]
    ---@param cflags string[]
    parse = function(self, exports, cflags)
        -- parse libclang
        local tu
        if #exports == 1 then
            -- empty unsaved_content
            tu = self:get_tu(exports[1].header, "", cflags)
        else
            -- use unsaved_content
            local mapped = utils.map(exports, function(v)
                return string.format('#include "%s"', v.header)
            end)
            local unsaved_content = table.concat(mapped, "\n")
            tu = self:get_tu("__unsaved_header__.h", unsaved_content, cflags)
        end

        self:visit_recursive(tu)
    end,

    ---@param self Clang
    ---@param path string
    ---@param unsaved_content string
    ---@param cflags string[]
    get_tu = function(self, path, unsaved_content, cflags)
        local index = self.clang.clang_createIndex(0, 0)

        local arguments = {
            "-x",
            "c++",
            "-target",
            "x86_64-windows-msvc",
            "-fms-compatibility-version=18",
            "-fdeclspec",
            "-fms-compatibility",
        }
        for i, cflag in ipairs(cflags) do
            table.insert(arguments, cflag)
        end
        table.insert(arguments, string.format("-I%s", path))

        local c_str = self.ffi.typeof(string.format("const char *[%d]", #arguments))
        local array = c_str()
        for i, arg in ipairs(arguments) do
            -- FFI is zero origin !
            array[i - 1] = arg
        end

        local unsaved = self.ffi.new("struct CXUnsavedFile")
        local n_unsaved = 0

        if #unsaved_content > 0 then
            n_unsaved = 1
            unsaved.Filename = path
            unsaved.Contents = unsaved_content
            unsaved.Length = #unsaved_content
        end

        local tu = self.clang.clang_parseTranslationUnit(
            index,
            path,
            array,
            #arguments,
            unsaved,
            n_unsaved,
            self.ffi.C.CXTranslationUnit_DetailedPreprocessingRecord
        )

        return tu
    end,

    visit_recursive = function(self, tu)
        local visitor = self.ffi.cast("CXCursorVisitorP", function(cursor, parent, data)
            self:push(cursor[0], parent[0])

            return self.ffi.C.CXChildVisit_Recurse
        end)
        local cursor = self.clang.clang_getTranslationUnitCursor(tu)
        self:set_root(cursor)
        self.clang.clang_visitChildren(cursor, visitor, nil)
        visitor:free()
    end,

    get_location = function(self, cursor)
        local location = self.clang.clang_getCursorLocation(cursor)
        if self.clang.clang_equalLocations(location, self.clang.clang_getNullLocation()) ~= 0 then
            return
        end

        local file = self.ffi.new("CXFile[1]")
        local line = self.ffi.new("unsigned[1]")
        local column = self.ffi.new("unsigned[1]")
        local offset = self.ffi.new("unsigned[1]")
        self.clang.clang_getSpellingLocation(location, file, line, column, offset)
        local path = self:get_spelling_from_file(file[0])
        if path then
            return path
        end
    end,

    get_or_create_node = function(self, cursor)
        local c = self.clang.clang_hashCursor(cursor)
        local node = self.node_map[c]
        if not node then
            node = utils.new(Node, {
                hash = c,
                spelling = self:get_spelling_from_cursor(cursor),
                type = cursor.kind,
                location = self:get_location(cursor),
            })
            self.node_map[node.hash] = node
        end
        return node
    end,

    set_root = function(self, cursor)
        self.root = self:get_or_create_node(cursor)
        self.root.indent = ""
    end,

    push = function(self, cursor, parent_cursor)
        local node = self:get_or_create_node(cursor)

        local p = self.clang.clang_hashCursor(parent_cursor)
        local parent = self.node_map[p]
        if not parent.children then
            parent.children = {}
        end
        table.insert(parent.children, node)
        node.indent = parent.indent .. "  "
    end,

    get_spelling_from_cursor = function(self, cursor)
        local cxString = self.clang.clang_getCursorSpelling(cursor)
        local value = self.ffi.string(self.clang.clang_getCString(cxString))
        self.clang.clang_disposeString(cxString)
        return value
    end,

    get_spelling_from_file = function(self, file)
        if file == self.ffi.NULL then
            return
        end
        local cxString = self.clang.clang_getFileName(file)
        local value = self.ffi.string(self.clang.clang_getCString(cxString))
        self.clang.clang_disposeString(cxString)
        return value
    end,
}

---@return Clang
Parser.new = function()
    require("clang.CXString")
    require("clang.Index")
    local ffi = require("ffi")
    local clang = ffi.load("libclang")
    return utils.new(Parser, {
        ffi = ffi,
        clang = clang,
        node_map = {},
    })
end

---@param args string[]
local function main(args)
    local usage = [[usage:
    lua clangffi.lua
    -Iinclude_dir
    -Eexport_header,dll_name.dll
    -Oout_dir
    ]]

    local cmd = CommandLine.parse(args)

    local parser = Parser.new()

    parser:parse(cmd.EXPORTS, cmd.CFLAGS)

    -- for node in parser.root:traverse_after() do
    --     node:process()
    -- end

    local used = {}
    for i, export in ipairs(cmd.EXPORTS) do
        local exporter = Exporter.new(export.header, export.link)
        for path, node in parser.root:traverse() do
            if used[node] then
                -- skip
            else
                if node.type == parser.ffi.C.CXCursor_FunctionDecl then
                    if node.location == export.header then
                        used[node] = true

                        local f = exporter:export(node)
                        print(f)
                    end
                end
            end
        end

        -- print(exporter)
    end
end

main({ ... })
