local utils = require("clangffi.utils")
local clang = require("clangffi.clang")
local C = clang.C

---@class Type
---@field name string
local Type = {
    ---@return string
    __tostring = function(self)
        if self.pointer then
            return tostring(self.pointer) .. "*"
        else
            if self.node and self.node.children then
                -- first typedef
                local filtered = utils.filter(self.node.children, function(c)
                    return c.cursor_kind == C.CXCursor_TypeRef
                end)
                return string.format("%s", filtered[1].spelling)
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

        if cxType.kind == C.CXType_Unexposed then
            -- template T ?
            return utils.new(Type, {
                type = "unexposed",
            })
        end

        -- pointer
        if cxType.kind == C.CXType_Pointer or cxType.kind == C.CXType_LValueReference then
            local pointeeCxType = clang.dll.clang_getPointeeType(cxType)
            local pointeeType = self:get_or_create(node, pointeeCxType)
            return utils.new(Type, {
                pointer = pointeeType,
            })
        elseif cxType.kind == C.CXType_DependentSizedArray then
            local elementCxType = clang.dll.clang_getArrayElementType(cxType)
            local elementType = self:get_or_create(node, elementCxType)
            return utils.new(Type, {
                array = elementType,
            })
        end

        -- function pointer
        if cxType.kind == C.CXType_FunctionProto then
            -- void (*fn)(void *)
            return utils.new(Type, {
                type = "function",
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

---@return TypeMap
TypeMap.new = function()
    return utils.new(TypeMap, {
        typemap = {},
    })
end

return TypeMap
