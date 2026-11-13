-- What space does while there is input, set by mixed/space in the schema
-- (or a .custom.yaml patch):
--
--   page   next page, wrapping from the last page back to page 1, as in
--          Quick Classic. Also pages the associated phrases
--          (mixed_predict.lua). Rime's key_binder can send Page_Down for
--          space but cannot tell when it is on the last page, hence a
--          processor. (default)
--   first  commit the first candidate, as in Cangjie (Rime's own behaviour;
--          this script steps aside)
--   raw    commit the typed letters and a space: "hello" + space gives
--          "hello ". Chinese is picked only with 1-9 or by tapping the
--          candidate bar; suits touch keyboards.
--          Punctuation is ASCII unless the character before it is Chinese:
--          "hello" + "," gives "hello,", 我 + "," gives 我，, "我 " + ","
--          gives "我 ,", 我 + "2" + "," gives 我2,. At the start (nothing
--          typed yet) it is ASCII.
--          Typing a full-width mark directly (e.g. a key that sends ，)
--          is left alone.
--
-- With first and raw, space on the associated phrases dismisses them and
-- types a space (mixed_predict.lua).

local kRejected, kAccepted, kNoop = 0, 1, 2

-- next page, wrapping to the first
local function page(ctx, env)
	local seg = ctx.composition:back()
	local menu = seg.menu
	if not menu or menu:prepare(1) == 0 then
		return kNoop                    -- no candidates: space does what it did
	end
	local size = env.page_size > 0 and env.page_size or 9
	local next = (seg.selected_index // size + 1) * size
	if menu:prepare(next + 1) > next then
		seg.selected_index = next
	else
		seg.selected_index = 0          -- last page: back to the first
	end
	return kAccepted
end

-- the ASCII punctuation a key types, or nil
local function punctuation(key)
	if key:ctrl() or key:alt() or key:super() then
		return nil
	end
	local code = key.keycode
	if code <= 0x20 or code >= 0x7f then
		return nil
	end
	local ch = string.char(code)
	if ch:match("%w") then
		return nil                      -- letters type, digits pick
	end
	return ch
end

-- does text end in Chinese (CJK, full-width forms ...)? nil: empty
local function ends_chinese(text)
	local last
	for _, c in utf8.codes(text) do
		last = c
	end
	if last then
		return last >= 0x2E80
	end
end

-- commit_text skips the commit notifier, so tell mixed_predict.lua too
local function commit(env, text)
	env.engine:commit_text(text)
	env.engine.context:set_property("mixed_before", text)
	local cjk = ends_chinese(text)
	if cjk ~= nil then
		env.last_chinese = cjk
	end
end

local P = {}

function P.init(env)
	local config = env.engine.schema.config
	env.page_size = env.engine.schema.page_size
	local mode = config:get_string("mixed/space")
	if mode ~= "first" and mode ~= "raw" then
		mode = "page"
	end
	env.mode = mode
	if mode == "raw" then
		env.last_chinese = false        -- nothing typed yet: ASCII
		env.commit_conn = env.engine.context.commit_notifier:connect(function(c)
			local cjk = ends_chinese(c:get_commit_text())
			if cjk ~= nil then
				env.last_chinese = cjk
			end
		end)
	end
end

function P.fini(env)
	if env.commit_conn then
		env.commit_conn:disconnect()
	end
end

function P.func(key, env)
	if env.mode == "first" or key:release() then
		return kNoop
	end
	local ctx = env.engine.context
	if env.mode == "raw" and not ctx:get_option("ascii_mode") then
		local name = key:repr()
		if ctx.input == "" and (name == "space" or name == "Return")
				or (ctx.composition:empty()
					or ctx.composition:back():has_tag("hint"))
				and name:match("^%d$") then
			env.last_chinese = false    -- it reaches the app as is
		end                             -- (a digit on associated phrases picks)
		local ch = punctuation(key)
		if ch then
			if ctx.input ~= "" then
				commit(env, ctx.input .. ch)     -- letters: ASCII
				ctx:clear()
				return kAccepted
			end
			if not ctx.composition:empty() then
				ctx:clear()             -- associated phrases: dismiss, so
			end                         -- , . don't page them
			if not env.last_chinese then
				commit(env, ch)
				return kAccepted
			end
			return kNoop                -- after Chinese: the punctuator
		end
	end
	if ctx.composition:empty() then
		return kNoop
	end
	local space = key:repr() == "space"
	if env.mode == "page" then
		return space and page(ctx, env) or kNoop
	end
	if ctx.input == "" or not space then
		return kNoop                    -- associated phrases: mixed_predict
	end
	commit(env, ctx.input .. " ")
	ctx:clear()
	return kAccepted
end

return P
