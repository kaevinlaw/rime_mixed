-- Adds the Cangjie radicals of the typed letters as a candidate:
-- "mm" offers 一一, "hqi" offers 竹手戈. For writing out a code, e.g. when
-- telling someone how to type a character.
--
-- mixed/radical_candidate in the schema (or a .custom.yaml patch) is the
-- position in the list: 1 = first (default), 2 = second ...; 0 = off.
-- If there are fewer candidates, it comes last.

local radicals = {
	a = "日", b = "月", c = "金", d = "木", e = "水", f = "火", g = "土",
	h = "竹", i = "戈", j = "十", k = "大", l = "中", m = "一", n = "弓",
	o = "人", p = "心", q = "手", r = "口", s = "尸", t = "廿", u = "山",
	v = "女", w = "田", x = "難", y = "卜", z = "重",
}

local F = {}

function F.init(env)
	env.pos = env.engine.schema.config:get_int("mixed/radical_candidate") or 1
end

function F.func(input, env)
	local ctx = env.engine.context
	local seg = not ctx.composition:empty() and ctx.composition:back()
	local code = seg and ctx.input:sub(seg.start + 1, seg._end) or ""
	if env.pos <= 0 or not code:match("^[a-z]+$") then
		for cand in input:iter() do
			yield(cand)
		end
		return
	end
	local text = code:gsub(".", radicals)
	local mine = Candidate("radicals", seg.start, seg._end, text, "")
	-- the input line shows the highlighted candidate's preedit; borrow the
	-- dictionary's (translator/preedit_format: "hqi 竹手戈"), else it is "hqi"
	local n, done = 0, false
	for cand in input:iter() do
		n = n + 1
		mine.preedit = cand.preedit
		if not done and n == env.pos then
			yield(mine)
			done = true
		end
		if cand.text ~= text then
			yield(cand)
		end
	end
	if not done then
		yield(mine)
	end
end

return F
