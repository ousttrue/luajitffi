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
---@field reverse_reference_map table<integer, Node[]>
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

        local tu = clang.clang_parseTranslationUnit(
            index,
            path,
            array,
            #arguments,
            unsaved,
            n_unsaved,
            mod.enums.CXTranslationUnit_Flags.CXTranslationUnit_DetailedPreprocessingRecord
        )

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

        if cursor.kind == CXCursorKind.CXCursor_TranslationUnit then
        elseif cursor.kind == CXCursorKind.CXCursor_MacroDefinition then
        elseif cursor.kind == CXCursorKind.CXCursor_InclusionDirective then
        elseif cursor.kind == CXCursorKind.CXCursor_MacroExpansion then
        elseif cursor.kind == CXCursorKind.CXCursor_UnexposedDecl then
        elseif cursor.kind == CXCursorKind.CXCursor_ClassTemplate then
        elseif cursor.kind == CXCursorKind.CXCursor_TemplateTypeParameter then
        elseif cursor.kind == CXCursorKind.CXCursor_CXXTypeidExpr then
        elseif cursor.kind == CXCursorKind.CXCursor_ClassTemplatePartialSpecialization then
        elseif cursor.kind == CXCursorKind.CXCursor_StaticAssert then
        elseif cursor.kind == CXCursorKind.CXCursor_DeclRefExpr then
        elseif cursor.kind == CXCursorKind.CXCursor_TemplateRef then
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
        elseif cursor.kind == CXCursorKind.CXCursor_UnaryOperator then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_BinaryOperator then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_ParenExpr then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_CXXBoolLiteralExpr then
        elseif cursor.kind == CXCursorKind.CXCursor_DLLImport then
            --skip
        elseif cursor.kind == CXCursorKind.CXCursor_StringLiteral then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_IntegerLiteral then
            node.tokens = clang_util.get_tokens(cursor)
        elseif cursor.kind == CXCursorKind.CXCursor_FunctionDecl then
            node.node_type = "function"
            local cxType = clang.clang_getCursorResultType(cursor)
            local t, is_const = types.type_from_cx_type(cxType, cursor)
            node.type = t
            node.is_const = is_const
        elseif cursor.kind == CXCursorKind.CXCursor_ParmDecl then
            node.node_type = "param"
            local cxType = clang.clang_getCursorType(cursor)
            local t, is_const = types.type_from_cx_type(cxType, cursor)
            node.type = t
            node.is_const = is_const
        elseif cursor.kind == CXCursorKind.CXCursor_FieldDecl then
            node.node_type = "field"
            local cxType = clang.clang_getCursorType(cursor)
            local t, is_const = types.type_from_cx_type(cxType, cursor)
            node.type = t
            -- node.is_const = is_const
        elseif cursor.kind == CXCursorKind.CXCursor_TypeRef then
            node.node_type = "typeref"
            local referenced = clang.clang_getCursorReferenced(cursor)
            local ref_hash = clang.clang_hashCursor(referenced)
            node.ref_hash = ref_hash

            local ref_list = self.reverse_reference_map[ref_hash]
            if not ref_list then
                ref_list = {}
                self.reverse_reference_map[ref_hash] = ref_list
            end
            table.insert(ref_list, node)
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
        else
            assert(false)
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

    -- 不要な typedef
    -- typedef Tag struct {} Name;
    -- 的なのを除去する
    ---@param self Parser
    ---@return integer
    resolve_typedef = function(self)
        local count = 0
        for stack, node in self.root:traverse() do
            if node.node_type == "typedef" then
                local replace = self:replace_typedef(node)
                if replace then
                    -- replace parent
                    local path = utils.map(stack, function(x)
                        return x
                    end)
                    table.remove(path)
                    local parent = self.root:from_path(path)
                    assert(parent)
                    parent:replace_child(node, replace)

                    -- replace reference
                    local ref_list = self.reverse_reference_map[node.hash]
                    if ref_list then
                        for j, x in ipairs(ref_list) do
                            x.ref_hash = replace.hash
                        end
                    end
                    count = count + 1
                end
            end
        end

        return count
    end,
}

---@return Parser
Parser.new = function()
    return utils.new(Parser, {
        ffi = ffi,
        clang = clang,
        nodemap = {},
        reverse_reference_map = {},
    })
end

return Parser
