local types = require("clangffi.types")

---@param t any
---@param param_name string use const if true
---@return string
local function get_typename(t, param_name)
    if not t then
        return "XXX no t XXX"
    end
    local mt = getmetatable(t)
    if not mt then
        return "XXX no mt XXX"
    end

    if types.is_functionproto(t) then
        t = t.pointee
        local name = ""
        if type(param_name) == "string" then
            name = param_name
        end
        local s = string.format("%s(*%s)(", get_typename(t.result_type), name)
        for i, p in ipairs(t.params) do
            if i > 1 then
                s = s .. ", "
            end
            s = s .. get_typename(p.type, p.name)
        end
        s = s .. ")"
        return s
    end

    local name = ""
    if type(param_name) == "string" then
        name = " " .. param_name
    end

    if mt == types.Primitive then
        return t.type .. name
    elseif mt == types.Pointer then
        local is_const = ""
        if getmetatable(t.pointee) == types.Pointer then
            -- type const*
            if t.is_const then
                is_const = " const"
            end
            return string.format("%s%s*%s", get_typename(t.pointee), is_const, name)
        else
            -- const type*
            if t.is_const then
                is_const = "const "
            end
            return string.format("%s%s*%s", is_const, get_typename(t.pointee), name)
        end
    elseif mt == types.Array then
        return string.format("%s%s[%d]", get_typename(t.element), name, t.size)
    elseif mt == types.Typedef then
        if not t.name then
            return "XXX no name XXX"
        end
        return t.name .. name
    elseif mt == types.Enum then
        if not t.name then
            return "XXX no name XXX"
        end
        return "enum " .. t.name .. name
    elseif mt == types.Struct then
        if not t.name then
            return "XXX no name XXX"
        end
        return "struct " .. t.name .. name
    elseif mt == types.FunctionProto then
        assert(false)
    else
        return "XXX unknown type XXX"
    end
end

---@param self Typedef
types.Typedef.cdef = function(self)
    if types.is_anonymous(self.type) then
        return string.format("typedef %s %s", self.type:cdef(), self.name)
    else
        return string.format("typedef %s", get_typename(self.type, self.name))
    end
end

---@param self Struct
types.Struct.cdef = function(self)
    if #self.fields == 0 then
        return string.format("struct %s", self.name, self.name)
    end

    local s = string.format("struct %s{\n", self.name)
    for i, f in ipairs(self.fields) do
        s = s .. string.format("    %s;\n", get_typename(f.type, f.name))
    end
    s = s .. string.format("}")
    return s
end

---@param self Enum
types.Enum.cdef = function(self)
    local s = string.format("enum %s{\n", self.name)
    for i, v in ipairs(self.values) do
        s = s .. string.format("    %s = %s,\n", v.name, v.value)
    end
    s = s .. string.format("}")
    return s
end

---@param self Function
types.Function.cdef = function(self)
    local s = string.format("%s %s(\n", get_typename(self.result_type, true), self.name)
    for i, p in pairs(self.params) do
        s = s .. string.format("    %s", get_typename(p.type, p.name))
        if i < #self.params then
            s = s .. ","
        end
        s = s .. "\n"
    end
    s = s .. ")"
    if self.mangling and self.name ~= maingling then
        s = s .. string.format(' asm("%s")', self.mangling)
    end
    return s
end
