local utils = require("utils")

---@class TypeMap
local TypeMap = {
    ---@param self TypeMap
    ---@param node Node
    get_or_create = function(self, node)
        return node.spelling
    end,
}

local type_map = utils.new(TypeMap, {})

return type_map
