# clang-ffi
luajit FFI generator using libclang

## FirstVersion

* created from from `include/clang-c/Index.h` and `CXString.h` of LLVM-11(64bit)

## Setup

```
> hererocks.exe -j 2.1.0-beta3 -r latest lua
> . ./lua/bin/activate.ps1
> luarocks install luafilesystem
```

## Usage

```
> lua/bin/lua.exe main.lua
```
