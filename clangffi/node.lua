local utils = require("clangffi.utils")
local clang_util = require("clangffi.clang_util")
local mod = require("clang.mod")
local clang = mod.libs.clang

local function cehck_stack(stack, target)
    for i, item in ipairs(stack) do
        if item[1] == target[1] and item[2] == target[2] then
            assert(false, "!! circular !!")
        end
    end
end

local function traverse(root, stack)
    if not stack then
        return {}, root
    end

    local current = root:from_path(stack)
    if current.children then
        local child = current.children[1]
        cehck_stack(stack, { current, 1 })
        -- push
        table.insert(stack, { current, 1 })
        return stack, child
    end

    while #stack > 0 do
        local parent, index = unpack(table.remove(stack))
        cehck_stack(stack, { parent, index + 1 })
        table.insert(stack, { parent, index + 1 })
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
            return
        end

        path = path or {}
        local used = {}
        local children = {}
        for i, child in ipairs(self.children) do
            if not path[child] and not used[child] then
                used[child] = true
                table.insert(children, child)
            end
        end
        self.children = children

        local copy = {}
        for k, v in pairs(path) do
            copy[k] = v
        end
        copy[self] = true

        for i, child in ipairs(self.children) do
            child:remove_duplicated(copy)
        end
    end,

    from_path = function(root, path)
        local current = root
        local i = 1
        while i <= #path do
            local _, index = unpack(path[i])
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
        cursor_kind = cursor.kind,
        type_kind = cxType.kind,
        location = clang_util.get_location(cursor),
    })
    return node
end

return Node
