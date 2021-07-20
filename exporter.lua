local utils = require("utils")
local TypeMap = require("typemap")
local clang = require("clang")
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
            return string.format("%s %s", p.cursor_kind, p.name)
        end)
        return string.format("%s%s %s(%s)", prefix, self.result_type, self.name, table.concat(params, ", "))
    end,
}

---@param node Node
---@return Function
Function.new = function(node)
    return utils.new(Function, {
        dll_export = node.dll_export,
        name = node.spelling,
        params = {},
        result_type = node.result_type,
    })
end

---@class Exporter
---@field functions Function[]
local Exporter = {

    ---@return string
    __tostring = function(self)
        local result = "// " .. self.header .. "\n"
        for i, f in ipairs(self.functions) do
            result = result .. string.format("%s\n", f)
        end
        return result
    end,

    ---@param self Exporter
    ---@param node Node
    ---@return Function
    export = function(self, node)
        local f = Function.new(node)
        table.insert(self.functions, f)
        return f
    end,
}

---@param header string
---@param link string
---@return Exporter
Exporter.new = function(header, link)
    return utils.new(Exporter, {
        header = header,
        link = link,
        functions = {},
    })
end

return Exporter
