local clang = require("clangffi.clang")
local utils = require("clangffi.utils")

local function traverse(root, stack)
    if not stack then
        return {}, root
    end

    local current = root:from_path(stack)
    if current.children then
        local child = current.children[1]
        -- push
        table.insert(stack, 1)
        return stack, child
    end

    while #stack > 0 do
        local index = table.remove(stack)
        table.insert(stack, index + 1)
        local sibling = root:from_path(stack)
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
---@field ref_hash integer
---@field cursor_kind any
---@field spelling string
---@field location Location
---@field node_type string
---@field type any
local Node = {

    ---@param self Node
    __tostring = function(self)
        return string.format("%s: %s", self.node_type, self.spelling)
    end,

    ---@param self Node
    ---@return fun(root: Node, state: Node[]):Node[]
    traverse = function(self)
        return traverse, self
    end,

    ---@param self Node
    ---@param src Node
    ---@param dst Node
    replace_child = function(self, src, dst)
        for i, child in ipairs(self.children) do
            if child == src then
                self.children[i] = dst
                return true
            end
        end
        assert(false)
    end,

    remove_duplicated = function(self)
        if not self.children then
            return
        end
        local used = {}
        local remove = {}
        for i, child in ipairs(self.children) do
            if used[child.hash] then
                table.insert(remove, 1, i)
            else
                used[child.hash] = true
                child:remove_duplicated()
            end
        end
        for i, x in ipairs(remove) do
            table.remove(self.children, x)
        end
    end,

    from_path = function(root, path)
        local current = root
        local i = 1
        while i <= #path do
            current = current.children[path[i]]
            i = i + 1
        end
        return current
    end,
}

---@param cursor any
---@param c integer
---@return Node
Node.new = function(cursor, c, parent_cursor)
    local cxType = clang.dll.clang_getCursorType(cursor)
    local node = utils.new(Node, {
        hash = c,
        spelling = clang.get_spelling_from_cursor(cursor),
        cursor_kind = cursor.kind,
        type_kind = cxType.kind,
        location = clang.get_location(cursor),
    })
    return node
end

return Node
