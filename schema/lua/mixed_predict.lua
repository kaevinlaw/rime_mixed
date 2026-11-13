-- Associated phrases after a commit, as in Mixed Chinese Keyboard Plus.
--
-- After text is committed, the words that may follow it (mixed_predict.txt,
-- made by convert.py from phrase_*.ms2) are shown as candidates with no
-- input. Picking one commits it and looks up the longer text, so
-- 我 -> 不 -> 能 offers 忘記你 (key 我不能). If the whole text has no entry,
-- its tail is tried: 我不能 -> 不能 -> 能.
--
-- Learning, as the app's "related words": whenever Chinese is committed
-- right after Chinese, the pair (last character before, committed word) is
-- counted, however the word was typed: 我 then 們 counts 我 -> 們. After a
-- commit, up to LEARNED_SHOWN learned words for its last character come
-- first, most used first (ties: most recent), then the built-in list.
-- Pairs not used for EXPIRE_DAYS days are forgotten. Stored in
-- mixed_predict.user.txt in the user folder (one line per change, compacted
-- on load); delete it to start over. Not part of Rime's sync.
--
-- A key that reaches the app (space, Return, a digit, arrows ...) breaks
-- the pair: 我 space 們 is not counted. mixed_paging.lua commits ASCII
-- itself and says so through the context property "mixed_before".
--
-- While suggestions are showing:
--   1-9, = -, Page_Up/Down         pick / page, as usual
--   space                          next page, wraps (mixed_paging.lua); with
--                                  mixed/space: first or raw, as Return
--   a letter                       starts normal input (suggestions go)
--   Escape, BackSpace              dismiss only
--   Return                         dismiss, and the key reaches the app
--
-- Off with mixed/associated_phrases: false (no learning either).
--
-- Cangjie hint: after picking a single character typed with a code other
-- than its Cangjie code (Quick "hi", Cantonese "ngo", a partial "hq"), or
-- picked from the associated phrases (我 -> 想), the input line shows its
-- Cangjie code as radicals: 〔我 竹手戈〕. Codes from mixed_cangjie.txt
-- (cangjie.py, from Unihan). With no associated phrases to show, the hint
-- shows alone; any key dismisses it and then does what it does. Off with
-- mixed/cangjie_hint: false.
--
-- Same technique as librime-predict: a (0, 0) segment tagged "prediction"
-- carrying its own menu, added after the engine has recomposed.

local kRejected, kAccepted, kNoop = 0, 1, 2

local LEARNED_SHOWN = 5                 -- the app's default
local EXPIRE_DAYS = 30                  -- the app's default: 1 month
local MAX_WORD = 8                      -- longer commits are not learned

local db                                -- built-in, shared by all sessions
local cangjie                           -- cangjie[character] = code
local learned                           -- learned[parent][child] = {count, last}
local user_path

local function load_db()
	local t = {}
	local path = rime_api.get_user_data_dir() .. "/mixed_predict.txt"
	local f = io.open(path, "r")
	if not f then
		log.error("mixed_predict: cannot open " .. path)
		return t
	end
	for line in f:lines() do
		local key, rest = line:match("^([^\t]+)\t(.*)$")
		if key then
			local words = {}
			for w in rest:gmatch("[^\t]+") do
				words[#words + 1] = w
			end
			t[key] = words
		end
	end
	f:close()
	return t
end

local RADICALS = {
	a = "日", b = "月", c = "金", d = "木", e = "水", f = "火", g = "土",
	h = "竹", i = "戈", j = "十", k = "大", l = "中", m = "一", n = "弓",
	o = "人", p = "心", q = "手", r = "口", s = "尸", t = "廿", u = "山",
	v = "女", w = "田", x = "難", y = "卜", z = "重",
}

local function load_cangjie()
	local t = {}
	local path = rime_api.get_user_data_dir() .. "/mixed_cangjie.txt"
	local f = io.open(path, "r")
	if not f then
		log.error("mixed_predict: cannot open " .. path)
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

-- 〔我 竹手戈〕 if text is one character typed with another code, or
-- picked with no code at all (typed "": an associated phrase)
local function hint_for(text, typed)
	if utf8.len(text) ~= 1 or typed ~= "" and not typed:match("^[a-z]+$") then
		return nil
	end
	local code = cangjie[text]
	if not code or code == typed then
		return nil
	end
	return "〔" .. text .. " " .. (code:gsub(".", RADICALS)) .. "〕"
end

-- Read the learned pairs (later lines win), drop expired ones and write
-- the file back with one line per pair.
local function load_learned()
	local t = {}
	user_path = rime_api.get_user_data_dir() .. "/mixed_predict.user.txt"
	local f = io.open(user_path, "r")
	if not f then
		return t
	end
	local oldest = os.time() - EXPIRE_DAYS * 86400
	for line in f:lines() do
		local parent, child, count, last =
			line:match("^([^\t]+)\t([^\t]+)\t(%d+)\t(%d+)$")
		if parent then
			t[parent] = t[parent] or {}
			t[parent][child] = { tonumber(count), tonumber(last) }
		end
	end
	f:close()
	local lines = {}
	for parent, children in pairs(t) do
		for child, e in pairs(children) do
			if e[2] < oldest then
				children[child] = nil
			else
				lines[#lines + 1] = table.concat({ parent, child, e[1], e[2] }, "\t")
			end
		end
	end
	f = io.open(user_path, "w")
	if f then
		f:write(table.concat(lines, "\n"), #lines > 0 and "\n" or "")
		f:close()
	end
	return t
end

local function is_han(c)
	return c >= 0x3400 and c <= 0x9FFF or c >= 0xF900 and c <= 0xFAFF
		or c >= 0x20000 and c <= 0x3FFFF
end

-- last character of text if it is Chinese, else nil
local function han_tail(text)
	local last
	for _, c in utf8.codes(text) do
		last = c
	end
	if last and is_han(last) then
		return utf8.char(last)
	end
end

-- whole text Chinese and short enough to learn
local function han_word(text)
	local n = 0
	for _, c in utf8.codes(text) do
		if not is_han(c) then
			return false
		end
		n = n + 1
	end
	return n > 0 and n <= MAX_WORD
end

local function learn(parent, child)
	learned[parent] = learned[parent] or {}
	local e = learned[parent][child] or { 0, 0 }
	e[1], e[2] = e[1] + 1, os.time()
	learned[parent][child] = e
	local f = io.open(user_path, "a")
	if f then
		f:write(table.concat({ parent, child, e[1], e[2] }, "\t"), "\n")
		f:close()
	end
end

-- up to LEARNED_SHOWN learned words after parent, most used first
local function learned_words(parent)
	local children = parent and learned[parent]
	if not children then
		return {}
	end
	local oldest = os.time() - EXPIRE_DAYS * 86400
	local list = {}
	for child, e in pairs(children) do
		if e[2] >= oldest then
			list[#list + 1] = { child, e[1], e[2] }
		end
	end
	table.sort(list, function(a, b)
		if a[2] ~= b[2] then
			return a[2] > b[2]
		end
		return a[3] > b[3]
	end)
	local words = {}
	for i = 1, math.min(#list, LEARNED_SHOWN) do
		words[i] = list[i][1]
	end
	return words
end

-- Longest tail of text that has an entry: 我不能, 不能, 能.
local function lookup(text)
	local pos = 1
	while pos <= #text do
		local words = db[text:sub(pos)]
		if words then
			return text:sub(pos), words
		end
		pos = utf8.offset(text, 2, pos)
		if not pos then
			break
		end
	end
end

local function showing(ctx)
	if ctx.input ~= "" or ctx.composition:empty() then
		return false
	end
	return ctx.composition:back():has_tag("prediction")
end

local function show(env, ctx)
	local text, hint = env.pending, env.hint
	env.pending, env.hint = nil, nil
	env.key = nil
	if not text or ctx.input ~= "" or not ctx.composition:empty() then
		return
	end
	local tail, mine, key, words
	if env.phrases then
		tail = han_tail(text)
		mine = learned_words(tail)
		key, words = lookup(text)
	end
	if not key and not (mine and #mine > 0) then
		if hint then                    -- the hint alone, no menu
			local seg = Segment(0, 0)
			seg.tags = Set({ "prediction", "placeholder", "hint" })
			seg.prompt = hint
			ctx.composition:push_back(seg)
		end
		return
	end
	local translation = Translation(function()
		local seen = {}
		for _, w in ipairs(mine) do
			seen[w] = true
			yield(Candidate("prediction", 0, 0, w, ""))
		end
		for _, w in ipairs(words or {}) do
			if not seen[w] then
				yield(Candidate("prediction", 0, 0, w, ""))
			end
		end
	end)
	local menu = Menu()
	menu:add_translation(translation)
	local seg = Segment(0, 0)
	seg.tags = Set({ "prediction", "placeholder" })
	seg.menu = menu
	seg.prompt = hint or ""
	ctx.composition:push_back(seg)
	env.key = key or tail
end

local P = {}

function P.init(env)
	local config = env.engine.schema.config
	env.phrases = config:get_bool("mixed/associated_phrases") ~= false
	env.hints = config:get_bool("mixed/cangjie_hint") ~= false
	env.enabled = env.phrases or env.hints
	if not env.enabled then
		return
	end
	if env.phrases and not db then
		db = load_db()
	end
	if env.phrases and not learned then
		learned = load_learned()
	end
	if env.hints and not cangjie then
		cangjie = load_cangjie()
	end
	local ctx = env.engine.context
	env.commit_conn = ctx.commit_notifier:connect(function(c)
		local text = c:get_commit_text()
		if text == "" then
			return
		end
		-- the radicals candidate (mixed_radicals.lua) is not a word
		local cand = c:get_selected_candidate()
		local real = not (cand and cand.type == "radicals")
		if env.hints and real and not c.composition:empty() then
			local seg = c.composition:back()
			env.hint = hint_for(text, c.input:sub(seg.start + 1, seg._end))
		end
		local parent = han_tail(c:get_property("mixed_before"))
		if env.phrases and real and parent and han_word(text) then
			learn(parent, text)
		end
		c:set_property("mixed_before", real and text or "")
		-- a picked suggestion continues the chain: 我 + 不 -> 我不
		if env.key and showing(c) then
			env.pending = env.key .. text
		else
			env.pending = text
		end
	end)
	-- runs after the engine's own update handler, so the segment survives
	env.update_conn = ctx.update_notifier:connect(function(c)
		show(env, c)
	end)
end

function P.fini(env)
	if env.enabled then
		env.commit_conn:disconnect()
		env.update_conn:disconnect()
	end
end

-- a key that types into the app itself, past Rime: breaks a learned pair.
-- Letters start input, modifiers alone do nothing.
local function reaches_app(key)
	local code = key.keycode
	if code >= 0xffe1 and code <= 0xffee then
		return false                    -- Shift, Control ... alone
	end
	if key:ctrl() or key:alt() or key:super() then
		return true
	end
	return not (code < 0x80 and string.char(code):match("%a"))
end

function P.func(key, env)
	local ctx = env.engine.context
	if not env.enabled or key:release() then
		return kNoop
	end
	local hint_only = showing(ctx) and ctx.composition:back():has_tag("hint")
	if not showing(ctx) or hint_only then
		if hint_only then               -- any key dismisses the hint
			ctx:clear()
			if key:repr() == "Escape" then
				return kAccepted        -- and Esc does nothing more
			end
		end
		if ctx.composition:empty() and reaches_app(key) then
			ctx:set_property("mixed_before", "")
		end
		return kNoop
	end
	local name = key:repr()
	if name == "Escape" or name == "BackSpace" then
		env.key = nil
		ctx:clear()
		return kAccepted
	end
	-- space only gets here with mixed/space: first or raw
	if name == "space" or name == "Return" then
		env.key = nil
		ctx:clear()
		ctx:set_property("mixed_before", "")
		return kRejected                -- let the app have the key
	end
	return kNoop
end

return P
