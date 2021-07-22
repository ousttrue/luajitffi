-- C:/Program Files/LLVM/include/clang-c/CXErrorCode.h
local ffi = require 'ffi'
ffi.cdef[[
enum CXErrorCode{
    CXError_Success = 0,
    CXError_Failure = 1,
    CXError_Crashed = 2,
    CXError_InvalidArguments = 3,
    CXError_ASTReadError = 4,
};
]]
