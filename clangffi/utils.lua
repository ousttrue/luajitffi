local ffi = require("ffi")
ffi.cdef([[
typedef unsigned int DWORD;
typedef const char *LPCSTR;
typedef int BOOL;
typedef struct _SECURITY_ATTRIBUTES {
    DWORD  nLength;
    void* lpSecurityDescriptor;
    BOOL   bInheritHandle;
} SECURITY_ATTRIBUTES;
typedef const SECURITY_ATTRIBUTES* LPSECURITY_ATTRIBUTES;
DWORD GetFileAttributesA(LPCSTR lpFileName);    
BOOL CreateDirectoryA(
  LPCSTR                lpPathName,
  LPSECURITY_ATTRIBUTES lpSecurityAttributes
);
]])
local kernel32 = ffi.load("kernel32")

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
        if f then
            table.insert(dst, f(v))
        else
            table.insert(dst, v)
        end
    end
    return dst
end

---@generic S, T
---@param t S[]
---@param f fun(i:integer, src:S):T
---@return T[]
M.imap = function(t, f)
    local dst = {}
    for i, v in ipairs(t) do
        table.insert(dst, f(i, v))
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

---@generic T
---@param class_table T
---@param instance_table any
---@return T
M.new = function(class_table, instance_table)
    class_table.__index = class_table
    return setmetatable(instance_table, class_table)
end

M.split_basename = function(path)
    local d = string.find(path, "([^/\\]+)$")
    if d then
        if d == 1 then
            return nil, path
        end
        return path:sub(1, d - 2), path:sub(d)
    end
end

M.split_ext = function(path)
    local dir, basename = M.split_basename(path)
    if basename then
        local d = string.find(basename, "([^/.]+)$")
        if d then
            return dir, basename:sub(1, d - 2), basename:sub(d - 1)
        end
    end
end

M.get_indent = function(indent, count)
    local s = ""
    for i = 1, count do
        s = s .. indent
    end
    return s
end

M.is_exists = function(path)
    if kernel32.GetFileAttributesA(path) ~= 0xffffffff then
        return true
    end
end

M.mkdirp = function(dir)
    local parent, basename = M.split_basename(dir)
    if parent and parent ~= "." then
        if not M.is_exists(parent) then
            M.mkdirp(parent)
        end
    end
    print(string.format("mkdir %s", dir))
    kernel32.CreateDirectoryA(dir, nil)
end

return M
