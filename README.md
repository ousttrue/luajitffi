# LuajitFFI
luajit FFI generator using libclang

## ToDo

* [ ] refactoring traverse
* [x] lfs alternative and luarocks to luajit
* [x] fix set_type
* [x] imgui(c++ mangle)
* [ ] automation [FFI Callbacks with pass by value structs](http://wiki.luajit.org/FFI-Callbacks-with-pass-by-value-structs)
* [x] struct: automation nested type order
* [ ] struct: EmmyLua annotation @field
* [x] struct: ImVector<T>
* [x] cdef require order
* [x] function: default argument
* [x] function: overload. same name has suffix
* [ ] function: description from comment
* [x] function: is variadic(...)
* [x] method
* [x] method: overload
* [ ] com: example <https://qiita.com/otagaisama-1/items/b0804b9d6d37d82950f7>
* [ ] separate annotation <https://github.com/sumneko/lua-language-server/wiki/Setting-without-VSCode>

## Setup

```
> cd LuaJIT/src
> cmd /K "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat" 
VC> msvcbuild.bat
```
## Usage

* require PATH environment variable to `libclang.dll`

```
lua main.lua
-I{Include_dir} #CFLAGS
-D{Definition} #CFLAGS
-E{Export_header},{dll_name.dll}
-O{Out_dir}
```
