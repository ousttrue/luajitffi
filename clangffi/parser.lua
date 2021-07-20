local ffi = require("ffi")
local clang = require("clangffi.clang")
local C = clang.C
local Node = require("clangffi.node")
local utils = require("clangffi.utils")
local TypeMap = require("clangffi.typemap")

---@class Parser
---@field root Node
---@field node_map table<integer, Node>
---@field typemap TypeMap
local Parser = {
    ---@param self Parser
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

    ---@param self Parser
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

    ---@param self Parser
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

    ---@param self Parser
    get_or_create_node = function(self, cursor, parent_cursor)
        local c = clang.dll.clang_hashCursor(cursor)
        local node = self.node_map[c]
        if node then
            return node
        end

        node = Node.new(cursor, c)
        self.node_map[c] = node

        if cursor.kind == C.CXCursor_TranslationUnit then
        elseif cursor.kind == C.CXCursor_MacroDefinition then
        elseif cursor.kind == C.CXCursor_InclusionDirective then
        elseif cursor.kind == C.CXCursor_MacroExpansion then
        elseif cursor.kind == C.CXCursor_UnexposedDecl then
        elseif cursor.kind == C.CXCursor_ClassTemplate then
        elseif cursor.kind == C.CXCursor_TemplateTypeParameter then
        elseif cursor.kind == C.CXCursor_CXXTypeidExpr then
        elseif cursor.kind == C.CXCursor_ClassTemplatePartialSpecialization then
        elseif cursor.kind == C.CXCursor_StaticAssert then
        elseif cursor.kind == C.CXCursor_UnaryOperator then
        elseif cursor.kind == C.CXCursor_DeclRefExpr then
        elseif cursor.kind == C.CXCursor_TemplateRef then
        elseif cursor.kind == C.CXCursor_FunctionTemplate then
        elseif cursor.kind == C.CXCursor_NonTypeTemplateParameter then
        elseif cursor.kind == C.CXCursor_VarDecl then
        elseif cursor.kind == C.CXCursor_UnexposedAttr then
        elseif cursor.kind == C.CXCursor_CompoundStmt then
        elseif cursor.kind == C.CXCursor_ReturnStmt then
        elseif cursor.kind == C.CXCursor_CallExpr then
        elseif cursor.kind == C.CXCursor_UnexposedExpr then
        elseif cursor.kind == C.CXCursor_CStyleCastExpr then
        elseif cursor.kind == C.CXCursor_BinaryOperator then
        elseif cursor.kind == C.CXCursor_ParenExpr then
            --skip
        elseif cursor.kind == C.CXCursor_StringLiteral then
        elseif cursor.kind == C.CXCursor_IntegerLiteral then
            -- literal
        elseif cursor.kind == C.CXCursor_FunctionDecl then
            node.type = "function"
            -- local cxType = clang.dll.clang_getCursorResultType(cursor)
            -- node.result_type = self.typemap:get_or_create(node, cxType)
        elseif cursor.kind == C.CXCursor_DLLImport then
            node.dll_export = true
        elseif cursor.kind == C.CXCursor_ParmDecl then
            local parent_c = clang.dll.clang_hashCursor(parent_cursor)
            local parent = self.node_map[parent_c]
            local cxType = clang.dll.clang_getCursorType(cursor)
            node.param_type = self.typemap:type_from_cx_type(cxType, cursor)
        elseif cursor.kind == C.CXCursor_FieldDecl then
            local parent_c = clang.dll.clang_hashCursor(parent_cursor)
            local parent = self.node_map[parent_c]
            local a = 0
        elseif cursor.kind == C.CXCursor_TypeRef then
            local parent_c = clang.dll.clang_hashCursor(parent_cursor)
            local parent = self.node_map[parent_c]
            local a = 0
            -- if #f.params == 0 then
            --     f.result_type = typemap:get_reference(node)
            -- else
            --     f.params[#f.params].type = typemap:get_reference(node)
            -- end
        elseif cursor.kind == C.CXCursor_EnumDecl then
            -- enum
            local t = self.typemap:create_enum(cursor)
            node.type = t
        elseif cursor.kind == C.CXCursor_EnumConstantDecl then
            local parent_c = clang.dll.clang_hashCursor(parent_cursor)
            local parent = self.node_map[parent_c]
            local a = 0
        elseif cursor.kind == C.CXCursor_TypedefDecl then
            -- typedef
            local t = self.typemap:create_typedef(cursor)
            node.type = t
        elseif cursor.kind == C.CXCursor_StructDecl then
            local t = self.typemap:create_struct(cursor)
            node.type = t
        else
            assert(false)
            -- print(cursor)
        end

        return node
    end,

    ---@param self Parser
    set_root = function(self, cursor)
        self.root = self:get_or_create_node(cursor)
        self.root.indent = ""
    end,

    ---@param self Parser
    push = function(self, cursor, parent_cursor)
        local node = self:get_or_create_node(cursor, parent_cursor)

        local p = clang.dll.clang_hashCursor(parent_cursor)
        local parent = self.node_map[p]
        if not parent.children then
            parent.children = {}
        end
        table.insert(parent.children, node)
        node.indent = parent.indent .. "  "
    end,
}

---@return Parser
Parser.new = function()
    return utils.new(Parser, {
        ffi = ffi,
        clang = clang,
        node_map = {},
        typemap = TypeMap.new(),
    })
end

return Parser
