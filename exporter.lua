local ffi = require("ffi")
local C = ffi.C
local utils = require("utils")
local typemap = require("typemap")

---@class Param
---@field name string
---@field type string
local Param = {}

---@class Function
---@field dll_export boolean
---@field name string
---@field params Param[]
---@field return_type string
local Function = {
    ---@return string
    __tostring = function(self)
        local prefix = ""
        if self.dll_export then
            prefix = "extern "
        end
        local params = utils.map(self.params, function(p)
            if p.type then
                return string.format("%s %s", p.type, p.name)
            else
                return p.name
            end
        end)
        return string.format("%s%s %s(%s)", prefix, self.return_type, self.name, table.concat(params, ", "))
    end,
}

---@param name string
---@return Function
Function.new = function(name)
    return utils.new(Function, {
        dll_export = false,
        name = name,
        params = {},
        return_type = "void",
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
        local f = Function.new(node.spelling)

        for path, node in node:traverse() do
            if node.type == C.CXCursor_FunctionDecl then
            elseif node.type == C.CXCursor_DLLImport then
                f.dll_export = true
            elseif node.type == C.CXCursor_ParmDecl then
                local param = utils.new(Param, {
                    name = node.spelling,
                })
                table.insert(f.params, param)
            elseif node.type == C.CXCursor_TypeRef then
                if #f.params == 0 then
                    f.return_type = typemap:get_or_create(node)
                else
                    f.params[#f.params].type = typemap:get_or_create(node)
                end
            else
                print(node)
            end
        end

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
