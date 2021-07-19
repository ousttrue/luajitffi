local ffi = require("ffi")
local C = ffi.C

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

return Node
