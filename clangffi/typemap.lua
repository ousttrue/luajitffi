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
        elseif self.type then
            if self.type == "typedef" then
                return string.format("typedef %s => %s", self.name, self.base_type)
            elseif self.type == "enum" then
                return string.format("enum %s", self.name)
            elseif self.type == "struct" then
                return string.format("struct %s", self.name)
            else
                return self.type
            end
        else
            assert(false)
        end
    end,
}

local Void = utils.new(Type, {
    type = "void",
})

local Bool = utils.new(Type, {
    type = "bool",
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

    [C.CXType_Bool] = Bool,

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
local TypeMap = {
    ---@param self TypeMap
    ---@param cxType any
    ---@param cursor any
    type_from_cx_type = function(self, cxType, cursor)
        local is_const = clang.dll.clang_isConstQualifiedType(cxType) ~= 0

        local primitive = primitives[tonumber(cxType.kind)]
        if primitive then
            return primitive
        end

        if cxType.kind == C.CXType_Unexposed then
            -- template T ?
            return utils.new(Type, {
                type = "unexposed",
            }), is_const
        end

        -- pointer
        if cxType.kind == C.CXType_Pointer or cxType.kind == C.CXType_LValueReference then
            local pointeeCxType = clang.dll.clang_getPointeeType(cxType)
            local pointeeType, _is_const = self:type_from_cx_type(pointeeCxType, cursor)
            return utils.new(Type, {
                pointer = pointeeType,
            }), is_const
        elseif cxType.kind == C.CXType_DependentSizedArray then
            local elementCxType = clang.dll.clang_getArrayElementType(cxType)
            local elementType, _is_const = self:type_from_cx_type(elementCxType, cursor)
            return utils.new(Type, {
                array = elementType,
            }), is_const
        end

        -- function pointer
        if cxType.kind == C.CXType_FunctionProto then
            -- void (*fn)(void *)
            return utils.new(Type, {
                type = "function",
            }), is_const
        end

        -- user type
        if cxType.kind == C.CXType_Typedef then
            return utils.new(Type, {
                type = "typedef",
            })
        elseif cxType.kind == C.CXType_Elaborated then
            return utils.new(Type, {
                type = "elaborated",
            })
        end

        assert(false)
    end,

    ---@param self TypeMap
    ---@param cursor any
    ---@return Type
    create_enum = function(self, cursor)
        local cx_type = clang.dll.clang_getEnumDeclIntegerType(cursor)
        local base_type, _is_const = self:type_from_cx_type(cx_type, cursor)
        if not base_type then
            return
        end

        local t = utils.new(Type, {
            name = clang.get_spelling_from_cursor(cursor),
            type = "enum",
            base_type = base_type,
        })
        return t
    end,

    ---@param self TypeMap
    ---@param cursor any
    ---@return Type
    create_typedef = function(self, cursor)
        local underlying = clang.dll.clang_getTypedefDeclUnderlyingType(cursor)
        local base_type, _is_const = self:type_from_cx_type(underlying, cursor)
        if not base_type then
            return
        end

        local t = utils.new(Type, {
            name = clang.get_spelling_from_cursor(cursor),
            type = "typedef",
            base_type = base_type,
        })
        return t
    end,

    ---@param self TypeMap
    ---@param cursor any
    ---@return Type
    create_struct = function(self, cursor)
        local t = utils.new(Type, {
            name = clang.get_spelling_from_cursor(cursor),
            type = "struct",
        })
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
