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

---@param node Node
---@return Function
Function.new = function(node)
    local params = utils.filter(node.children, function(c)
        return c.cursor_kind == C.CXCursor_ParmDecl
    end)
    return utils.new(Function, {
        dll_export = node.dll_export,
        name = node.spelling,
        params = params,
        result_type = node.result_type,
    })
end

---@class Exporter
---@field link string
---@field headers string[]
---@field functions Function[]
local Exporter = {

    ---@return string
    __tostring = function(self)
        local result = "// " .. self.link .. "\n"
        for i, f in ipairs(self.functions) do
            result = result .. string.format("%s\n", f)
        end
        return result
    end,

    ---@param self Exporter
    ---@param node Node
    ---@return Function
    export_function = function(self, node)
        local f = Function.new(node)
        table.insert(self.functions, f)
        return f
    end,

    ---@param self Exporter
    ---@param node Node
    export = function(self, node)
        if node.cursor_kind == clang.C.CXCursor_FunctionDecl then
            for i, header in ipairs(self.headers) do
                if node.location.path == header then
                    local f = self:export_function(node)
                    return f
                end
            end
        end
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
