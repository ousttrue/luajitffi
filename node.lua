local ffi = require("ffi")
local C = ffi.C

local function _walk_after_factory()
    local walk_after
    walk_after = function(node)
        if node.children then
            for i, child in ipairs(node.children) do
                walk_after(child)
            end
        end
        coroutine.yield(node)
    end
    return walk_after
end
local function _walk_begin_factory()
    local walk_begin
    walk_begin = function(node)
        coroutine.yield(node)
        if node.children then
            for i, child in ipairs(node.children) do
                walk_begin(child)
            end
        end
    end
    return walk_begin
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
    traverse_after = function(self)
        local co = coroutine.create(_walk_after_factory())
        return function()
            local success, result = coroutine.resume(co, self)
            if success then
                return result
            end
        end
    end,

    traverse_begin = function(self)
        local co = coroutine.create(_walk_begin_factory())
        return function()
            local success, result = coroutine.resume(co, self)
            if success then
                return result
            end
        end
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
    print = function(self)
        print(string.format("%s%q: %s", self.indent, self.type, self.spelling))
        if self.children then
            for i, child in ipairs(self.children) do
                child:print()
            end
        end
    end,
}

return Node
