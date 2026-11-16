-- Fuzzy Cangjie, for touch keyboards: a key slips onto its neighbour.
-- For 3-5 typed letters (see mixed/fuzzy_min), the characters whose code differs only by
-- neighbouring keys come after the exact characters: "hqo" (失) also
-- offers 我 (hqi), and so does "hwo" (two keys off). Neighbours are the keys
-- left and right in the same QWERTY row (h: g j), as librime's own typo
-- corrector. The first letter is taken as typed. Single characters only,
-- never words, and only by their Cangjie code (mixed_cangjie.txt, as for
-- the Cangjie hint): a Cantonese code a key away (ngo, ngi) is not offered.
--
-- Picking one learns it under its real code: 我 picked from "hqo" ranks
-- higher for "hqi", nothing is written under "hqo" (the candidate is the
-- dictionary's own entry for hqi, so table_translator learns that). The
-- Cangjie hint (mixed_predict.lua) then shows the real code: 〔我 竹手戈〕.
--
-- Order: fewer wrong letters first; within that, characters you picked
-- before (under their real code) first, then the dictionary's order. Inserted before the first candidate that is not
-- an exact single character (a word, a completion, English), else last.
--
-- mixed/fuzzy: how many letters may be wrong, 0 (off) to 4 (all but the
-- first of a 5-letter code); default 2. More finds more, but lists more
-- unrelated characters too.
-- mixed/fuzzy_min: the fewest letters typed before it starts, 2 to 5;
-- default 3. With 2, "an" (日弓) also offers 明 (ab).
-- Used by mixed_cangjie.schema.yaml.

local ROWS = { "qwertyuiop", "asdfghjkl", "zxcvbnm" }
local NEIGHBOURS = {}                   -- NEIGHBOURS["h"] = { "g", "j" }
for _, row in ipairs(ROWS) do
	for i = 1, #row do
		local n = {}
		if i > 1 then n[#n + 1] = row:sub(i - 1, i - 1) end
		if i < #row then n[#n + 1] = row:sub(i + 1, i + 1) end
		NEIGHBOURS[row:sub(i, i)] = n
	end
end

local RADICALS = {
	a = "日", b = "月", c = "金", d = "木", e = "水", f = "火", g = "土",
	h = "竹", i = "戈", j = "十", k = "大", l = "中", m = "一", n = "弓",
	o = "人", p = "心", q = "手", r = "口", s = "尸", t = "廿", u = "山",
	v = "女", w = "田", x = "難", y = "卜", z = "重",
}

-- codes with 1..max letters moved to a neighbouring key, the first letter
-- kept: out[d] lists those with d letters moved
local function variants(code, max)
	local out = {}
	for d = 1, max do
		out[d] = {}
	end
	local function walk(i, prefix, d)
		if i > #code then
			if d > 0 then
				table.insert(out[d], prefix)
			end
			return
		end
		local c = code:sub(i, i)
		walk(i + 1, prefix .. c, d)
		if d < max then
			for _, n in ipairs(NEIGHBOURS[c]) do
				walk(i + 1, prefix .. n, d + 1)
			end
		end
	end
	walk(2, code:sub(1, 1), 0)
	return out
end

local function single(text)
	return utf8.len(text) == 1
end

local cangjie                           -- cangjie[character] = code, shared

local function load_cangjie()
	local t = {}
	local path = rime_api.get_user_data_dir() .. "/mixed_cangjie.txt"
	local f = io.open(path, "r")
	if not f then
		log.error("mixed_fuzzy: cannot open " .. path)
		return t
	end
	for line in f:lines() do
		local char, code = line:match("^([^#\t][^\t]*)\t(%a+)$")
		if char then
			t[char] = code
		end
	end
	f:close()
	return t
end

-- fuzzy candidates for code, minus the texts in skip
local function fuzzy(env, code, seg, skip)
	local out, seen = {}, {}
	local by_weight = function(a, b) return a.entry.weight > b.entry.weight end
	for _, codes in ipairs(variants(code, env.max)) do   -- 1 wrong, 2 wrong ...
		local learned, plain = {}, {}
		local function add(list, entry, user, v)
			if single(entry.text) and cangjie[entry.text] == v
					and not skip[entry.text] and not seen[entry.text] then
				seen[entry.text] = true
				list[#list + 1] = { entry = entry, user = user }
			end
		end
		for _, v in ipairs(codes) do
			if env.mem:user_lookup(v, false) then
				for entry in env.mem:iter_user() do
					add(learned, entry, true, v)
				end
			end
		end
		for _, v in ipairs(codes) do
			if env.mem:dict_lookup(v, false, 0) then
				for entry in env.mem:iter_dict() do
					add(plain, entry, false, v)
				end
			end
		end
		table.sort(learned, by_weight)
		table.sort(plain, by_weight)
		for _, list in ipairs({ learned, plain }) do
			for _, item in ipairs(list) do
				local phrase = Phrase(env.mem, item.user and "user_table" or "table",
					seg.start, seg._end, item.entry)
				out[#out + 1] = phrase:toCandidate()
			end
		end
	end
	return out
end

local F = {}

function F.init(env)
	local config = env.engine.schema.config
	local max = config:get_int("mixed/fuzzy")
	if max == nil then                  -- true / false, or not set
		max = config:get_bool("mixed/fuzzy") == false and 0 or 2
	end
	env.max = math.max(0, math.min(4, max))
	env.min = math.max(2, math.min(5, config:get_int("mixed/fuzzy_min") or 3))
	env.on = env.max > 0
	if env.on then
		env.mem = Memory(env.engine, env.engine.schema)   -- translator's dictionary
		cangjie = cangjie or load_cangjie()
	end
end

function F.func(input, env)
	local ctx = env.engine.context
	local seg = not ctx.composition:empty() and ctx.composition:back()
	local code = seg and ctx.input:sub(seg.start + 1, seg._end) or ""
	if not env.on or #code < env.min or #code > 5 or not code:match("^[a-z]+$") then
		for cand in input:iter() do
			yield(cand)
		end
		return
	end
	local exact, preedit, done = {}, nil, false
	local function insert()
		done = true
		for _, cand in ipairs(fuzzy(env, code, seg, exact)) do
			-- the input line shows the highlighted candidate's preedit:
			-- the dictionary's ("hqo 竹手人"), as for the others
			cand.preedit = preedit or code .. " " .. code:gsub(".", RADICALS)
			yield(cand)
		end
	end
	for cand in input:iter() do
		preedit = preedit or cand.preedit
		if not done then
			local t = cand.type
			if single(cand.text) and (t == "table" or t == "user_table") then
				exact[cand.text] = true
			else
				insert()
			end
		end
		yield(cand)
	end
	if not done then
		insert()
	end
end

return F
