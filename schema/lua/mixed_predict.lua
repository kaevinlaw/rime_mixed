-- Associated phrases after a commit, as in Mixed Chinese Keyboard Plus.
--
-- After text is committed, the words that may follow it (mixed_predict.txt,
-- made by convert.py from phrase_*.ms2) are shown as candidates with no
-- input. Picking one commits it and looks up the longer text, so
-- 我 -> 不 -> 能 offers 忘記你 (key 我不能). If the whole text has no entry,
-- its tail is tried: 我不能 -> 不能 -> 能.
--
-- While suggestions are showing:
--   1-9, = -, Page_Up/Down         pick / page, as usual
--   space                          next page, wraps (mixed_paging.lua); with
--                                  mixed/space: first or raw, as Return
--   a letter                       starts normal input (suggestions go)
--   Escape, BackSpace              dismiss only
--   Return                         dismiss, and the key reaches the app
--
-- Off with mixed/associated_phrases: false.
--
-- Same technique as librime-predict: a (0, 0) segment tagged "prediction"
-- carrying its own menu, added after the engine has recomposed.

local kRejected, kAccepted, kNoop = 0, 1, 2

local db                                -- shared by all sessions

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
	local text = env.pending
	env.pending = nil
	env.key = nil
	if not text or ctx.input ~= "" or not ctx.composition:empty() then
		return
	end
	local key, words = lookup(text)
	if not key then
		return
	end
	local translation = Translation(function()
		for _, w in ipairs(words) do
			yield(Candidate("prediction", 0, 0, w, ""))
		end
	end)
	local menu = Menu()
	menu:add_translation(translation)
	local seg = Segment(0, 0)
	seg.tags = Set({ "prediction", "placeholder" })
	seg.menu = menu
	ctx.composition:push_back(seg)
	env.key = key
end

local P = {}

function P.init(env)
	env.enabled = env.engine.schema.config:get_bool("mixed/associated_phrases") ~= false
	if not env.enabled then
		return
	end
	if not db then
		db = load_db()
	end
	local ctx = env.engine.context
	env.commit_conn = ctx.commit_notifier:connect(function(c)
		local text = c:get_commit_text()
		if text == "" then
			return
		end
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

function P.func(key, env)
	local ctx = env.engine.context
	if not env.enabled or key:release() or not showing(ctx) then
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
		return kRejected                -- let the app have the key
	end
	return kNoop
end

return P
