# LuajitFFI
luajit FFI generator using libclang

## ToDo

* [ ] lfs alternative and luarocks to luajit
* [ ] fix set_type
* [ ] imgui(c++ mangle)
* [ ] automation [FFI Callbacks with pass by value structs](http://wiki.luajit.org/FFI-Callbacks-with-pass-by-value-structs)

## Setup

```
> hererocks.exe -j 2.1.0-beta3 -r latest lua
> . ./lua/bin/activate.ps1
> luarocks install luafilesystem
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
