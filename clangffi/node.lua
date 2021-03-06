local utils = require("clangffi.utils")
local clang_util = require("clangffi.clang_util")
local mod = require("clang.mod")
local clang = mod.libs.clang

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
        return string.format("%d: %s %s", self.hash, self.spelling, self.node_type)
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

    -- remove dup child and circular child
    remove_duplicated = function(self, path)
        if not self.children then
            return 1
        end

        path = path or {}
        local used = {}
        local children = {}
        for i, child in ipairs(self.children) do
            if not path[child] and not used[child] then
                used[child] = true
                assert(child)
                table.insert(children, child)
            end
        end
        if #children == 0 then
            self.children = nil
            return 1
        end

        self.children = children
        local copy = {}
        for k, v in pairs(path) do
            copy[k] = v
        end
        copy[self] = true

        local count = 1
        for i, child in ipairs(self.children) do
            count = count + child:remove_duplicated(copy)
        end
        return count
    end,

    from_path = function(root, path)
        local current = root
        local i = 1
        while i <= #path do
            local index = path[i]
            current = current.children[index]
            i = i + 1
        end
        return current
    end,
}

---@param cursor any
---@param c integer
---@return Node
Node.new = function(cursor, c, parent_cursor)
    local cxType = clang.clang_getCursorType(cursor)
    local node = utils.new(Node, {
        hash = c,
        spelling = clang_util.get_spelling_from_cursor(cursor),
        cursor_kind = tonumber(cursor.kind),
        type_kind = tonumber(cxType.kind),
        location = clang_util.get_location(cursor),
    })
    return node
end

return Node
