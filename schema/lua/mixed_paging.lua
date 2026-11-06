-- Space pages forward through the candidates and wraps from the last page
-- back to page 1, as in Quick Classic. Works for typed input and for the
-- associated phrases (mixed_predict.lua). Pick with 1-9; Return still ends
-- the associated phrases.
--
-- Rime's key_binder can send Page_Down for space but cannot tell when it is
-- on the last page, hence a processor.
--
-- Off with mixed/space_pages: false in the schema (or a .custom.yaml patch);
-- space then commits the first candidate, as in Cangjie.

local kRejected, kAccepted, kNoop = 0, 1, 2

local P = {}

function P.init(env)
	local config = env.engine.schema.config
	env.page_size = env.engine.schema.page_size
	env.enabled = config:get_bool("mixed/space_pages") ~= false   -- default on
end

function P.func(key, env)
	if not env.enabled or key:release() or key:repr() ~= "space" then
		return kNoop
	end
	local ctx = env.engine.context
	if ctx.composition:empty() then
		return kNoop
	end
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

return P
