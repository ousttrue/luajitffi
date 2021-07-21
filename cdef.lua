local types = require("clangffi.types")

---@param t any
---@param in_function boolean use const if true
---@return string
local function get_typename(t, in_function, name)
    if not t then
        return "XXX no t XXX"
    end
    local mt = getmetatable(t)
    if not mt then
        return "XXX no mt XXX"
    end
    if mt == types.Primitive then
        return t.type
    elseif mt == types.Pointer then
        return get_typename(t.pointee, in_function) .. "*"
    elseif mt == types.Array then
        return string.format("%s[%d]", get_typename(t.element), t.size)
    elseif mt == types.Typedef then
        if not t.name then
            return "XXX no name XXX"
        end
        return t.name
    elseif mt == types.Enum then
        if not t.name then
            return "XXX no name XXX"
        end
        return t.name
    elseif mt == types.Struct then
        if not t.name then
            return "XXX no name XXX"
        end
        return t.name
    else
        return "XXX unknown type XXX"
    end
end

---@param self Typedef
types.Typedef.cdef = function(self)
    return string.format("typedef %s %s;\n", get_typename(self.type, false), self.name)
end

---@param self Struct
types.Struct.cdef = function(self)
    local s = string.format("struct %s {\n", self.name)
    for i, v in ipairs(self.fields) do
        s = s .. string.format("    %s %s;\n", get_typename(v.type, false), v.name)
    end
    s = s .. "};\n"
    return s
end

---@param self Enum
types.Enum.cdef = function(self)
    local s = string.format("enum %s {\n", self.name)
    for i, v in ipairs(self.values) do
        s = s .. string.format("    %s = %s,\n", v.name, v.value)
    end
    s = s .. "};\n"
    return s
end

---@param self Function
types.Function.cdef = function(self)
    local s = string.format("%s %s(\n", get_typename(self.result_type, true), self.name)
    for i, p in pairs(self.params) do
        s = s .. string.format("    %s %s", get_typename(p.type, true), p.name)
        if i < #self.params then
            s = s .. ","
        end
        s = s .. "\n"
    end
    s = s .. ");\n"
    return s
end
