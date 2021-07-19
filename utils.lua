local M = {}

---@param str string
---@param ts string
---@return string[]
M.split = function(str, ts)
    local t = {}
    for s in string.gmatch(str, "([^" .. ts .. "]+)") do
        table.insert(t, s)
    end
    return t
end

---@generic S, T
---@param t S[]
---@param f fun(src:S):T
---@return T[]
M.map = function(t, f)
    local dst = {}
    for _, v in ipairs(t) do
        table.insert(dst, f(v))
    end
    return dst
end

---@generic S
---@param t S[]
---@param f fun(src:S):boolean
---@return S[]
M.filter = function(t, f)
    local dst = {}
    for _, v in ipairs(t) do
        if f(v) then
            table.insert(dst, v)
        end
    end
    return dst
end

M.new = function(class_table, instance_table)
    class_table.__index = class_table
    return setmetatable(instance_table, class_table)
end

return M
