local ffi = require("ffi")
local clang = require("clangffi.clang")
local utils = require("clangffi.utils")

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
---@field hash integer
---@field children Node[]
---@field cursor_kind any
---@field spelling string
---@field location Location
---@field indent string
---@field formatted string
---@field type Type
local Node = {

    ---@param self Node
    ---@return fun(root: Node, state: Node[]):Node[]
    traverse = function(self)
        return traverse, self
    end,

    ---@param self Node
    __tostring = function(self)
        return string.format("%s%q: %s", self.indent, self.cursor_kind, self.spelling)
    end,
}

---@param cursor any
---@param c integer
---@return Node
Node.new = function(cursor, c)
    local cxType = clang.dll.clang_getCursorType(cursor)
    return utils.new(Node, {
        hash = c,
        spelling = clang.get_spelling_from_cursor(cursor),
        cursor_kind = cursor.kind,
        type_kind = cxType.kind,
        location = clang.get_location(cursor),
    })
end

return Node
