local utils = require("clangffi.utils")
local types = require("clangffi.types")
local clang = require("clangffi.clang")
local C = clang.C

---@class ExportHeader
---@field header string
---@field types Type[]
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
local Exporter = {

    ---@param self Exporter
    ---@param export_header ExportHeader
    ---@param node Node
    ---@return Function
    export_function = function(self, export_header, node)
        -- functions
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
                local ref = self.nodemap[x.ref_hash]
                assert(ref)
                local parent = self.nodemap[x.parent_hash]
                local d = x.level - parent.level + 1
                if d == 1 then
                    -- return
                    f.result = ref
                elseif d == 2 then
                    -- param
                    table.insert(f.params, ref)
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
        if not f.dll_export then
            return
        end

        table.insert(export_header.functions, f)

        -- types

        return f
    end,

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
    export = function(self, node)
        if node.cursor_kind ~= clang.C.CXCursor_FunctionDecl then
            return
        end

        local export_header = self.headers[node.location.path]
        if not export_header then
            return
        end

        local f = self:export_function(export_header, node)
        return f
    end,
}

---@param nodemap Table<integer, Node>
---@return Exporter
Exporter.new = function(nodemap)
    return utils.new(Exporter, {
        nodemap = nodemap,
        headers = {},
    })
end

return Exporter
