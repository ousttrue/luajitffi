local function new(class_table, instance_table)
    class_table.__index = class_table
    return setmetatable(instance_table, class_table)
end

---@class Function
---@field name string
local Function = {
    ---@return string
    __tostring = function(self)
        return string.format("%s()", self.name)
    end,
}

---@param name string
---@return Function
Function.new = function(name)
    return new(Function, {
        name = name,
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
    export = function(self, node)
        table.insert(self.functions, Function.new(node.spelling))
    end,
}

---@param header string
---@param link string
---@return Exporter
Exporter.new = function(header, link)
    return new(Exporter, {
        header = header,
        link = link,
        functions = {},
    })
end

return Exporter
