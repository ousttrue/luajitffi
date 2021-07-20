local Node = require("node")
local Exporter = require("exporter")
local utils = require("utils")
local ffi = require("ffi")
local clang = require("clang")
local C = clang.C
local TypeMap = require("typemap")

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
---@field root Node
---@field node_map table<integer, Node>
---@field typemap TypeMap
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
        local index = clang.dll.clang_createIndex(0, 0)

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

        local c_str = ffi.typeof(string.format("const char *[%d]", #arguments))
        local array = c_str()
        for i, arg in ipairs(arguments) do
            -- FFI is zero origin !
            array[i - 1] = arg
        end

        local unsaved = ffi.new("struct CXUnsavedFile")
        local n_unsaved = 0

        if #unsaved_content > 0 then
            n_unsaved = 1
            unsaved.Filename = path
            unsaved.Contents = unsaved_content
            unsaved.Length = #unsaved_content
        end

        local tu = clang.dll.clang_parseTranslationUnit(
            index,
            path,
            array,
            #arguments,
            unsaved,
            n_unsaved,
            clang.C.CXTranslationUnit_DetailedPreprocessingRecord
        )

        return tu
    end,

    visit_recursive = function(self, tu)
        local visitor = ffi.cast("CXCursorVisitorP", function(cursor, parent, data)
            self:push(cursor[0], parent[0])
            return clang.C.CXChildVisit_Recurse
        end)
        local cursor = clang.dll.clang_getTranslationUnitCursor(tu)
        self:set_root(cursor)
        clang.dll.clang_visitChildren(cursor, visitor, nil)
        visitor:free()
    end,

    get_or_create_node = function(self, cursor)
        local c = clang.dll.clang_hashCursor(cursor)
        local node = self.node_map[c]
        if not node then
            node = Node.new(cursor, c)
            self.node_map[node.hash] = node

            if cursor.kind == C.CXCursor_FunctionDecl then
                local cxType = clang.dll.clang_getCursorResultType(cursor)
                node.result_type = self.typemap:get_or_create(node, cxType)
            elseif cursor.kind == C.CXCursor_DLLImport then
                node.dll_export = true
            elseif cursor.kind == C.CXCursor_ParmDecl then
                -- local param = Param.new(cursor)
                -- if cursor.children then
                --     assert(false)
                -- else
                --     local cxType = clang.dll.clang_getCursorType(cursor.cursor)
                --     param.type = typemap:get_or_create(cursor.cursor, cxType, cursor)
                --     table.insert(f.params, param)
                -- end
            elseif cursor.kind == C.CXCursor_TypeRef then
                -- if #f.params == 0 then
                --     f.result_type = typemap:get_reference(node)
                -- else
                --     f.params[#f.params].type = typemap:get_reference(node)
                -- end
            else
                -- print(cursor)
            end

            -- --- return
            -- do
            --     local cxType = clang.dll.clang_getCursorResultType(node.cursor)
            --     f.result_type = typemap:get_or_create(node.cursor, cxType, node)
            -- end
        end
        return node
    end,

    -- ---@param self Node
    -- process = function(self)
    --     if self.formatted then
    --         return
    --     end

    --     if self.type == C.CXCursor_TranslationUnit then
    --     elseif self.type == C.CXCursor_MacroDefinition then
    --     elseif self.type == C.CXCursor_MacroExpansion then
    --     elseif self.type == C.CXCursor_InclusionDirective then
    --     elseif self.type == C.CXCursor_TypedefDecl then
    --         -- self.formatted = string.format("%d: typedef %s", self.hash, self.spelling)
    --     elseif self.type == C.CXCursor_FunctionDecl then
    --         self.formatted = string.format("%s: function %s()", self.location, self.spelling)
    --     else
    --         -- self.formatted = string.format("%d: %q %s", self.hash, self.type, self.spelling)
    --     end
    -- end,

    set_root = function(self, cursor)
        self.root = self:get_or_create_node(cursor)
        self.root.indent = ""
    end,

    push = function(self, cursor, parent_cursor)
        local node = self:get_or_create_node(cursor)

        local p = clang.dll.clang_hashCursor(parent_cursor)
        local parent = self.node_map[p]
        if not parent.children then
            parent.children = {}
        end
        table.insert(parent.children, node)
        node.indent = parent.indent .. "  "
    end,
}

---@return Clang
Parser.new = function()
    return utils.new(Parser, {
        ffi = ffi,
        clang = clang,
        node_map = {},
        typemap = TypeMap.new(),
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

    local used = {}
    for i, export in ipairs(cmd.EXPORTS) do
        local exporter = Exporter.new(export.header, export.link)
        for path, node in parser.root:traverse() do
            if used[node] then
                -- skip
            else
                if node.cursor_kind == clang.C.CXCursor_FunctionDecl then
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
