# LuajitFFI
luajit FFI generator using libclang

## ToDo

* [x] lfs alternative and luarocks to luajit
* [x] fix set_type
* [x] imgui(c++ mangle)
* [ ] automation [FFI Callbacks with pass by value structs](http://wiki.luajit.org/FFI-Callbacks-with-pass-by-value-structs)
* [ ] struct: automation nested type order
* [ ] struct: @field
* [ ] cdef require order
* [ ] function: default argument
* [x] function: overload. same name has suffix
* [ ] function: description from comment

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
