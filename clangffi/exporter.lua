local utils = require("clangffi.utils")
local types = require("clangffi.types")
local clang = require("clangffi.clang")
local C = clang.C

---@class ExportHeader
---@field header string
---@field types any[]
---@field functions Function[]
local ExportHeader = {
    ---@param self ExportHeader
    ---@return string
    __tostring = function(self)
        return string.format("%s (%d funcs) (%d types)", self.header, #self.functions, #self.types)
    end,
}

---@param header string
---@return ExportHeader
ExportHeader.new = function(header)
    return utils.new(ExportHeader, {
        header = header,
        types = {},
        functions = {},
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
                    local parent = self.nodemap[x.parent_hash]

                    -- return
                    t.result = self:export(ref_node)
                elseif x.cursor_kind == C.CXCursor_ParmDecl then
                    table.insert(t.params, x)
                elseif x.cursor_kind == C.CXCursor_UnexposedAttr then
                    -- CINDEX_DEPRECATED
                    local parent = self.nodemap[x.parent_hash]
                    local a = 0
                else
                    assert(false)
                end
            elseif #stack == 2 then
                if x.cursor_kind == C.CXCursor_TypeRef then
                    -- param
                    table.insert(t.params, ref_node)
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
                    table.insert(t.values, x)
                else
                    assert(false)
                end
            else
            end
        end
        table.insert(export_header.types, t)
        self.used[node] = t
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
                    table.insert(t.fields, x)
                elseif x.cursor_kind == C.CXCursor_TypeRef then
                    -- assert(false)
                else
                    -- nested type
                    assert(false)
                end
            else
                -- nested
            end
        end

        if t.name == nil or t.name == "" then
            a = 0
        end
        table.insert(export_header.types, t)
        self.used[node] = t
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
