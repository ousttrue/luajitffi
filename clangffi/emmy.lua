local types = require("clangffi.types")

---@param t any
---@param param_name string use const if true
---@return string
function get_typename(t, param_name)
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
        return t.name .. name
    elseif mt == types.Struct then
        if not t.name then
            return "XXX no name XXX"
        end
        return t.name .. name
    elseif mt == types.FunctionProto then
        assert(false)
    else
        return "XXX unknown type XXX"
    end
end

local map = {
    ["int"] = "integer",
    ["long long"] = "integer",
    ["const char*"] = "string",
    ["void"] = "",
}

return {
    get_typename = function(t)
        local result = get_typename(t)
        if result:find("unsigned ") == 1 then
            result = result:sub(#"unsigned ?")
        end
        local found = map[result]
        if found then
            return found
        end

        if result:find("*") then
            return "cdata"
        end

        return result
    end,
}
