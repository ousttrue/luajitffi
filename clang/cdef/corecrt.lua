-- C:/Program Files (x86)/Windows Kits/10/Include/10.0.18362.0/ucrt/corecrt.h
local ffi = require 'ffi'
ffi.cdef[[
typedef long long __time64_t;
typedef __time64_t time_t;
]]
