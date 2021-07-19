local utils = require("utils")
local clang = require("clang")
local C = clang.C

---@class Type
---@field name string
local Type = {}

---@class TypeMap
---@field typemap Table<integer, Type>
local TypeMap = {
    ---@param self TypeMap
    ---@param cursor any
    ---@param cxType any
    get_or_create = function(self, cursor, cxType)
        local c = clang.dll.clang_hashCursor(cursor)
        local t = self.typemap[c]
        if t then
            return t
        end

        if cxType.kind == C.CXType_Void then
            t = utils.new(Type, {
                name = "void",
            })
        else
            print(cxType.kind)
            assert(false)
        end

        self.typemap[c] = t
        return t
    end,
}

TypeMap.new = function()
    return utils.new(TypeMap, {
        typemap = {},
    })
end

return TypeMap
