local M = {}
M.__index = M
_G.dddd_outlets = _G.dddd_outlets or {}

-- ─────────────────────────────────────
--- Generates a random hexadecimal identifier used for dddd message routing.
---@return string id 12-character hexadecimal id.
function M:_random_string()
	local res = {}
	for i = 1, 12 do
		res[i] = string.format("%x", math.random(0, 15))
	end
	return table.concat(res)
end

-- ─────────────────────────────────────
--- Recursively parses a bracketed/parenthesized list fragment.
---@param str string Serialized list string.
---@param i integer Current cursor index.
---@return table result Parsed sublist.
---@return integer i Cursor index at parse end.
function M:_parse_list(str, i)
	local result = {}
	local token = ""
	i = i + 1

	local char_open, char_close = self:check_brackets(str)

	while i <= #str do
		local ch = str:sub(i, i)

		if ch == char_open then
			local sublist
			sublist, i = self:_parse_list(str, i)
			table.insert(result, sublist)
		elseif ch == char_close then
			if token ~= "" then
				local num = tonumber(token)
				table.insert(result, num or token)
			end
			return result, i
		elseif ch == " " or ch == "\t" or ch == "\n" then
			if token ~= "" then
				local num = tonumber(token)
				table.insert(result, num or token)
				token = ""
			end
		else
			token = token .. ch
		end

		i = i + 1
	end

	return result, i
end

-- ─────────────────────────────────────
--- Copies a Lua value thoroughly.
---
--- Tables are copied deeply; nested tables are recursively cloned to ensure
--- complete state isolation across Pd's dataflow execution branches.
---@param obj any Value to copy.
---@return any copy Copied value with no shared references.
function M:_deep_copy_table(obj, copies)
	if type(obj) ~= "table" then
		return obj
	end

	copies = copies or {}
	if copies[obj] then
		return copies[obj]
	end

	local copy = {}
	copies[obj] = copy

	for k, v in pairs(obj) do
		if type(v) == "table" then
			copy[k] = self:_deep_copy_table(v, copies)
		else
			copy[k] = v
		end
	end

	return copy
end

-- ─────────────────────────────────────
--- Creates a new dddd instance from Pd atoms.
---
--- The atom list is converted into a nested Lua table when possible.
---@param pdobj table Pd object instance owning this dddd.
---@param atoms table|any Pd atoms or a scalar value.
---@return table obj New dddd instance.
function M:new(pdobj, atoms)
	local obj = setmetatable({}, self)
	obj.atoms = atoms or {}
	obj.table = self:table_from_atoms(atoms)
	obj.pdobj = pdobj
	obj.depth = self:get_depth(obj.table)
	return obj
end

-- ─────────────────────────────────────
--- Creates a new dddd instance from an existing Lua table.
---@param pdobj table Pd object instance owning this dddd.
---@param t table Source table.
---@return table obj New dddd instance.
function M:new_from_table(pdobj, t)
	local obj = setmetatable({}, self)
	obj.pdobj = pdobj
	obj.table = t
	obj.depth = self:get_depth(obj.table)
	return obj
end

-- ─────────────────────────────────────
--- Creates a dddd by resolving an id from a Pd atom list.
---@param pdobj table Pd object instance owning this dddd.
---@param t table Atom list where the first item is the dddd id.
---@return table obj Cloned dddd instance referenced by id.
function M:new_from_atoms(pdobj, t)
	local id = t[1]
	return M:new_from_id(pdobj, id)
end

-- ─────────────────────────────────────
--- Creates a dddd clone from a previously emitted dddd outlet id.
---@param pdobj table Pd object instance owning this dddd.
---@param id string Outlet id token (for example: <abc123...>).
---@return table obj Cloned dddd instance.
function M:new_from_id(pdobj, id)
	local obj = setmetatable({}, self)
	obj.atoms = {}

	local stored = _G.dddd_outlets[id]
	if stored == nil then
		error("dddd outlet id " .. tostring(id) .. " not found")
	end

	local source_table
	if type(stored) == "table" and type(stored.get_table) == "function" then
		source_table = stored:get_table()
	else
		source_table = stored
	end

	obj.table = M._deep_copy_table(self, source_table)

	-- init metadata
	obj.depth = self:get_depth(obj.table)
	obj._id = M:_random_string()
	obj.pdobj = pdobj

	return obj
end

-- ─────────────────────────────────────
--- Sets a semantic type tag for this dddd instance.
---@param typename string Type name to associate with this object.
function M:set_type(typename)
	self.type = typename
end

-- ─────────────────────────────────────
--- Returns the semantic type tag of this dddd instance.
---@return string|nil typename Current type tag, if set.
function M:get_type()
	return self.type or nil
end

-- ─────────────────────────────────────
--- Validates that the provided type matches the stored type.
---@param typename string Type name to validate.
function M:assert_type(typename)
	if typename ~= self.type then
		self.pdobj:error("[" .. self.pdobj._name .. "] Expected type " .. self.type .. " received type " .. typename)
		error("[" .. self.pdobj._name .. "] Expected type " .. self.type .. " received type " .. typename)
	end
end

-- ─────────────────────────────────────
--- Retrieves and clones a dddd from the global outlet table.
---@param pdobj table Pd object instance owning this dddd.
---@param id string Outlet id token.
---@return table cloned Cloned dddd object.
function M:get_dddd_from_id(pdobj, id)
	local original = _G.dddd_outlets[id]
	if not original then
		self.pdobj:error("[" .. self.pdobj._name .. "] " .. "dddd with id " .. tostring(id) .. " not found")
		error("dddd with id " .. tostring(id) .. " not found")
	end

	local cloned_table = M._deep_copy_table(original:get_table())
	local cloned = M:new_from_table(pdobj, cloned_table)
	return cloned
end

-- ─────────────────────────────────────
--- Emits this dddd through a Pd outlet using temporary id indirection.
---@param i integer Outlet index.
function M:output(i)
	local id = M:_random_string()
	local str = "<" .. id .. ">"
	_G.dddd_outlets[str] = self
	pd._outlet(self.pdobj._object, i, "dddd", { str })
	_G.dddd_outlets[str] = nil -- clear memory
end

-- ─────────────────────────────────────
--- Computes depth of any nested table recursively.
---@param tbl any Value or nested table.
---@return integer depth Nesting depth, 0 for non-table values.
function M:get_depth(tbl)
	if type(tbl) ~= "table" then
		return 0
	end
	local max_depth = 0
	for _, v in ipairs(tbl) do
		local d = self:get_depth(v)
		if d > max_depth then
			max_depth = d
		end
	end
	return max_depth + 1
end

-- ─────────────────────────────────────
function M:get_table_depth()
	return self:get_depth(self.table)
end

-- ─────────────────────────────────────
--- Parses a parenthesized or bracketed list string into a Lua table.
---@param str string Serialized nested list.
---@return table|nil result Parsed table, or nil if format is invalid.
function M:lisplist_to_table(str)
	local list_b = str:match("^%s*(%b[])%s*$")
	local result
	if list_b then
		result = self:_parse_list(list_b, 1)
	end

	local list_p = str:match("^%s*(%b())%s*$")
	if list_p then
		result = self:_parse_list(list_p, 1)
	end
	return result
end

-- ─────────────────────────────────────
--- Converts Pd atoms to an internal Lua table representation.
---
--- The bracket style is inferred and stored for later serialization.
---@param atoms table|any Pd atoms or scalar value.
---@return table|any parsed Parsed nested table or original scalar.
function M:table_from_atoms(atoms)
	local parts = {}
	if type(atoms) == "table" then
		for _, v in ipairs(atoms) do
			table.insert(parts, tostring(v))
		end
	else
		self._s_open = "("
		self._s_close = ")"
		self.table = atoms
		return self.table
	end

	local str = table.concat(parts, " ")
	local open, _ = self:check_brackets(str)

	local list_str
	if open == "(" then
		list_str = "(" .. str .. ")"
		self._s_open = "("
		self._s_close = ")"
	elseif open == "[" then
		list_str = "[" .. str .. "]"
		self._s_open = "["
		self._s_close = "]"
	else
		return
	end

	self.table = self:lisplist_to_table(list_str)
	return self.table
end

-- ─────────────────────────────────────
--- Prints the current dddd value to the Pd console.
---
--- Tables are flattened to a readable nested string form.
function M:print()
	if type(self.table) ~= "table" then
		pd.post(self.table)
		return
	end

	local parts = {}
	for _, v in ipairs(self.table) do
		if type(v) == "table" then
			table.insert(parts, self:to_string(v))
		else
			table.insert(parts, tostring(v))
		end
	end
	pd.post(self._s_open .. table.concat(parts, " ") .. self._s_close)
end

-- ─────────────────────────────────────
--- Serializes a Lua value/table to a nested dddd string.
---@param tbl any Value to serialize.
---@return string serialized String representation using current bracket style.
function M:to_string(tbl)
	if type(tbl) ~= "table" then
		return tostring(tbl)
	end

	local parts = {}
	for _, v in ipairs(tbl) do
		if type(v) == "table" then
			table.insert(parts, self:to_string(v))
		else
			table.insert(parts, tostring(v))
		end
	end

	if self._s_open == nil or self._s_close == nil then
		self._s_open = "("
		self._s_close = ")"
	end

	return self._s_open .. table.concat(parts, " ") .. self._s_close
end

-- ─────────────────────────────────────
--- Detects bracket style used in a serialized list.
---
--- Mixed bracket and parenthesis syntax is rejected.
---@param str string Serialized list string.
---@return string|nil open Opening delimiter.
---@return string|nil close Closing delimiter.
function M:check_brackets(str)
	local thereis_b = str:find("%[") or str:find("%]")
	local thereis_p = str:find("%(") or str:find("%)")

	if thereis_b and thereis_p then
		self.pdobj:error("[" .. self.pdobj._name .. "] " .. "mixed brackets and parenthesis are not allowed")
		error("mixed brackets and parenthesis are not allowed")
	elseif not thereis_b and not thereis_p then
		return "[", "]"
	elseif thereis_b then
		return "[", "]"
	elseif thereis_p then
		return "(", ")"
	else
		return nil, nil
	end
end

-- ─────────────────────────────────────
--- Returns the internal table reference for this dddd.
---@return any table_value Current internal value/table.
function M:get_table()
	return self.table
end

return M
