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

        local f = utils.new(types.Function, {
            dll_export = false,
            name = node.spelling,
            params = {},
        })
        for _, x in node:traverse() do
            if x.cursor_kind == C.CXCursor_FunctionDecl then
                -- skip self
            elseif x.cursor_kind == C.CXCursor_DLLImport then
                f.dll_export = true
            elseif x.cursor_kind == C.CXCursor_TypeRef then
                local ref_node = self.nodemap[x.ref_hash]
                assert(ref_node)
                local parent = self.nodemap[x.parent_hash]
                local d = x.level - parent.level + 1
                if d == 1 then
                    -- return
                    f.result = ref_node
                    self:export(ref_node)
                elseif d == 2 then
                    -- param
                    table.insert(f.params, ref_node)
                else
                    -- other descendant
                    local a = 0
                end
            elseif x.cursor_kind == C.CXCursor_ParmDecl then
                table.insert(f.params, x)
            elseif x.cursor_kind == C.CXCursor_UnexposedAttr then
                -- CINDEX_DEPRECATED
                local parent = self.nodemap[x.parent_hash]
                local a = 0
            else
                assert(false)
            end
        end
        if f.dll_export then
            table.insert(export_header.functions, f)
            self.used[node] = f
        end
    end,

    ---@param self Exporter
    ---@param node Node
    ---@return Function
    export_enum = function(self, node)
        local export_header = self:get_or_create_header(node.location.path)

        local enum = utils.new(types.Enum, {
            name = node.spelling,
            values = {},
        })
        for _, x in node:traverse() do
            if x.cursor_kind == C.CXCursor_EnumDecl then
                -- self
            elseif x.cursor_kind == C.CXCursor_EnumConstantDecl then
                table.insert(enum.values, x)
            elseif x.cursor_kind == C.CXCursor_IntegerLiteral then
                local parent = self.nodemap[x.parent_hash]
                local d = x.level - parent.level + 1
                if d == 2 then
                    a = 0
                else
                    assert(false)
                end
            elseif x.cursor_kind == C.CXCursor_DeclRefExpr then
                -- refrence value
                -- CXType_FirstBuiltin = CXType_Void,
            else
                assert(false)
            end
        end
        table.insert(export_header.types, enum)
        self.used[node] = enum
    end,

    ---@param self Exporter
    ---@param node Node
    ---@return Function
    export_typedef = function(self, node)
        local export_header = self:get_or_create_header(node.location.path)
    end,

    ---@param self Exporter
    ---@param node Node
    export = function(self, node)
        if self.used[node] then
            return
        end

        if node.node_type == "function" then
            self:export_function(node)
        elseif node.node_type == "enum" then
            self:export_enum(node)
        elseif node.node_type == "typedef" then
            self:export_typedef(node)
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
