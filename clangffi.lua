---@param str string
---@param ts string
---@return string[]
local function split(str, ts)
    local t = {}
    for s in string.gmatch(str, "([^" .. ts .. "]+)") do
        table.insert(t, s)
    end
    return t
end

---@generic S, T
---@param tbl S[]
---@param f fun(src:S):T
---@return T[]
local function map(tbl, f)
    local t = {}
    for _, v in ipairs(tbl) do
        table.insert(t, f(v))
    end
    return t
end

local function new(class_table, instance_table)
    class_table.__index = class_table
    return setmetatable(instance_table, class_table)
end

---@class Export
---@field header string
---@field link string
local Export = {
    ---@param self Export
    __tostring = function(self)
        return string.format("{%s: %s}", self.header, self.link)
    end,
}

---@param header string
---@param link string
---@return Export
Export.new = function(header, link)
    return new(Export, {
        header = header,
        link = link,
    })
end

---@class Args
---@field CFLAGS string[]
---@field EXPORTS Export[]
---@field OUT_DIR string
local Args = {
    ---@param self Args
    ---@return string
    unsaved_export_headers = function(self)
        return table.concat(
            map(self.EXPORTS, function(v)
                return string.format('#include "%s"', v.header)
            end),
            "\n"
        )
    end,

    ---@param self Args
    __tostring = function(self)
        return string.format(
            "CFLAGS:[%s], EXPORT:[%s] => %s",
            table.concat(self.CFLAGS, ", "),
            table.concat(
                map(self.EXPORTS, function(v)
                    return tostring(v)
                end),
                ", "
            ),
            self.OUT_DIR
        )
    end,
}

---@param args string[]
---@return Args
Args.parse = function(args)
    local instance = {
        CFLAGS = {},
        EXPORTS = {},
    }
    for i, arg in ipairs(args) do
        if arg:find("-I") == 1 or arg:find("-D") == 1 then
            table.insert(instance.CFLAGS, arg)
        elseif arg:find("-E") == 1 then
            local value = arg:sub(3)
            local export, dll = unpack(split(value, ","))
            table.insert(instance.EXPORTS, Export.new(export, dll))
        elseif arg:find("-O") == 1 then
            local value = arg:sub(3)
            instance.OUT_DIR = value
        end
        i = i + 1
    end

    for i, cflags in ipairs(instance.CFLAGS) do
        if cflags:find("-I") == 1 then
            local include = cflags:sub(3)
            for j, v in ipairs(instance.EXPORTS) do
                if v.header:find(include) == 1 then
                    -- to relative path
                    v.header = v.header:sub(#include + 2)
                end
            end
        end
    end

    return new(Args, instance)
end

---@class Node
---@field hash integer
---@field children Node[]
---@field type any
---@field spelling string
local Node = {
    ---@param self Node
    ---@param indent string
    print = function(self, indent)
        print(string.format("%s%d: %q %s", indent, self.hash, self.type, self.spelling))
        indent = indent .. "  "
        if self.children then
            for i, child in ipairs(self.children) do
                child:print(indent)
            end
        end
    end,
}

---@class Clang
---@field ffi ffilib
---@field clang any
---@field root Node
---@field node_map table<integer, Node>
local Clang = {
    ---@param path string
    ---@param unsaved_content string
    ---@param cflags string[]
    parse = function(self, path, unsaved_content, cflags)
        local index = self.clang.clang_createIndex(0, 0)

        local arguments = {
            "-x",
            "c++",
            "-target",
            "x86_64-windows-msvc",
            "-fms-compatibility-version=18",
            "-fdeclspec",
            "-fms-compatibility",
        }
        for i, cflag in ipairs(cflags) do
            table.insert(arguments, cflag)
        end
        table.insert(arguments, string.format("-I%s", path))

        local c_str = self.ffi.typeof(string.format("const char *[%d]", #arguments))
        local array = c_str()
        for i, arg in ipairs(arguments) do
            -- FFI is zero origin !
            array[i - 1] = arg
        end

        local unsaved = self.ffi.new("struct CXUnsavedFile")
        local n_unsaved = 0

        if #unsaved_content > 0 then
            n_unsaved = 1
            unsaved.Filename = path
            unsaved.Contents = unsaved_content
            unsaved.Length = #unsaved_content
        end

        local tu = self.clang.clang_parseTranslationUnit(
            index,
            path,
            array,
            #arguments,
            unsaved,
            n_unsaved,
            self.ffi.C.CXTranslationUnit_DetailedPreprocessingRecord
        )

        return tu
    end,

    traverse = function(self, tu)
        local visitor = self.ffi.cast("CXCursorVisitorP", function(cursor, parent, data)
            self:push(cursor[0], parent[0])

            return self.ffi.C.CXChildVisit_Recurse
        end)
        local cursor = self.clang.clang_getTranslationUnitCursor(tu)
        self:set_root(cursor)
        self.clang.clang_visitChildren(cursor, visitor, nil)
        visitor:free()
    end,

    get_or_create_node = function(self, cursor)
        local c = self.clang.clang_hashCursor(cursor)
        local node = self.node_map[c]
        if not node then
            node = new(Node, {
                hash = c,
                spelling = self:get_string_from_cursor(cursor),
                type = cursor.kind,
            })
            self.node_map[node.hash] = node
        end
        return node
    end,

    set_root = function(self, cursor)
        self.root = self:get_or_create_node(cursor)
    end,

    push = function(self, cursor, parent_cursor)
        local node = self:get_or_create_node(cursor)

        if self.clang.clang_Cursor_isNull(parent_cursor) == 0 then
            local p = self.clang.clang_hashCursor(parent_cursor)
            local parent = self.node_map[p]
            if not parent.children then
                parent.children = {}
            end
            table.insert(parent.children, node)
        end
    end,

    get_string_from_cursor = function(self, cursor)
        local spelling = self.clang.clang_getCursorSpelling(cursor)
        local value = self.ffi.string(self.clang.clang_getCString(spelling))
        self.clang.clang_disposeString(spelling)
        return value
    end,
}

---@return Clang
Clang.new = function()
    require("clang.CXString")
    require("clang.Index")
    local ffi = require("ffi")
    local clang = ffi.load("libclang")
    return new(Clang, {
        ffi = ffi,
        clang = clang,
        node_map = {},
    })
end

---@param args string[]
local function main(args)
    local usage = [[usage:
    lua clangffi.lua
    -Iinclude_dir
    -Eexport_header,dll_name.dll
    -Oout_dir
    ]]

    local parsed = Args.parse(args)

    local clang = Clang.new()

    -- parse libclang
    local tu
    if #parsed.EXPORTS == 1 then
        -- empty unsaved_content
        tu = clang:parse(parsed.EXPORTS[1].header, "", parsed.CFLAGS)
    else
        -- use unsaved_content
        tu = clang:parse("__unsaved_header__.h", parsed:unsaved_export_headers(), parsed.CFLAGS)
    end

    clang:traverse(tu)

    clang.root:print("")
end

main({ ... })
