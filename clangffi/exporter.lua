local utils = require("clangffi.utils")
local types = require("clangffi.types")
local mod = require("clang.mod")
local clang = mod.libs.clang
local CXCursorKind = mod.enums.CXCursorKind

---@class ExportHeader
---@field header string
---@field functions Function[]
---@field types any[]
---@field includes ExportHeader[]
local ExportHeader = {
    ---@param self ExportHeader
    ---@return string
    __tostring = function(self)
        return string.format("%s (%d funcs)(%d types)", self.header, #self.functions, #self.types)
    end,

    ---@param self ExportHeader
    sort = function(self)
        table.sort(self.types, function(a, b)
            return a.location.line < b.location.line
        end)
    end,
}

---@param header string
---@return ExportHeader
ExportHeader.new = function(header)
    return utils.new(ExportHeader, {
        header = header,
        functions = {},
        types = {},
        includes = {},
    })
end

---@param tokens string[]
---@return string
local function get_default_value(tokens)
    for i, t in ipairs(tokens) do
        if t == "=" then
            return table.concat(tokens, "", i + 1)
        end
    end
end

---@class RefSrcDst
---@field node Node
---@field src Node
---@field set_type fun(node:Node):nil

---@class Exporter
---@field nodemap Table<integer, Node>
---@field map Table<string, ExportHeader>
---@field export_list RefSrcDst[]
---@field used Table<Node, boolean>
local Exporter = {

    ---@param self Exporter
    ---@param path string
    ---@return ExportHeader
    get_or_create_header = function(self, path)
        local export_header = self.map[path]
        if not export_header then
            export_header = ExportHeader.new(path)
            self.map[path] = export_header
        end
        return export_header
    end,

    ---@param self Exporter
    ---@param dst Node
    ---@param src Node
    ---@param set_type fun(t:any, node:Node):nil
    ---@param t any
    ---@return Ref
    push_ref = function(self, dst, src, set_type, t)
        assert(set_type)
        local ref = utils.new(types.Ref, {
            node = dst,
            src = src,
            set_type = function(node)
                set_type(t, node)
            end,
        })
        table.insert(self.export_list, ref)
        return ref
    end,

    ---@param self Exporter
    ---@param node Node
    ---@return Function
    export_function = function(self, node, is_method)
        local export_header = self:get_or_create_header(node.location.path)
        local t = utils.new(types.Function, {
            dll_export = false,
            name = node.spelling,
            mangling = node.mangling,
            location = node.location,
            params = {},
            result_type = node.type,
            result_is_const = node.is_const,
            is_variadic = node.is_variadic,
        })

        for stack, x in node:traverse() do
            if #stack == 0 then
                -- skip self
            elseif #stack == 1 then
                if
                    x.cursor_kind == CXCursorKind.CXCursor_DLLImport
                    or x.cursor_kind == CXCursorKind.CXCursor_DLLExport
                then
                    t.dll_export = true
                elseif x.cursor_kind == CXCursorKind.CXCursor_TypeRef then
                    local ref_node = self.nodemap[x.ref_hash]
                    assert(ref_node)
                    -- return
                    self:push_ref(ref_node, node, t.set_result_type, t)
                elseif x.cursor_kind == CXCursorKind.CXCursor_ParmDecl then
                    local p = utils.new(types.Param, {
                        name = x.spelling,
                        type = x.type,
                        is_const = x.is_const,
                    })
                    p.default_value = get_default_value(x.tokens)
                    table.insert(t.params, p)

                    if types.is_functionproto(x.type) then
                        self:export_functionproto(x)
                    end
                elseif x.cursor_kind == CXCursorKind.CXCursor_FunctionDecl then
                    --
                elseif x.cursor_kind == CXCursorKind.CXCursor_UnexposedAttr then
                    -- CINDEX_DEPRECATED
                elseif x.cursor_kind == CXCursorKind.CXCursor_TemplateRef then
                    --
                else
                    assert(false)
                end
            elseif #stack == 2 then
                if x.cursor_kind == CXCursorKind.CXCursor_TypeRef then
                    -- param
                    local ref_node = self.nodemap[x.ref_hash]
                    assert(ref_node)
                    self:push_ref(ref_node, node, t.params[#t.params].set_type, t.params[#t.params])
                else
                    -- other descendant
                end
            else
                -- skip
            end
        end

        if not is_method then
            table.insert(export_header.functions, t)
            self.used[node] = t
        end
        return t
    end,

    ---@param self Exporter
    ---@param node Node
    ---@return FunctionProto
    export_functionproto = function(self, node)
        local t = node.type.pointee
        for stack, x in node:traverse() do
            if #stack == 0 then
                -- skip self
            elseif #stack == 1 then
                if x.cursor_kind == CXCursorKind.CXCursor_TypeRef then
                    local ref_node = self.nodemap[x.ref_hash]
                    assert(ref_node)
                    -- return
                    self:push_ref(ref_node, node, t.set_result_type, t)
                elseif x.cursor_kind == CXCursorKind.CXCursor_ParmDecl then
                    local p = utils.new(types.Param, {
                        name = x.spelling,
                        type = x.type,
                        is_const = x.is_const,
                    })
                    table.insert(t.params, p)
                else
                    assert(false)
                end
            elseif #stack == 2 then
                if x.cursor_kind == CXCursorKind.CXCursor_TypeRef then
                    -- if parent.node_type == "param" then
                    -- param
                    local ref_node = self.nodemap[x.ref_hash]
                    assert(ref_node)
                    self:push_ref(ref_node, node, t.params[#t.params].set_type, t.params[#t.params])
                    -- else
                    --     -- assert(false)
                    -- end
                else
                    -- other descendant
                end
            else
                -- skip
            end
        end
        return t
    end,

    ---@param self Exporter
    ---@param node Node
    ---@return Enum
    export_enum = function(self, node)
        local export_header = self:get_or_create_header(node.location.path)
        local t = utils.new(types.Enum, {
            name = node.spelling,
            location = node.location,
            values = {},
        })

        for stack, x in node:traverse() do
            if #stack == 0 then
                -- self
            elseif #stack == 1 then
                if x.cursor_kind == CXCursorKind.CXCursor_EnumConstantDecl then
                    table.insert(
                        t.values,
                        utils.new(types.EnumConst, {
                            name = x.spelling,
                            value = x.value,
                        })
                    )
                elseif x.cursor_kind == CXCursorKind.CXCursor_MacroDefinition then
                else
                    assert(false)
                end
            elseif #stack == 2 then
                if x.cursor_kind == CXCursorKind.CXCursor_IntegerLiteral then
                    t.values[#t.values].value = table.concat(x.tokens, " ")
                elseif x.cursor_kind == CXCursorKind.CXCursor_DeclRefExpr then
                    t.values[#t.values].value = x.spelling
                elseif x.cursor_kind == CXCursorKind.CXCursor_BinaryOperator then
                    t.values[#t.values].value = table.concat(x.tokens, " ")
                elseif x.cursor_kind == CXCursorKind.CXCursor_UnaryOperator then
                    t.values[#t.values].value = table.concat(x.tokens, "")
                elseif x.cursor_kind == CXCursorKind.CXCursor_ParenExpr then
                    t.values[#t.values].value = table.concat(x.tokens, "")
                elseif x.cursor_kind == CXCursorKind.CXCursor_UnexposedExpr then
                elseif x.cursor_kind == CXCursorKind.CXCursor_MacroExpansion then
                else
                    assert(false, string.format("unknown CXCurosrKind: %s", x.cursor_kind))
                end
            end
        end

        if not types.is_anonymous(t) then
            table.insert(export_header.types, t)
            self.used[node] = t
        end

        return t
    end,

    ---@param self Exporter
    ---@param node Node
    ---@return Typedef
    export_typedef = function(self, node)
        local export_header = self:get_or_create_header(node.location.path)
        local t = utils.new(types.Typedef, {
            name = node.spelling,
            location = node.location,
            type = node.type,
        })

        if types.is_functionproto(node.type) then
            self:export_functionproto(node)
        else
            for stack, x in node:traverse() do
                if #stack == 0 then
                    -- self
                elseif #stack == 1 then
                    if x.node_type == "typeref" then
                        local ref_node = self.nodemap[x.ref_hash]
                        assert(ref_node)
                        self:push_ref(ref_node, node, t.set_type, t)
                    elseif x.node_type == "struct" or x.node_type == "union" then
                        -- tyepdef struct {} hoge;
                        t:set_type(self:export(x))
                    elseif x.node_type == "enum" then
                        -- typedef enum {} hoge;
                        t:set_type(self:export(x))
                    elseif x.node_type == "typedef" then
                        t:set_type(self:export(x))
                    elseif x.node_type == "param" then
                        -- TODO: function pointer ?
                    else
                        assert(false)
                    end
                else
                    -- nested skip
                end
            end
        end

        table.insert(export_header.types, t)
        self.used[node] = t
        return t
    end,

    ---@param self Exporter
    ---@param node Node
    ---@return Struct
    export_struct = function(self, node)
        local export_header = self:get_or_create_header(node.location.path)
        local t = utils.new(types.Struct, {
            name = node.spelling,
            location = node.location,
            fields = {},
            methods = {},
        })

        for stack, x in node:traverse() do
            if #stack == 0 then
                --self
            elseif #stack == 1 then
                if x.cursor_kind == CXCursorKind.CXCursor_FieldDecl then
                    table.insert(
                        t.fields,
                        utils.new(types.Field, {
                            name = x.spelling,
                            type = x.type,
                        })
                    )

                    if types.is_functionproto(x.type) then
                        self:export_functionproto(x)
                    end
                elseif x.cursor_kind == CXCursorKind.CXCursor_CXXMethod then
                    local m = self:export_function(x, true)
                    m.name = string.format("%s_%s", t.name, x.spelling)
                    table.insert(
                        m.params,
                        1,
                        utils.new(types.Param, {
                            name = "this",
                            type = utils.new(types.Pointer, {
                                pointee = t,
                            }),
                        })
                    )
                    table.insert(t.methods, m)

                    if types.is_functionproto(x.type) then
                        self:export_functionproto(x)
                    end
                elseif x.cursor_kind == CXCursorKind.CXCursor_TypeRef then
                    assert(false)
                else
                    -- nested type
                    -- assert(false)
                end
            elseif #stack == 2 then
                local copy = utils.imap(stack)
                table.remove(copy)
                local parent = node:from_path(copy)

                if x.cursor_kind == CXCursorKind.CXCursor_TypeRef then
                    if parent.node_type == "field" then
                        local ref_node = self.nodemap[x.ref_hash]
                        assert(ref_node)
                        local f = t.fields[#t.fields]
                        if f.type == "template" then
                            -- template argument
                            self:push_ref(ref_node, node, function()
                                -- do nothing
                            end, f)
                        else
                            self:push_ref(ref_node, node, f.set_type, f)
                        end
                    elseif parent.node_type == "method" then
                    elseif parent.node_type == "typedef" then
                    elseif parent.node_type == "base_class" then
                    else
                        assert(false)
                    end
                elseif x.cursor_kind == CXCursorKind.CXCursor_TemplateRef then
                    if parent.node_type == "field" then
                        local ref_node = self.nodemap[x.ref_hash]
                        assert(ref_node)
                        local f = t.fields[#t.fields]
                        assert(f.type == "template" or f.type.pointee == "template" or f.type.element == "template")
                        self:push_ref(ref_node, node, f.set_type, f)
                    elseif parent.node_type == "method" then
                        local ref_node = self.nodemap[x.ref_hash]
                        assert(ref_node)
                        local m = t.methods[#t.methods]
                        self:push_ref(ref_node, node, m.set_result_type, m)
                    else
                        assert(false)
                    end
                elseif x.cursor_kind == CXCursorKind.CXCursor_IntegerLiteral then
                elseif x.cursor_kind == CXCursorKind.CXCursor_DeclRefExpr then
                elseif
                    x.cursor_kind == CXCursorKind.CXCursor_DLLImport
                    or x.cursor_kind == CXCursorKind.CXCursor_DLLExport
                then
                    if parent.node_type == "method" then
                        t.methods[#t.methods].dll_export = true
                    else
                        a = 0
                    end
                else
                    -- assert(false)
                end
            else
                -- nested
            end
        end

        if not types.is_anonymous(t) then
            if node.semantic_parent_hash then
                local semantic_parent = self.nodemap[node.semantic_parent_hash]
                local semantic_parent_type = self.used[semantic_parent]
                if not semantic_parent_type.nested then
                    semantic_parent_type.nested = {}
                end
                table.insert(semantic_parent_type.nested, t)
            else
                table.insert(export_header.types, t)
            end
            self.used[node] = t
        end
        return t
    end,

    ---@param self Exporter
    ---@param node Node
    push = function(self, node)
        table.insert(self.export_list, { node = node })
    end,

    ---@param self Exporter
    ---@param node Node
    ---@param parent Struct
    ---@return Node
    export = function(self, node)
        local found = self.used[node]
        if found then
            return found
        end

        if node.node_type == "function" then
            return self:export_function(node)
        elseif node.node_type == "enum" then
            return self:export_enum(node)
        elseif node.node_type == "typedef" then
            return self:export_typedef(node)
        elseif node.node_type == "struct" or node.node_type == "union" or node.node_type == "class_template" then
            return self:export_struct(node)
        elseif not node.node_type then
            return
        else
            assert(false)
        end
    end,

    ---@param self Exporter
    execute = function(self)
        -- export list
        while true do
            if #self.export_list == 0 then
                break
            end

            local export_list = self.export_list
            self.export_list = {}
            for i, ref in ipairs(export_list) do
                local t = self:export(ref.node)
                if ref.set_type then
                    ref.set_type(t)
                end
            end
        end

        -- sort
        for header, export_header in pairs(self.map) do
            export_header:sort()

            -- resolve same name function
            local functions = export_header.functions
            export_header.functions = {}
            local name_map = {}
            for i, f in ipairs(functions) do
                assert(f.name)
                local found = name_map[f.name]
                if found then
                    if not found.same_name then
                        found.same_name = {}
                    end
                    table.insert(found.same_name, f)
                else
                    name_map[f.name] = f
                    table.insert(export_header.functions, f)
                end
            end
        end
    end,
}

---@param nodemap Table<integer, Node>
---@return Exporter
Exporter.new = function(nodemap)
    return utils.new(Exporter, {
        nodemap = nodemap,
        map = {},
        used = {},
        export_list = {},
    })
end

return Exporter
