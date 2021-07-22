local utils = require("clangffi.utils")
local clang = require("clangffi.clang")
local C = clang.C

local M = {}

---
--- Primitives
---

---@class Primitive
---@field name string
M.Primitive = {
    __tostring = function(self)
        return string.format("(%s)", self.type)
    end,
}

M.Void = utils.new(M.Primitive, {
    type = "void",
})

M.Bool = utils.new(M.Primitive, {
    type = "bool",
})

M.Int8 = utils.new(M.Primitive, {
    type = "char",
})
M.Int16 = utils.new(M.Primitive, {
    type = "short",
})
M.Int32 = utils.new(M.Primitive, {
    type = "int",
})
M.Int64 = utils.new(M.Primitive, {
    type = "long long",
})

M.UInt8 = utils.new(M.Primitive, {
    type = "unsigned char",
})
M.UInt16 = utils.new(M.Primitive, {
    type = "unsigned short",
})
M.UInt32 = utils.new(M.Primitive, {
    type = "unsigned int",
})
M.UInt64 = utils.new(M.Primitive, {
    type = "unsigned long long",
})

M.Float = utils.new(M.Primitive, {
    type = "float",
})
M.Double = utils.new(M.Primitive, {
    type = "double",
})

---
--- Poiner, Reference, Array
---

---@class Pointer
---@field pointee any
M.Pointer = {
    ---@param self Pointer
    ---@return string
    __tostring = function(self)
        return string.format("%s*", self.pointee)
    end,
}

---@class Array
---@field element any
---@field size integer
M.Array = {
    ---@param self Array
    ---@return string
    __tostring = function(self)
        return string.format("%s[%d]", self.element, self.size)
    end,
}

---
--- Function, Struct, Typedef, Enum...
---

---@class Param
---@field name string
---@field type any
---@field is_const boolean
M.Param = {
    ---@param self Param
    ---@return string
    __tostring = function(self)
        return string.format("%s %s", self.type, self.name)
    end,
}

---@class Function
---@field dll_export boolean
---@field name string
---@field params Param[]
---@field result_type any
---@field result_is_const boolean
M.Function = {
    ---@param self Function
    ---@return string
    __tostring = function(self)
        local prefix = ""
        if self.dll_export then
            prefix = "extern "
        end
        local params = utils.map(self.params, function(p)
            -- assert(p.cursor_kind)
            return string.format("%s %s", p.type, p.name)
        end)
        return string.format("%s%s %s(%s)", prefix, self.result_type, self.name, table.concat(params, ", "))
    end,
}

---@class FunctionProto
---@field params Param[]
---@field result_type any
---@field result_is_const boolean
M.FunctionProto = {
    ---@param self FunctionProto
    ---@return string
    __tostring = function(self)
        local prefix = ""
        local params = utils.map(self.params, function(p)
            -- assert(p.cursor_kind)
            return string.format("%s %s", p.type, p.name)
        end)
        return string.format("%s%s (*)(%s)", prefix, self.result_type, table.concat(params, ", "))
    end,
}

---@class Typedef
---@field name string
---@field type any
---@field type_is_const boolean
M.Typedef = {
    ---@param self Typedef
    ---@return string
    __tostring = function(self)
        return string.format("typedef %s = %s", self.name, self.type)
    end,
}

---@class Field
---@field name string
---@field type any
---@field is_const boolean
M.Field = {
    ---@param self Field
    ---@return string
    __tostring = function(self)
        return string.format("%s %s", self.type, self.name)
    end,
}

---@class Struct
---@field name string
---@field fields Field[]
M.Struct = {
    ---@param self Struct
    ---@return string
    __tostring = function(self)
        return string.format("struct %s{%d fields}", self.name, #self.fields)
    end,
}

---@class EnumConst
---@field name string
---@field value any
M.EnumConst = {
    ---@param self EnumConst
    ---@return string
    __tostring = function(self)
        return "enum_const"
    end,
}

---@class Enum
---@field name string
---@field values EnumConst[]
M.Enum = {
    ---@param self Enum
    ---@return string
    __tostring = function(self)
        return string.format("enum %s{%d values}", self.name, #self.values)
    end,
}

---@param t any
---@return boolean
M.is_anonymous = function(t)
    local mt = getmetatable(t)
    if mt == M.Struct or mt == M.Enum then
        return not t.name or #t.name == 0
    end
end

local primitives = {
    [C.CXType_Void] = M.Void,

    [C.CXType_Bool] = M.Bool,

    [C.CXType_WChar] = M.UInt16, -- Windows
    [C.CXType_UShort] = M.UInt16,
    [C.CXType_UInt] = M.UInt32,
    [C.CXType_ULong] = M.UInt32,
    [C.CXType_ULongLong] = M.UInt64,

    [C.CXType_Char_S] = M.Int8,
    [C.CXType_Int] = M.Int32,
    [C.CXType_Long] = M.Int32,
    [C.CXType_LongLong] = M.Int64,

    [C.CXType_Double] = M.Double,
}

---@param cxType any
---@param cursor any
M.type_from_cx_type = function(cxType, cursor)
    local is_const = clang.dll.clang_isConstQualifiedType(cxType) ~= 0

    local primitive = primitives[tonumber(cxType.kind)]
    if primitive then
        return primitive, is_const
    end

    if cxType.kind == C.CXType_Unexposed then
        -- template T ?
        return "unexposed", is_const
    elseif cxType.kind == C.CXType_Pointer or cxType.kind == C.CXType_LValueReference then
        -- pointer
        local pointeeCxType = clang.dll.clang_getPointeeType(cxType)
        local pointeeType, _is_const = M.type_from_cx_type(pointeeCxType, cursor)
        return utils.new(M.Pointer, {
            pointee = pointeeType,
            is_const = _is_const,
        }),
            is_const
    elseif cxType.kind == C.CXType_ConstantArray then
        -- -- array[N]
        local array_size = tonumber(clang.dll.clang_getArraySize(cxType))
        local elementCxType = clang.dll.clang_getArrayElementType(cxType)
        local elementType, _is_const = M.type_from_cx_type(elementCxType, cursor)
        return utils.new(M.Array, {
            size = array_size,
            element = elementType,
        }),
            is_const
    elseif cxType.kind == C.CXType_DependentSizedArray then
        -- -- param array
        local array_size = clang.dll.clang_getArraySize(cxType)
        local elementCxType = clang.dll.clang_getArrayElementType(cxType)
        local elementType, _is_const = M.type_from_cx_type(elementCxType, cursor)
        return utils.new(M.Pointer, {
            pointee = elementType,
        }), is_const
    elseif cxType.kind == C.CXType_FunctionProto then
        local resultCxType = clang.dll.clang_getResultType(cxType)
        local resultType, _is_const = M.type_from_cx_type(resultCxType, cursor)
        return utils.new(M.FunctionProto, {
            result_type = resultType,
            result_is_const = _is_const,
            params = {},
        }),
            is_const
    elseif cxType.kind == C.CXType_Typedef then
        return utils.new(M.Typedef, {})
    elseif cxType.kind == C.CXType_Elaborated then
        return "elaborated", is_const
    else
        assert(false)
    end
end

---@param cursor any
---@return Enum
M.get_enum_int_type = function(cursor)
    local cx_type = clang.dll.clang_getEnumDeclIntegerType(cursor)
    local base_type, _is_const = M.type_from_cx_type(cx_type, cursor)
    return base_type
end

---@param cursor any
---@return Typedef
M.get_underlying_type = function(cursor)
    local underlying = clang.dll.clang_getTypedefDeclUnderlyingType(cursor)
    local base_type, _is_const = M.type_from_cx_type(underlying, cursor)
    return base_type
end

M.is_functionproto = function(t)
    if getmetatable(t) == M.Pointer then
        if getmetatable(t.pointee) == M.FunctionProto then
            return true
        end
    end
end

return M
