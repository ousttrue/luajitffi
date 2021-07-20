local utils = require("clangffi.utils")
local clang = require("clangffi.clang")
local C = clang.C

---@class Param
---@field node Node
---@field name string
---@field type Type
local Param = {}

---@param node Node
---@return Node
Param.new = function(node)
    return utils.new(Param, {
        node = node,
        name = node.spelling,
    })
end

---@class Function
---@field dll_export boolean
---@field name string
---@field params Param[]
---@field result_type Type
local Function = {
    ---@return string
    __tostring = function(self)
        local prefix = ""
        if self.dll_export then
            prefix = "extern "
        end
        local params = utils.map(self.params, function(p)
            assert(p.cursor_kind)
            return string.format("%s %s", p.param_type, p.spelling)
        end)
        return string.format("%s%s %s(%s)", prefix, self.result_type, self.name, table.concat(params, ", "))
    end,
}

---@class ExportHeader
---@field header string
---@field types Type[]
---@field functions Function[]
local ExportHeader = {}

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
---@field headers Table<string, ExportHeader>
local Exporter = {

    ---@return string
    __tostring = function(self)
        local result = ""
        for i, f in ipairs(self.functions) do
            result = result .. string.format("%s\n", f)
        end
        return result
    end,

    ---@param self Exporter
    ---@param export_header ExportHeader
    ---@param node Node
    ---@return Function
    export_function = function(self, export_header, node)
        local params = {}
        if node.children then
            params = utils.filter(node.children, function(c)
                return c.cursor_kind == C.CXCursor_ParmDecl
            end)
        end
        local f = utils.new(Function, {
            dll_export = node.dll_export,
            name = node.spelling,
            params = params,
            result_type = node.result_type,
        })
        table.insert(export_header.functions, f)
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

---@param link string
---@return Exporter
Exporter.new = function(link)
    return utils.new(Exporter, {
        headers = {},
        link = link,
        functions = {},
    })
end

return Exporter
