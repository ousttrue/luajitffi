local ffi = require("ffi")

require("generated.clang.vcruntime")
local size_t = ffi.new("size_t")
print(ffi.typeof(size_t))

require("generated.clang.corecrt")
local TIME_T = ffi.typeof("time_t")
local time_t = ffi.new(TIME_T)
print(type(TIME_T), type(time_t))

require("generated.clang.CXErrorCode")
local error_code = ffi.new("enum CXErrorCode")
print(error_code)

require("generated.clang.CXString")
require("generated.clang.Index")
