-- Json.lua : small JSON encoder / decoder compatible with Lua 5.0 (WoW 1.12)
SkullEPGP_Json = {}
local J = SkullEPGP_Json

J.null = {}

local ESC = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function utf8char(cp)
	if cp < 128 then
		return string.char(cp)
	elseif cp < 2048 then
		local a = math.floor(cp / 64)
		return string.char(192 + a, 128 + (cp - a * 64))
	else
		local a = math.floor(cp / 4096)
		local r = cp - a * 4096
		local b = math.floor(r / 64)
		return string.char(224 + a, 128 + b, 128 + (r - b * 64))
	end
end

local function skipws(s, i)
	local _, e = string.find(s, "^[ \t\r\n]*", i)
	return e + 1
end

local parseValue

local function parseString(s, i)
	local buf = {}
	local j = i + 1
	while true do
		local a = string.find(s, '["\\]', j)
		if not a then error("unterminated string (position " .. i .. ")", 0) end
		if a > j then table.insert(buf, string.sub(s, j, a - 1)) end
		local c = string.sub(s, a, a)
		if c == '"' then
			return table.concat(buf), a + 1
		end
		local n = string.sub(s, a + 1, a + 1)
		if n == "u" then
			local hex = string.sub(s, a + 2, a + 5)
			if not string.find(hex, "^%x%x%x%x$") then error("invalid \\u sequence (position " .. a .. ")", 0) end
			table.insert(buf, utf8char(tonumber(hex, 16)))
			j = a + 6
		else
			local m = ESC[n]
			if not m then error("invalid escape (position " .. a .. ")", 0) end
			table.insert(buf, m)
			j = a + 2
		end
	end
end

parseValue = function(s, i)
	i = skipws(s, i)
	local c = string.sub(s, i, i)
	if c == "{" then
		local t = {}
		i = skipws(s, i + 1)
		if string.sub(s, i, i) == "}" then return t, i + 1 end
		while true do
			i = skipws(s, i)
			if string.sub(s, i, i) ~= '"' then error("key expected (position " .. i .. ")", 0) end
			local key
			key, i = parseString(s, i)
			i = skipws(s, i)
			if string.sub(s, i, i) ~= ":" then error("':' expected (position " .. i .. ")", 0) end
			local val
			val, i = parseValue(s, i + 1)
			if val ~= J.null then t[key] = val end
			i = skipws(s, i)
			local d = string.sub(s, i, i)
			if d == "}" then return t, i + 1 end
			if d ~= "," then error("',' or '}' expected (position " .. i .. ")", 0) end
			i = i + 1
		end
	elseif c == "[" then
		local t = {}
		local n = 0
		i = skipws(s, i + 1)
		if string.sub(s, i, i) == "]" then return t, i + 1 end
		while true do
			local val
			val, i = parseValue(s, i)
			n = n + 1
			t[n] = val
			i = skipws(s, i)
			local d = string.sub(s, i, i)
			if d == "]" then return t, i + 1 end
			if d ~= "," then error("',' or ']' expected (position " .. i .. ")", 0) end
			i = i + 1
		end
	elseif c == '"' then
		return parseString(s, i)
	elseif c == "t" and string.sub(s, i, i + 3) == "true" then
		return true, i + 4
	elseif c == "f" and string.sub(s, i, i + 4) == "false" then
		return false, i + 5
	elseif c == "n" and string.sub(s, i, i + 3) == "null" then
		return J.null, i + 4
	else
		local _, e = string.find(s, "^-?%d+%.?%d*", i)
		if not e then error("unexpected value (position " .. i .. ")", 0) end
		local _, e2 = string.find(s, "^[eE][+-]?%d+", e + 1)
		if e2 then e = e2 end
		return tonumber(string.sub(s, i, e)), e + 1
	end
end

-- Decode(text) -> value ; raises an error (string) if invalid. Call it through pcall.
function J.Decode(s)
	if string.sub(s, 1, 3) == "\239\187\191" then s = string.sub(s, 4) end
	local v, i = parseValue(s, 1)
	i = skipws(s, i)
	if i <= string.len(s) then error("trailing text after the end of the JSON (position " .. i .. ")", 0) end
	return v
end

local function escape(str)
	str = string.gsub(str, '[%c"\\]', function(c)
		if c == '"' then return '\\"' end
		if c == "\\" then return "\\\\" end
		if c == "\n" then return "\\n" end
		if c == "\r" then return "\\r" end
		if c == "\t" then return "\\t" end
		return string.format("\\u%04x", string.byte(c))
	end)
	return str
end

local function isArray(t)
	return table.getn(t) > 0 or next(t) == nil
end

function J.Encode(v)
	local tv = type(v)
	if tv == "string" then
		return '"' .. escape(v) .. '"'
	elseif tv == "number" then
		return tostring(v)
	elseif tv == "boolean" then
		return v and "true" or "false"
	elseif tv == "table" then
		local out = {}
		if isArray(v) then
			for i = 1, table.getn(v) do table.insert(out, J.Encode(v[i])) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do table.insert(keys, tostring(k)) end
		table.sort(keys)
		for i = 1, table.getn(keys) do
			local k = keys[i]
			local val = v[k]
			if val == nil then val = v[tonumber(k)] end
			table.insert(out, '"' .. escape(k) .. '":' .. J.Encode(val))
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end
