local utils = require("utils")
local clang = require("clang")
local C = clang.C

---@class Type
---@field name string
local Type = {
    ---@return string
    __tostring = function(self)
        if self.pointer then
            return tostring(self.pointer) .. "*"
        else
            if self.node then
                -- first typedef
                return string.format("%s = %s", self.type, self.node.children[2].spelling)
            else
                return self.type
            end
        end
    end,
}

local Void = utils.new(Type, {
    type = "void",
})
local UInt16 = utils.new(Type, {
    type = "unsigned short",
})
local UInt32 = utils.new(Type, {
    type = "unsigned int",
})
local UInt64 = utils.new(Type, {
    type = "unsigned long long",
})

local Int8 = utils.new(Type, {
    type = "char",
})
local Int32 = utils.new(Type, {
    type = "int",
})
local Int64 = utils.new(Type, {
    type = "long long",
})

local Double = utils.new(Type, {
    type = "double",
})

local primitives = {
    [C.CXType_Void] = Void,

    [C.CXType_WChar] = UInt16, -- Windows
    [C.CXType_UShort] = UInt16,
    [C.CXType_UInt] = UInt32,
    [C.CXType_ULongLong] = UInt64,

    [C.CXType_Char_S] = Int8,
    [C.CXType_Int] = Int32,
    [C.CXType_Long] = Int32,
    [C.CXType_LongLong] = Int64,

    [C.CXType_Double] = Double,
}

---@class TypeMap
---@field typemap Table<integer, Type>
local TypeMap = {
    ---@param self TypeMap
    ---@param node Node
    get_or_create = function(self, node, cxType)
        local t = self.typemap[node]
        if t then
            return t
        end

        local primitive = primitives[tonumber(cxType.kind)]
        if primitive then
            return primitive
        end

        -- pointer
        if cxType.kind == C.CXType_Pointer then
            local pointee = clang.dll.clang_getPointeeType(cxType)
            local base_type = self:get_or_create(node, pointee)
            return utils.new(Type, {
                pointer = base_type,
            })
        end

        -- user type
        if cxType.kind == C.CXType_Typedef then
            t = utils.new(Type, {
                type = "typedef",
                node = node,
            })
        elseif cxType.kind == C.CXType_Elaborated then
            t = utils.new(Type, {
                type = "elaborated",
                node = node,
            })
        else
            assert(false)
        end

        self.typemap[node] = t
        return t
    end,
}

TypeMap.new = function()
    return utils.new(TypeMap, {
        typemap = {},
    })
end

return TypeMap
