local ffi = require("ffi")
require("clang.CXString")
require("clang.Index")
return {
    dll = ffi.load("libclang"),
    C = ffi.C,
}
