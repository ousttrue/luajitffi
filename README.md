# LuajitFFI
luajit FFI generator using libclang

## ToDo

* [x] lfs alternative and luarocks to luajit
* [ ] fix set_type
* [ ] imgui(c++ mangle)
* [ ] automation [FFI Callbacks with pass by value structs](http://wiki.luajit.org/FFI-Callbacks-with-pass-by-value-structs)

## Setup

```
> cd LuaJIT/src
> cmd /C "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat" "&" "msvcbuild.bat"
```
## Usage

* require PATH environment variable to `libclang.dll`

```
lua main.lua
-Iinclude_dir(CFLAGS)
-DDefinition(CFLAGS)
-Eexport_header,dll_name.dll
-Oout_dir
```
