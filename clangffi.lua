require 'clang.CXString'
require 'clang.Index'
local ffi = require 'ffi'
local clang = ffi.load('libclang')
print(clang)
