local mod = require("clang.mod")
local ffi = require("ffi")

-- require("clang.cdef.vcruntime")
local size_t = ffi.new("size_t")
print(ffi.typeof(size_t))

-- require("clang.cdef.corecrt")
local TIME_T = ffi.typeof("time_t")
local time_t = ffi.new(TIME_T)
print(type(TIME_T), type(time_t))

-- require("clang.cdef.CXErrorCode")
local error_code = ffi.new("enum CXErrorCode")
print(error_code)

-- require("clang.cdef.CXString")
-- require("clang.cdef.Index")
print(ffi.new("void*", nil) == nil)
local index = mod.libs.clang.clang_createIndex(0, 0)
print(index)
