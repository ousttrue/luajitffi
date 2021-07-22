local utils = require("clangffi.utils")
local types = require("clangffi.types")
local clang = require("clangffi.clang")
local C = clang.C

---@class ExportHeader
---@field header string
---@field functions Function[]
---@field types any[]
local ExportHeader = {
    ---@param self ExportHeader
    ---@return string
    __tostring = function(self)
        return string.format("%s (%d funcs)(%d types)", self.header, #self.functions, #self.types)
    end,
}

---@param header string
---@return ExportHeader
ExportHeader.new = function(header)
    return utils.new(ExportHeader, {
        header = header,
        functions = {},
        types = {},
    })
end

---@class Exporter
---@field nodemap Table<integer, Node>
---@field headers Table<string, ExportHeader>
---@field used Table<Node, boolean>
local Exporter = {

    ---@param self Exporter
    ---@param path string
    ---@return ExportHeader
    get_or_create_header = function(self, path)
        local export_header = self.headers[path]
        if not export_header then
            export_header = ExportHeader.new(path)
            self.headers[path] = export_header
        end
        return export_header
    end,

    ---@param self Exporter
    ---@param node Node
    ---@return Function
    export_function = function(self, node)
        local export_header = self:get_or_create_header(node.location.path)
        local t = utils.new(types.Function, {
            dll_export = false,
            name = node.spelling,
            params = {},
            result_type = node.type,
            result_is_const = node.is_const,
        })

        for stack, x in node:traverse() do
            if #stack == 0 then
                -- skip self
            elseif #stack == 1 then
                if x.cursor_kind == C.CXCursor_DLLImport then
                    t.dll_export = true
                elseif x.cursor_kind == C.CXCursor_TypeRef then
                    local ref_node = self.nodemap[x.ref_hash]
                    assert(ref_node)
                    -- return
                    t.result_type = self:export(ref_node)
                elseif x.cursor_kind == C.CXCursor_ParmDecl then
                    local p = utils.new(types.Param, {
                        name = x.spelling,
                        type = x.type,
                        is_const = x.is_const,
                    })
                    table.insert(t.params, p)

                    if types.is_functionproto(x.type) then
                        self:export_functionproto(x)
                    end
                elseif x.cursor_kind == C.CXCursor_UnexposedAttr then
                    -- CINDEX_DEPRECATED
                else
                    assert(false)
                end
            elseif #stack == 2 then
                if x.cursor_kind == C.CXCursor_TypeRef then
                    local parent = self.nodemap[x.parent_hash]
                    assert(parent)
                    -- if parent.node_type == "param" then
                    -- param
                    local ref_node = self.nodemap[x.ref_hash]
                    assert(ref_node)
                    t.params[#t.params].type = self:export(ref_node)
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

        table.insert(export_header.functions, t)
        self.used[node] = t
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
                if x.cursor_kind == C.CXCursor_TypeRef then
                    local ref_node = self.nodemap[x.ref_hash]
                    assert(ref_node)
                    -- return
                    t.result_type = self:export(ref_node)
                elseif x.cursor_kind == C.CXCursor_ParmDecl then
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
                if x.cursor_kind == C.CXCursor_TypeRef then
                    local parent = self.nodemap[x.parent_hash]
                    assert(parent)
                    -- if parent.node_type == "param" then
                    -- param
                    local ref_node = self.nodemap[x.ref_hash]
                    assert(ref_node)
                    t.params[#t.params].type = self:export(ref_node)
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
            values = {},
        })

        for stack, x in node:traverse() do
            if #stack == 0 then
                -- self
            elseif #stack == 1 then
                if x.cursor_kind == C.CXCursor_EnumConstantDecl then
                    table.insert(
                        t.values,
                        utils.new(types.EnumConst, {
                            name = x.spelling,
                            value = x.value,
                        })
                    )
                else
                    assert(false)
                end
            elseif #stack == 2 then
                if x.cursor_kind == C.CXCursor_IntegerLiteral then
                    t.values[#t.values].value = table.concat(x.tokens, " ")
                elseif x.cursor_kind == C.CXCursor_DeclRefExpr then
                    t.values[#t.values].value = x.spelling
                elseif x.cursor_kind == C.CXCursor_BinaryOperator then
                    t.values[#t.values].value = table.concat(x.tokens, " ")
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
    export_typedef = function(self, node)
        local export_header = self:get_or_create_header(node.location.path)
        local t = utils.new(types.Typedef, {
            name = node.spelling,
            type = node.type,
        })
        if types.is_functionproto(node.type) then
            self:export_functionproto(node)
        end

        for stack, x in node:traverse() do
            if #stack == 0 then
                -- self
            elseif #stack == 1 then
                if x.node_type == "typeref" then
                    local ref_node = self.nodemap[x.ref_hash]
                    assert(ref_node)
                    t.type = self:export(ref_node)
                elseif x.node_type == "struct" then
                    -- tyepdef struct {} hoge;
                    t.type = self:export(x)
                elseif x.node_type == "enum" then
                    -- typedef enum {} hoge;
                    t.type = self:export(x)
                elseif x.node_type == "param" then
                    -- TODO: function pointer ?
                else
                    assert(false)
                end
            else
                -- nested skip
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
            fields = {},
        })

        for stack, x in node:traverse() do
            if #stack == 0 then
                --self
            elseif #stack == 1 then
                if x.cursor_kind == C.CXCursor_FieldDecl then
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
                elseif x.cursor_kind == C.CXCursor_TypeRef then
                    assert(false)
                else
                    -- nested type
                    assert(false)
                end
            elseif #stack == 2 then
                if x.cursor_kind == C.CXCursor_TypeRef then
                    local parent = self.nodemap[x.parent_hash]
                    assert(parent)
                    -- if parent.node_type == "field" then
                    local ref_node = self.nodemap[x.ref_hash]
                    assert(ref_node)
                    t.fields[#t.fields].type = self:export(ref_node)
                    -- end
                elseif x.cursor_kind == C.CXCursor_IntegerLiteral then
                elseif x.cursor_kind == C.CXCursor_DeclRefExpr then
                else
                end
            else
                -- nested
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
        elseif node.node_type == "struct" then
            return self:export_struct(node)
        else
            assert(false)
        end
    end,
}

---@param nodemap Table<integer, Node>
---@return Exporter
Exporter.new = function(nodemap)
    return utils.new(Exporter, {
        nodemap = nodemap,
        headers = {},
        used = {},
    })
end

return Exporter
