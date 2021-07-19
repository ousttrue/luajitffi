local utils = require("utils")

---@class Type
---@field name string
local Type = {}

---@class TypeMap
---@field typemap Table<Node, Type>
local TypeMap = {
    ---@param self TypeMap
    ---@param node Node
    get_or_create = function(self, node)
        local t = self.typemap[node]
        if t then
            return t
        end

        -- local cx_type = clang. unsafe { clang_getCursorResultType(cursor)        

        t = utils.new(Type, {
            name = node.spelling,
        })
        self.typemap[node] = t
        return t
    end,
}

---@type TypeMap
local typemap = utils.new(TypeMap, {
    typemap = {},
})

return typemap
