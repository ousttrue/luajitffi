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
---@field src ExportHeader
---@field set_type fun(node:Node):nil

---@class Exporter
---@field nodemap Table<integer, Node>
---@field map Table<string, ExportHeader>
---@field export_list RefSrcDst[]
---@field used Table<Node, boolean>
local Exporter = {

    ---@param self Exporter
    ---@param path string
    ---@param parent ExportHeader
    ---@return ExportHeader
    get_or_create_header = function(self, path, parent)
        local export_header = self.map[path]
        if not export_header then
            export_header = ExportHeader.new(path)
            self.map[path] = export_header
            table.insert(parent.includes, export_header)
        end
        return export_header
    end,

    ---@param self Exporter
    ---@param dst Node
    ---@param src ExportHeader
    ---@param set_type fun(t:any, node:Node):nil
    ---@param t any
    ---@return Ref
    push_ref = function(self, dst, src, set_type, t)
        assert(set_type)
        assert(getmetatable(src) == ExportHeader)
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
    push = function(self, node)
        table.insert(self.export_list, { node = node, src = self.root })
    end,

    ---@param self Exporter
    ---@param node Node
    ---@return Function
    export_function = function(self, node, is_method)
        local export_header = self:get_or_create_header(node.location.path, self.root)
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

        local function export_param(param_node)
            local p = utils.new(types.Param, {
                name = param_node.spelling,
                type = param_node.type,
                is_const = param_node.is_const,
            })
            p.default_value = get_default_value(param_node.tokens)
            if types.is_functionproto(param_node.type) then
                self:export_functionproto(param_node)
            end

            if param_node.children then
                for i, x in ipairs(param_node.children) do
                    if x.cursor_kind == CXCursorKind.CXCursor_TypeRef then
                        -- param
                        local ref_node = self.nodemap[x.ref_hash]
                        assert(ref_node)
                        self:push_ref(ref_node, self.map[node.location.path], p.set_type, p)
                    else
                        -- other descendant
                    end
                end
            end

            return p
        end

        if node.children then
            for i, x in ipairs(node.children) do
                if
                    x.cursor_kind == CXCursorKind.CXCursor_DLLImport
                    or x.cursor_kind == CXCursorKind.CXCursor_DLLExport
                then
                    t.dll_export = true
                elseif x.cursor_kind == CXCursorKind.CXCursor_TypeRef then
                    local ref_node = self.nodemap[x.ref_hash]
                    assert(ref_node)
                    -- return
                    self:push_ref(ref_node, self.map[node.location.path], t.set_result_type, t)
                elseif x.cursor_kind == CXCursorKind.CXCursor_ParmDecl then
                    local p = export_param(x)
                    table.insert(t.params, p)
                elseif x.cursor_kind == CXCursorKind.CXCursor_FunctionDecl then
                    --
                elseif x.cursor_kind == CXCursorKind.CXCursor_UnexposedAttr then
                    -- CINDEX_DEPRECATED
                elseif x.cursor_kind == CXCursorKind.CXCursor_TemplateRef then
                    --
                else
                    assert(false)
                end
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
    export_functionproto = function(self, node)
        local function export_param(param_node)
            local p = utils.new(types.Param, {
                name = param_node.spelling,
                type = param_node.type,
                is_const = param_node.is_const,
            })

            if param_node.children then
                for i, x in ipairs(param_node.children) do
                    if x.cursor_kind == CXCursorKind.CXCursor_TypeRef then
                        local ref_node = self.nodemap[x.ref_hash]
                        assert(ref_node)
                        self:push_ref(
                            ref_node,
                            self.map[node.location.path],
                            p.set_type,
                            p
                        )
                    end
                end
            end

            return p
        end

        if node.children then
            local t = node.type.pointee
            for i, x in ipairs(node.children) do
                if x.cursor_kind == CXCursorKind.CXCursor_TypeRef then
                    -- return
                    local ref_node = self.nodemap[x.ref_hash]
                    assert(ref_node)
                    self:push_ref(ref_node, self.map[node.location.path], t.set_result_type, t)
                elseif x.cursor_kind == CXCursorKind.CXCursor_ParmDecl then
                    local p = export_param(x)
                    table.insert(t.params, p)
                else
                    assert(false)
                end
            end
        end
    end,

    ---@param self Exporter
    ---@param node Node
    ---@return Enum
    export_enum = function(self, node, parent)
        local export_header = self:get_or_create_header(node.location.path, parent)
        local t = utils.new(types.Enum, {
            name = node.spelling,
            location = node.location,
            values = {},
        })

        if node.children then
            for i, x in ipairs(node.children) do
                if x.cursor_kind == CXCursorKind.CXCursor_EnumConstantDecl then
                    local e = utils.new(types.EnumConst, {
                        name = x.spelling,
                        value = x.value,
                    })
                    table.insert(t.values, e)

                    if x.children then
                        for j, y in ipairs(x.children) do
                            if y.cursor_kind == CXCursorKind.CXCursor_IntegerLiteral then
                                e.value = table.concat(y.tokens, " ")
                            elseif y.cursor_kind == CXCursorKind.CXCursor_DeclRefExpr then
                                e.value = y.spelling
                            elseif y.cursor_kind == CXCursorKind.CXCursor_BinaryOperator then
                                e.value = table.concat(y.tokens, " ")
                            elseif y.cursor_kind == CXCursorKind.CXCursor_UnaryOperator then
                                e.value = table.concat(y.tokens, "")
                            elseif y.cursor_kind == CXCursorKind.CXCursor_ParenExpr then
                                e.value = table.concat(y.tokens, "")
                            elseif y.cursor_kind == CXCursorKind.CXCursor_UnexposedExpr then
                            elseif y.cursor_kind == CXCursorKind.CXCursor_MacroExpansion then
                            else
                                assert(false, string.format("unknown CXCurosrKind: %s", y.cursor_kind))
                            end
                        end
                    end
                elseif x.cursor_kind == CXCursorKind.CXCursor_MacroDefinition then
                else
                    assert(false)
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
    export_typedef = function(self, node, parent)
        local export_header = self:get_or_create_header(node.location.path, parent)
        local t = utils.new(types.Typedef, {
            name = node.spelling,
            location = node.location,
            type = node.type,
        })

        if types.is_functionproto(node.type) then
            self:export_functionproto(node)
        else
            if node.children then
                for i, x in ipairs(node.children) do
                    if x.node_type == "typeref" then
                        local ref_node = self.nodemap[x.ref_hash]
                        assert(ref_node)
                        self:push_ref(ref_node, self.map[node.location.path], t.set_type, t)
                    elseif x.node_type == "struct" or x.node_type == "union" then
                        -- tyepdef struct {} hoge;
                        t:set_type(self:export(x))
                    elseif x.node_type == "enum" then
                        -- typedef enum {} hoge;
                        t:set_type(self:export(x))
                    elseif x.node_type == "typedef" then
                        t:set_type(self:export(x))
                    else
                        assert(false)
                    end
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
    export_struct = function(self, node, parent)
        local export_header = self:get_or_create_header(node.location.path, parent)
        local t = utils.new(types.Struct, {
            name = node.spelling,
            location = node.location,
            fields = {},
            methods = {},
        })

        local function export_field(field_node)
            local f = utils.new(types.Field, {
                name = field_node.spelling,
                type = field_node.type,
            })

            if types.is_functionproto(field_node.type) then
                self:export_functionproto(field_node)
            end

            if field_node.children then
                for _, x in ipairs(field_node.children) do
                    if x.cursor_kind == CXCursorKind.CXCursor_TypeRef then
                        local ref_node = self.nodemap[x.ref_hash]
                        assert(ref_node)
                        if f.type == "template" then
                            -- template argument
                            self:push_ref(ref_node, self.map[node.location.path], function()
                                -- do nothing
                            end, f)
                        else
                            self:push_ref(ref_node, self.map[node.location.path], f.set_type, f)
                        end
                    elseif x.cursor_kind == CXCursorKind.CXCursor_TemplateRef then
                        local ref_node = self.nodemap[x.ref_hash]
                        assert(ref_node)
                        assert(f.type == "template" or f.type.pointee == "template" or f.type.element == "template")
                        self:push_ref(ref_node, self.map[node.location.path], f.set_type, f)
                    elseif x.cursor_kind == CXCursorKind.CXCursor_IntegerLiteral then
                    elseif x.cursor_kind == CXCursorKind.CXCursor_DeclRefExpr then
                    elseif
                        x.cursor_kind == CXCursorKind.CXCursor_DLLImport
                        or x.cursor_kind == CXCursorKind.CXCursor_DLLExport
                    then
                        if field_node.node_type == "method" then
                            t.methods[#t.methods].dll_export = true
                        else
                            a = 0
                        end
                    else
                        -- assert(false)
                    end
                end
            end
            return f
        end

        if node.children then
            for i, x in ipairs(node.children) do
                if x.cursor_kind == CXCursorKind.CXCursor_FieldDecl then
                    local f = export_field(x)
                    table.insert(t.fields, f)
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
    ---@param parent Struct
    ---@return Node
    export = function(self, node, parent)
        local found = self.used[node]
        if found then
            return found
        end

        if node.node_type == "function" then
            return self:export_function(node)
        elseif node.node_type == "enum" then
            return self:export_enum(node, parent)
        elseif node.node_type == "typedef" then
            return self:export_typedef(node, parent)
        elseif node.node_type == "struct" or node.node_type == "union" or node.node_type == "class_template" then
            return self:export_struct(node, parent)
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
                local t = self:export(ref.node, ref.src)
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
        root = ExportHeader.new(),
    })
end

return Exporter
