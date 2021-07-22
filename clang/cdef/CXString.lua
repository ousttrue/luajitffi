-- C:/Program Files/LLVM/include/clang-c/CXString.h
local ffi = require 'ffi'
ffi.cdef[[
typedef struct {
    const void* data;
    unsigned int private_flags;
} CXString;
typedef struct {
    CXString* Strings;
    unsigned int Count;
} CXStringSet;
const char* clang_getCString(
    CXString string
);
void clang_disposeString(
    CXString string
);
void clang_disposeStringSet(
    CXStringSet* set
);
]]
