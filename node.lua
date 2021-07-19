local ffi = require("ffi")
local clang = require("clang")
local utils = require("utils")

local function from_path(root, path)
    local current = root
    local i = 1
    while i <= #path do
        current = current.children[path[i]]
        i = i + 1
    end
    return current
end

local function traverse(root, stack)
    if not stack then
        return {}, root
    end

    local current = from_path(root, stack)
    if current.children then
        local child = current.children[1]
        -- push
        table.insert(stack, 1)
        return stack, child
    end

    while #stack > 0 do
        local index = table.remove(stack)
        table.insert(stack, index + 1)
        local sibling = from_path(root, stack)
        if sibling then
            -- sibling
            return stack, sibling
        end
        -- pop
        table.remove(stack)
    end

    return nil
end

---@class Node
---@field cursor any
---@field hash integer
---@field children Node[]
---@field type any
---@field spelling string
---@field location string
---@field indent string
---@field formatted string
local Node = {

    ---@param self Node
    ---@return fun(root: Node, state: Node[]):Node[]
    traverse = function(self)
        return traverse, self
    end,

    -- ---@param self Node
    -- process = function(self)
    --     if self.formatted then
    --         return
    --     end

    --     if self.type == C.CXCursor_TranslationUnit then
    --     elseif self.type == C.CXCursor_MacroDefinition then
    --     elseif self.type == C.CXCursor_MacroExpansion then
    --     elseif self.type == C.CXCursor_InclusionDirective then
    --     elseif self.type == C.CXCursor_TypedefDecl then
    --         -- self.formatted = string.format("%d: typedef %s", self.hash, self.spelling)
    --     elseif self.type == C.CXCursor_FunctionDecl then
    --         self.formatted = string.format("%s: function %s()", self.location, self.spelling)
    --     else
    --         -- self.formatted = string.format("%d: %q %s", self.hash, self.type, self.spelling)
    --     end
    -- end,

    ---@param self Node
    __tostring = function(self)
        return string.format("%s%q: %s", self.indent, self.type, self.spelling)
    end,
}

local function get_spelling_from_cursor(cursor)
    local cxString = clang.dll.clang_getCursorSpelling(cursor)
    local value = ffi.string(clang.dll.clang_getCString(cxString))
    clang.dll.clang_disposeString(cxString)
    return value
end

local function get_spelling_from_file(file)
    if file == ffi.NULL then
        return
    end
    local cxString = clang.dll.clang_getFileName(file)
    local value = ffi.string(clang.dll.clang_getCString(cxString))
    clang.dll.clang_disposeString(cxString)
    return value
end

local function get_location(cursor)
    local location = clang.dll.clang_getCursorLocation(cursor)
    if clang.dll.clang_equalLocations(location, clang.dll.clang_getNullLocation()) ~= 0 then
        return
    end

    local file = ffi.new("CXFile[1]")
    local line = ffi.new("unsigned[1]")
    local column = ffi.new("unsigned[1]")
    local offset = ffi.new("unsigned[1]")
    clang.dll.clang_getSpellingLocation(location, file, line, column, offset)
    local path = get_spelling_from_file(file[0])
    if path then
        return path
    end
end

---@param cursor any
---@param c integer
---@return Node
Node.new = function(cursor, c)
    return utils.new(Node, {
        cursor = cursor,
        hash = c,
        spelling = get_spelling_from_cursor(cursor),
        type = cursor.kind,
        location = get_location(cursor),
    })
end

return Node
