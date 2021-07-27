local ffi = require("ffi")
local Node = require("clangffi.node")
local utils = require("clangffi.utils")
local types = require("clangffi.types")
local mod = require("clang.mod")
local clang_util = require("clangffi.clang_util")
local clang = mod.libs.clang
local CXCursorKind = mod.enums.CXCursorKind

---@class Parser
---@field root Node
---@field nodemap table<integer, Node>
---@field node_count integer
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
            local mapped = utils.imap(exports, function(i, v)
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
        local index = clang.clang_createIndex(0, 0)

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

        local flags = mod.enums.CXTranslationUnit_Flags.CXTranslationUnit_DetailedPreprocessingRecord
            + mod.enums.CXTranslationUnit_Flags.CXTranslationUnit_SkipFunctionBodies

        local tu = clang.clang_parseTranslationUnit(index, path, array, #arguments, unsaved, n_unsaved, flags)

        return tu
    end,

    ---@param self Parser
    visit_recursive = function(self, tu)
        local visitor = ffi.cast("CXCursorVisitorP", function(cursor, parent, data)
            self:push(cursor[0], parent[0])
            return mod.enums.CXChildVisitResult.CXChildVisit_Recurse
        end)
        local cursor = clang.clang_getTranslationUnitCursor(tu)
        self:set_root(cursor)
        clang.clang_visitChildren(cursor, visitor, nil)
        visitor:free()
    end,

    ---@param self Parser
    get_or_create_node = function(self, cursor, parent_cursor)
        local c = clang.clang_hashCursor(cursor)
        local node = self.nodemap[c]
        if node then
            return node
        end

        node = Node.new(cursor, c, parent_cursor)
        self.nodemap[c] = node
        self.node_count = self.node_count + 1
        if self.node_count % 10000 == 0 then
            print(self.node_count)
        end

        if cursor.kind == CXCursorKind.CXCursor_TranslationUnit then
        elseif cursor.kind == CXCursorKind.CXCursor_MacroDefinition then
        elseif cursor.kind == CXCursorKind.CXCursor_InclusionDirective then
        elseif cursor.kind == CXCursorKind.CXCursor_MacroExpansion then
        elseif cursor.kind == CXCursorKind.CXCursor_UnexposedDecl then
        elseif cursor.kind == CXCursorKind.CXCursor_CXXBaseSpecifier then
        elseif cursor.kind == CXCursorKind.CXCursor_TemplateTypeParameter then
        elseif cursor.kind == CXCursorKind.CXCursor_CXXTypeidExpr then
        elseif cursor.kind == CXCursorKind.CXCursor_ClassTemplatePartialSpecialization then
        elseif cursor.kind == CXCursorKind.CXCursor_StaticAssert then
        elseif cursor.kind == CXCursorKind.CXCursor_DeclRefExpr then
        elseif cursor.kind == CXCursorKind.CXCursor_FunctionTemplate then
        elseif cursor.kind == CXCursorKind.CXCursor_NonTypeTemplateParameter then
        elseif cursor.kind == CXCursorKind.CXCursor_VarDecl then
        elseif cursor.kind == CXCursorKind.CXCursor_UnexposedAttr then
        elseif cursor.kind == CXCursorKind.CXCursor_CompoundStmt then
        elseif cursor.kind == CXCursorKind.CXCursor_ReturnStmt then
        elseif cursor.kind == CXCursorKind.CXCursor_CallExpr then
        elseif cursor.kind == CXCursorKind.CXCursor_UnexposedExpr then
        elseif cursor.kind == CXCursorKind.CXCursor_CStyleCastExpr then
        elseif cursor.kind == CXCursorKind.CXCursor_FirstInvalid then
        elseif cursor.kind == CXCursorKind.CXCursor_WarnUnusedResultAttr then
        elseif cursor.kind == CXCursorKind.CXCursor_AlignedAttr then
        elseif cursor.kind == CXCursorKind.CXCursor_Namespace then
        elseif cursor.kind == CXCursorKind.CXCursor_CXXNullPtrLiteralExpr then
        elseif cursor.kind == CXCursorKind.CXCursor_UsingDeclaration then
        elseif cursor.kind == CXCursorKind.CXCursor_NamespaceRef then
        elseif cursor.kind == CXCursorKind.CXCursor_OverloadedDeclRef then
        elseif cursor.kind == CXCursorKind.CXCursor_CXXAccessSpecifier then
        elseif cursor.kind == CXCursorKind.CXCursor_ClassDecl then
        elseif cursor.kind == CXCursorKind.CXCursor_Constructor then
        elseif cursor.kind == CXCursorKind.CXCursor_Destructor then
        elseif cursor.kind == CXCursorKind.CXCursor_CXXDeleteExpr then
        elseif cursor.kind == CXCursorKind.CXCursor_ConversionFunction then
        elseif cursor.kind == CXCursorKind.CXCursor_DLLImport then
        elseif cursor.kind == CXCursorKind.CXCursor_DLLExport then
        elseif cursor.kind == CXCursorKind.CXCursor_ConditionalOperator then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_UnaryOperator then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_BinaryOperator then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_ParenExpr then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_UnaryExpr then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_CXXBoolLiteralExpr then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_StringLiteral then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_IntegerLiteral then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_FloatingLiteral then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_FunctionDecl or cursor.kind == CXCursorKind.CXCursor_CXXMethod then
            node.node_type = "function"
            if cursor.kind == CXCursorKind.CXCursor_CXXMethod then
                node.node_type = "method"
            end
            local cxType = clang.clang_getCursorResultType(cursor)
            local t, is_const = types.type_from_cx_type(cxType, cursor)
            node.type = t
            node.is_const = is_const
            node.mangling = clang_util.get_mangling_from_cursor(cursor)
            node.is_variadic = clang.clang_Cursor_isVariadic(cursor) ~= 0
        elseif cursor.kind == CXCursorKind.CXCursor_ParmDecl then
            node.node_type = "param"
            local cxType = clang.clang_getCursorType(cursor)
            local t, is_const = types.type_from_cx_type(cxType, cursor)
            node.type = t
            node.is_const = is_const
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_FieldDecl then
            node.node_type = "field"
            local offset = tonumber(clang.clang_Cursor_getOffsetOfField(cursor))
            node.offset = offset
            local cxType = clang.clang_getCursorType(cursor)
            local t, is_const = types.type_from_cx_type(cxType, cursor)
            node.type = t
            -- node.is_const = is_const
        elseif cursor.kind == CXCursorKind.CXCursor_TemplateRef then
            node.node_type = "templateref"
            local referenced = clang.clang_getCursorReferenced(cursor)
            local ref_hash = clang.clang_hashCursor(referenced)
            node.ref_hash = ref_hash
        elseif cursor.kind == CXCursorKind.CXCursor_TypeRef then
            node.node_type = "typeref"
            local referenced = clang.clang_getCursorReferenced(cursor)
            local ref_hash = clang.clang_hashCursor(referenced)
            node.ref_hash = ref_hash
        elseif cursor.kind == CXCursorKind.CXCursor_EnumDecl then
            node.node_type = "enum"
            local t = types.get_enum_int_type(cursor)
            node.base_type = t
        elseif cursor.kind == CXCursorKind.CXCursor_EnumConstantDecl then
            node.node_type = "enum_constant"
            local value = tonumber(clang.clang_getEnumConstantDeclValue(cursor))
            node.value = value
        elseif cursor.kind == CXCursorKind.CXCursor_TypedefDecl then
            node.node_type = "typedef"
            local t = types.get_underlying_type(cursor)
            node.type = t
        elseif cursor.kind == CXCursorKind.CXCursor_StructDecl then
            node.node_type = "struct"
            local cxType = clang.clang_getCursorType(cursor)
            node.size = clang.clang_Type_getSizeOf(cxType)
            local semantic_parent = clang.clang_getCursorSemanticParent(cursor)
            if
                semantic_parent.kind ~= CXCursorKind.CXCursor_TranslationUnit
                and semantic_parent.kind ~= CXCursorKind.CXCursor_UnexposedDecl
            then
                local semantic_parent_hash = clang.clang_hashCursor(semantic_parent)
                if semantic_parent_hash > 0 then
                    -- nested type
                    node.semantic_parent_hash = semantic_parent_hash
                end
            end
        elseif cursor.kind == CXCursorKind.CXCursor_UnionDecl then
            node.node_type = "union"
        elseif cursor.kind == CXCursorKind.CXCursor_ClassTemplate then
            node.node_type = "class_template"
        else
            assert(false, string.format("unknown kind: %q", cursor.kind))
        end

        return node
    end,

    ---@param self Parser
    set_root = function(self, cursor)
        self.root = self:get_or_create_node(cursor)
    end,

    ---@param self Parser
    push = function(self, cursor, parent_cursor)
        local node = self:get_or_create_node(cursor, parent_cursor)

        local p = clang.clang_hashCursor(parent_cursor)
        local parent = self.nodemap[p]
        if not parent.children then
            parent.children = {}
        end

        -- this is slow down. later call Node:remove_duplicated
        -- for i, sibling in ipairs(parent.children) do
        --     if sibling.hash == node.hash then
        --         -- avoid duplicate
        --         return
        --     end
        -- end

        table.insert(parent.children, node)
    end,

    ---@param self Parser
    ---@param node Node
    replace_typedef = function(self, node)
        if getmetatable(node.type) == types.Primitive then
            return
        elseif getmetatable(node.type) == types.Pointer then
            return
        elseif getmetatable(node.type) == types.Typedef then
            return
        elseif node.type == "unexposed" then
            return
        elseif node.type == "elaborated" then
            if #node.children == 1 then
                if node.children[1].node_type == "struct" then
                    node.children[1].spelling = node.spelling
                    return node.children[1]
                elseif node.children[1].node_type == "enum" then
                    node.children[1].spelling = node.spelling
                    return node.children[1]
                else
                    assert(false)
                end
            else
                assert(false)
            end
        else
            assert(false)
        end
    end,
}

---@return Parser
Parser.new = function()
    return utils.new(Parser, {
        ffi = ffi,
        clang = clang,
        nodemap = {},
        node_count = 0,
        reverse_reference_map = {},
    })
end

return Parser
