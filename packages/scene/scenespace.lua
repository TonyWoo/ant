local ecs = ...
local world = ecs.world

local su = require "util"

local mathpkg = import_package "ant.math"
local ms = mathpkg.stack
local math3d = require "math3d"

ecs.tag "hierarchy_tag"

ecs.component_alias("world_srt", "srt")
ecs.component_alias("hierarchy_transform", "transform")

ecs.component_alias("attach", "entityid")

ecs.singleton "hierarchy_transform_result"

local scene_space = ecs.system "scene_space"
scene_space.dependby "primitive_filter_system"
scene_space.singleton "event"
scene_space.singleton "hierarchy_transform_result"

local function find_children(marked, eid, componenttype)
	local e = world[eid]
	local pid = e[componenttype].parent
	if pid and marked[pid] then
		marked[eid] = pid
		return true
	end
	marked[eid] = false
	return false
end

local mark_mt = { __index = function(marked, eid) return find_children(marked, eid, "hierarchy_transform") end }

local render_mark_mt = {__index = function(marked, eid) return find_children(marked, eid, "transform") end}

local function mark_tree(tree, componenttype)
	for _, eid in world:each(componenttype) do
		local _ = tree[eid]
	end
end

local function tree_sort(tree)
	local r = {}

	local from = 1
	local to = 1
	-- find leaves
	local leaf = {}
	for eid, pid in pairs(tree) do
		if pid then
			if leaf[pid] then	-- fake leaf
				-- todo remove result
				for i = 1, to-1 do
					if r[i] == pid then
						to = to - 1
						r[i] = r[to]
						break
					end
				end
			end
			leaf[pid] = false
			if leaf[eid] == nil then
				leaf[eid] = true	-- mark leaf
				r[to] = eid
				to = to + 1
			end
		end
	end
	while to > from do
		local lb = from
		from = to
		for i = lb, to-1 do
			local pid = tree[r[i]]
			if pid and tree[pid] and not leaf[pid] then
				r[to] = pid
				to = to + 1
				leaf[pid] = true
			end
		end
	end
	return r
end

local function update_world(trans)
	local srt = ms:push_srt_matrix(trans)
	local base = trans.base
	local worldmat = trans.world
	if base then
		srt = ms(trans.base, srt, "*P")	
	end

	local peid = trans.parent
	if peid then
		local parent = world[peid]
		local pt = parent.hierarchy_transform
		ms(worldmat, pt.world, srt, "*=")
	else
		ms(worldmat, srt, "=")
	end
	return worldmat
end

local function fetch_sort_tree_result(tree, mark_mt, componenttype)
	setmetatable(tree, mark_mt)
	mark_tree(tree, componenttype)
	return tree_sort(tree)
end

local function update_scene_tree(tree, cache_result)
	if next(tree) then
		local sort_result = fetch_sort_tree_result(tree, mark_mt, "hierarchy_transform")

		for i = #sort_result, 1, -1 do
			local eid = sort_result[i]
			local e = world[eid]
			local t = e.hierarchy_transform
			local cachemat = update_world(t)
			assert(type(cachemat) == 'userdata')
			cache_result[eid] = cachemat
		end
	end
end

local function notify_render_child_changed(tree)
	if next(tree) then
		local sort_result = fetch_sort_tree_result(tree, render_mark_mt, "transform")
		for i = 1, #sort_result do
			local eid = sort_result[i]
			local e = world[eid]
			if e.hierarchy_transform then
				-- mean all the render child have been updated
				break
			end

			e.transform.watcher._marked_init = true
		end
	end
end

function scene_space:post_init()	
	for eid in world:each_new("hierarchy_transform") do
		local e = world[eid]
		local trans = e.hierarchy_transform		
		trans.world = math3d.ref "matrix"
		self.event:new(eid, "hierarchy_transform")
	end
end

function scene_space:delete()
	local hierarchy_cache = self.hierarchy_transform_result
	local tree = {}
	for eid in world:each_removed "hierarchy_transform" do
		hierarchy_cache[eid] = nil
	end

	for eid in pairs(hierarchy_cache) do
		local e = world[eid]
		tree[eid] = e.hierarchy_transform.parent		
	end

	update_scene_tree(tree, hierarchy_cache)
end

function scene_space:event_changed()	
	local tree = {}	
	local changed_parent = false
	for eid, events in self.event:each("hierarchy_transform") do
		local e = world[eid]
		local trans = e.hierarchy_transform
		local oldparent = trans.parent
		su.handle_transform(events, trans)

		local newparent = trans.parent
		if newparent ~= oldparent then
			local parentparent = world[newparent].hierarchy_transform.parent
			tree[newparent] = parentparent
			changed_parent = true
		end
		
		tree[eid] = newparent
	end

	update_scene_tree(tree, self.hierarchy_transform_result)
	if changed_parent then
		notify_render_child_changed(tree)
	end
end