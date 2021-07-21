local utils = require("clangffi.utils")
local clang = require("clangffi.clang")
local C = clang.C

local M = {}

---
--- Primitives
---

---@class Primitive
---@field name string
M.Primitive = {}

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
M.Pointer = {}

---@class Array
---@field element any
---@field size integer
M.Array = {}

---@class Param
---@field name string
---@field type any
---@field is_const boolean
M.Param = {}

---
--- Function, Struct, Typedef, Enum...
---

---@class Function
---@field dll_export boolean
---@field name string
---@field params Param[]
---@field result_type any
---@field result_is_const boolean
M.Function = {
    ---@return string
    __tostring = function(self)
        local prefix = ""
        if self.dll_export then
            prefix = "extern "
        end
        local params = utils.map(self.params, function(p)
            assert(p.cursor_kind)
            return string.format("%s %s", p.param_type, p.spelling)
        end)
        return string.format("%s%s %s(%s)", prefix, self.result_type, self.name, table.concat(params, ", "))
    end,
}

---@class Typedef
---@field type any
---@field type_is_const boolean
M.Typedef = {}

---@class Elabolated
M.Elaborated = {}

---@class Struct
M.Struct = {}

---@class EnumConst
---@field name string
---@field value any
M.EnumConst = {}

---@class Enum
---@field values EnumConst[]
M.Enum = {}

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
        return primitive
    end

    if cxType.kind == C.CXType_Unexposed then
        -- template T ?
        return {
            type = "unexposed",
        }, is_const
    elseif cxType.kind == C.CXType_Pointer or cxType.kind == C.CXType_LValueReference then
        -- pointer
        local pointeeCxType = clang.dll.clang_getPointeeType(cxType)
        local pointeeType, _is_const = M.type_from_cx_type(pointeeCxType, cursor)
        return utils.new(M.Pointer, {
            pointee = pointeeType,
        }), is_const
    elseif cxType.kind == C.CXType_ConstantArray then
        -- -- array[N]
        local array_size = clang.dll.clang_getArraySize(cxType)
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
        -- function pointer
        -- void (*fn)(void *)
        return utils.new(M.Function, {}), is_const
    elseif cxType.kind == C.CXType_Typedef then
        return utils.new(M.Typedef, {})
    elseif cxType.kind == C.CXType_Elaborated then
        return utils.new(M.Elaborated, {})
    else
        assert(false)
    end
end

---@param cursor any
---@return Enum
M.create_enum = function(cursor)
    local cx_type = clang.dll.clang_getEnumDeclIntegerType(cursor)
    local base_type, _is_const = M.type_from_cx_type(cx_type, cursor)
    if not base_type then
        return
    end

    local t = utils.new(M.Enum, {
        type = base_type,
    })
    return t
end

---@param cursor any
---@return Typedef
M.create_typedef = function(cursor)
    local underlying = clang.dll.clang_getTypedefDeclUnderlyingType(cursor)
    local base_type, _is_const = M.type_from_cx_type(underlying, cursor)
    if not base_type then
        return
    end

    local t = utils.new(M.Typedef, {
        type = base_type,
    })
    return t
end

---@param cursor any
---@return Struct
M.create_struct = function(cursor)
    local t = utils.new(M.Struct, {})
    return t
end

return M
