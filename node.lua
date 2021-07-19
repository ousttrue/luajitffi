local ffi = require("ffi")
local C = ffi.C

---@class Node
---@field hash integer
---@field children Node[]
---@field type any
---@field spelling string
---@field location string
---@field formatted string
local Node = {
    ---@param self Node
    process = function(self)
        if self.children then
            for i, child in ipairs(self.children) do
                child:process()
            end
        end

        if self.formatted then
            return
        end

        if self.type == C.CXCursor_TranslationUnit then
        elseif self.type == C.CXCursor_MacroDefinition then
        elseif self.type == C.CXCursor_MacroExpansion then
        elseif self.type == C.CXCursor_InclusionDirective then
        elseif self.type == C.CXCursor_TypedefDecl then
            -- self.formatted = string.format("%d: typedef %s", self.hash, self.spelling)
        elseif self.type == C.CXCursor_FunctionDecl then
            self.formatted = string.format("%s: function %s()", self.location, self.spelling)
        else
            -- self.formatted = string.format("%d: %q %s", self.hash, self.type, self.spelling)
        end
    end,

    ---@param self Node
    ---@param indent string
    print = function(self, indent)
        if self.formatted then
            print(string.format("%s%s", indent, self.formatted))
        end

        indent = indent .. "  "
        if self.children then
            for i, child in ipairs(self.children) do
                child:print(indent)
            end
        end
    end,
}

return Node
