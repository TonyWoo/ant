-- luacheck: globals log
local log = log and log.info(...) or print

local bgfx 		= require "bgfx"
local viewidmgr = require "viewid_mgr"
local gltfutil = import_package "ant.glTF".util
local default_comp = require "components.default"
local computil = require "components.util"
local fs = require "filesystem"

local util = {}
util.__index = util

local property_types = {
    color = "v4",
    v4 = "v4",
    m4 = "m4",
    texture = "s",
}

local function update_properties(shader, properties, render_properties)
	local su = shader.uniforms	
	for name, u in pairs(su) do
		local function find_property(name, properties)
			local uniforms = properties.uniforms
			if uniforms then
				local p = uniforms[name]
				if p then
					return p
				end
			end
			local textures = properties.textures
			return textures and textures[name] or nil
		end

		local p = find_property(name, properties)
		if p == nil then
			for _, v in pairs(render_properties) do
				p = find_property(name, v)
				if p then
					break
				end
			end
		end

		if p then
			assert(property_types[p.type] == u.type)
			if p.type == "texture" then
				bgfx.set_texture(assert(p.stage), u.handle, p.handle)
			else				
				bgfx.set_uniform(u.handle, p.value)
			end
		else
			--log(string.format("uniform : %s, not privided, but shader program needed", name))
		end
	end
end

-- function util.draw_primitive_OLDCOLD(vid, primgroup, mat, render_properties)
--     bgfx.set_transform(mat)

-- 	-- 保留兼容，最好按实验结果重构
-- 	local material = primgroup.material[1]
-- 	local properties =  primgroup.properties[1]
	
-- 	local mg = assert(primgroup.mgroup)
-- 	local ib, vb = mg.ib, mg.vb

-- 	local prims = mg.primitives
-- 	if prims == nil or next(prims) == nil then
-- 		-- 地形走的是这个分支? 
-- 		bgfx.set_state(bgfx.make_state(material.state)) -- always convert to state str
-- 		update_properties(material.shader, properties, render_properties)
-- 		local prog = material.shader.prog

-- 		if ib then
-- 			bgfx.set_index_buffer(ib.handle)
-- 		end
-- 		for idx, v in ipairs(vb.handles) do
-- 			bgfx.set_vertex_buffer(idx - 1, v)
-- 		end
		
-- 		bgfx.submit(vid, prog, 0, false)
-- 	else
-- 		local numprim = #prims

-- 		for idx, v in ipairs(vb.handles) do
-- 			bgfx.set_vertex_buffer(idx - 1, v)
-- 		end

-- 		for i=1, numprim do
-- 			-- 这部分后续需要优化，提供机制判断一个mesh 是否具备多个材质，分开处理
-- 			local material = primgroup.material[i]  or primgroup.material[1]
-- 			local properties = primgroup.properties[i] or primgroup.properties[1]
-- 			local prog = material.shader.prog

-- 			bgfx.set_state(bgfx.make_state(material.state)) -- always convert to state str
-- 			update_properties(material.shader, properties, render_properties)

-- 			local prim = prims[i]
-- 			if ib and prim.start_index and prim.num_indices then
-- 				bgfx.set_index_buffer(ib.handle, prim.start_index, prim.num_indices)
-- 			end
-- 			bgfx.submit(vid, prog, 0, i~=numprim)
-- 		end

-- 		-- for i=1, numprim do
-- 		-- 	local prim = prims[i]

-- 		-- 	if ib and prim.start_index and prim.num_indices then
-- 		-- 		bgfx.set_index_buffer(ib.handle, prim.start_index, prim.num_indices)
-- 		-- 	end
-- 		-- 	for idx, v in ipairs(vb.handles) do
-- 		-- 		bgfx.set_vertex_buffer(idx - 1, v, prim.start_vertex, prim.num_vertices)
-- 		-- 		--bgfx.set_vertex_buffer(idx - 1, v)
-- 		-- 	end

-- 		-- 	bgfx.submit(vid, prog, 0, i~=numprim)
-- 		-- end

-- 	end
-- end


function util.draw_primitive(vid, primgroup, mat, render_properties)
    bgfx.set_transform(mat)

	local material = primgroup.material
	bgfx.set_state(bgfx.make_state(material.state)) -- always convert to state str
	update_properties(material.shader, primgroup.properties, render_properties)

	local prog = material.shader.prog

	local mg = assert(primgroup.mgroup)
	local ib, vb = mg.ib, mg.vb	

	if primgroup.using_glb then
		if ib then
			bgfx.set_index_buffer(ib.handle, ib.start, ib.num)
		end

		local start_v, num_v = vb.start, vb.num
		for idx, handle in pairs(vb.handles) do
			bgfx.set_vertex_buffer(idx, handle, start_v, num_v)
		end
		bgfx.submit(vid, prog, 0, false)
	else
		local prims = mg.primitives
		if prims == nil or next(prims) == nil then
			if ib then
				bgfx.set_index_buffer(ib.handle)
			end
			for idx, v in ipairs(vb.handles) do
				bgfx.set_vertex_buffer(idx - 1, v)
			end
			
			bgfx.submit(vid, prog, 0, false)
		else
			local numprim = #prims

			for idx, v in ipairs(vb.handles) do
				bgfx.set_vertex_buffer(idx - 1, v)
			end
			for i=1, numprim do
				local prim = prims[i]
				if ib and prim.start_index and prim.num_indices then
					bgfx.set_index_buffer(ib.handle, prim.start_index, prim.num_indices)
				end
				bgfx.submit(vid, prog, 0, i~=numprim)
			end
		end
	end
end

local function add_result(eid, group, materialinfo, properties, worldmat, result)
	local idx = result.cacheidx
	local r = result[idx]
	if r == nil then
		r = {}
		result[idx] = r
	end

	r.eid 		= eid
	r.mgroup 	= group

	r.material 	= materialinfo
	r.properties = properties
	r.worldmat 	= worldmat

	result.cacheidx = idx + 1

	return r
end


function util.insert_primitive_old(eid, meshhandle, materials, worldmat, filter,group_id)	
	local mgroups = meshhandle.groups
	local results = filter.result	

	if group_id ~= nil then 
		local g = mgroups[ group_id ]
		local mc = materials[ group_id ] or materials[1] 

		-- this two variable trans to table parameters
		local mat_info = {} --mc.materialinfo  				-- maybe need materials[] for primitives[],futhur extend
		local mat_properties = {}  --mc.properties 

		-- 一个primitive 带 n 个materials ，需要把这些materials 传到render 
		-- 这部分需要重写，合并到加载时候，不需要每次动态装配
		-- 原mat_info,mat_properties 存在一个引用关系，需要从加载时，就为每个mesh 提供 materials，properties
		-- 这里需要从整个fbx materials 去找出对应material 装备，推前到加载时完成，需要新需求修改统一
		-- tested install mat&properties for submesh'submesh
		local num_primitives = #g.primitives 
		if num_primitives >= 1 and mat_info.ajust ~= 1 then 
			local base = g.primitives[1].material_idx
			for i=1,num_primitives do 
				local m_idx = g.primitives[i].material_idx
				m_idx = m_idx - base + 1
				local m_content = materials[m_idx] or materials[1]   -- some prim 
				table.insert(mat_info,m_content.materialinfo)
			end 
			mat_info.ajust = 1
		end 

		if num_primitives >= 1 and mat_properties.ajust ~= 1 then  
			local base = g.primitives[1].material_idx
			for i=1,num_primitives do 
				local m_idx = g.primitives[i].material_idx
				m_idx = m_idx - base + 1
				local m_content = materials[m_idx] or materials[1]   -- some prim 
				table.insert(mat_properties,m_content.properties)
			end 
			mat_properties.ajust = 1
		end 
        -- tested 

		if mat_info[1].surface_type.transparency == "translucent" then
			add_result(eid, g, mat_info, mat_properties, worldmat, results.translucent)
		else
			add_result(eid, g, mat_info, mat_properties, worldmat, results.opaque)
		end
	else
		--   compatible with the one mode
		for i=1, #mgroups do
			local g = mgroups[i]
			local mc = materials[i] or materials[1]


			local mi = { mc.materialinfo }
			local properties = { mc.properties }
			
			if mi[1].surface_type.transparency == "translucent" then
				add_result(eid, g, mi, properties, worldmat, results.translucent)
			else
				add_result(eid, g, mi, properties, worldmat, results.opaque)
			end
		end
	end 
end

function util.insert_primitive(eid, prim, meshscene, material, worldmat, filter)
	local result = filter.result
	local function vb_info(prim, meshscene)
		local bvidx_mapper = {}
		local vbhandles = {}
		for _, accidx in pairs(prim.attributes) do
			local acc = meshscene.accessors[accidx+1]
			local bvidx = acc.bufferView
			if not bvidx_mapper[bvidx] then
				vbhandles[#vbhandles+1] = meshscene.bufferViews[bvidx+1].handle
				bvidx_mapper[bvidx] = true
			end
		end

		return {
			handles = vbhandles,
			start = gltfutil.start_vertex(prim, meshscene),
			num = gltfutil.num_vertices(prim, meshscene),
		}
	end

	local function ib_info(prim, meshscene)
		local indices = prim.indices
		if indices then
			local idxacc = meshscene.accessors[indices+1]
			local idxbv = meshscene.bufferViews[idxacc.bufferView+1]
			return {
				handle = idxbv.handle,
				start = gltfutil.start_index(prim, meshscene),
				num = gltfutil.num_indices(prim, meshscene),
			}
		end
	end

	local group = {
		vb = vb_info(prim, meshscene),
		ib = ib_info(prim, meshscene),
	}

	local mi = material.materialinfo
	local resulttarget = mi.surface_type.transparency == "translucent" and
		result.translucent or result.opaque

	local r = add_result(eid, group, mi, material.properties, worldmat, resulttarget)
	r.using_glb = true
end

function util.create_render_queue_entity(world, view_rect, viewdir, eyepos, view_tag, viewid)	
	return world:create_entity {
		camera = default_comp.camera(eyepos, viewdir, 
				default_comp.frustum(view_rect.w, view_rect.h)),
		viewid = viewid or viewidmgr.get(view_tag),
		render_target = {
			viewport = default_comp.viewport(view_rect),
		},
		primitive_filter = {
			view_tag = view_tag,
			filter_tag = "can_render",
		},
		main_queue = view_tag == "main_view" and true or nil,
		visible = true,
	}	
end

function util.create_main_queue(world, view_rect, viewdir, eyepos)
	local fb_renderbuffer_flag = util.generate_sampler_flag {
		RT="RT_ON",
		MIN="LINEAR",
		MAG="LINEAR",
		U="CLAMP",
		V="CLAMP"
	}

	return world:create_entity {
		camera = default_comp.camera(eyepos, viewdir, 
				default_comp.frustum(view_rect.w, view_rect.h)),
		viewid = viewidmgr.get "main_view",
		render_target = {
			viewport = default_comp.viewport(view_rect),
			frame_buffer = {
				render_buffers = {
					default_comp.render_buffer(view_rect.w, view_rect.h, "RGBA8", fb_renderbuffer_flag),
					default_comp.render_buffer(view_rect.w, view_rect.h, "D24S8", fb_renderbuffer_flag),
				},
			},
		},
		primitive_filter = {
			view_tag = "main_view",
			filter_tag = "can_render",
		},
		main_queue = true,
		visible = true,
	}	
end

function util.default_sampler()
	return {
		U="MIRROR",
		V="MIRROR",
		W="MIRROR",
		MIN="LINEAR",
		MAG="LINEAR",
		MIP="LINEAR",
	}
end

function util.fill_default_sampler(sampler)
	local d = util.default_sampler()
	if sampler == nil then
		return d
	end

	for k, v in pairs(d) do
		if sampler[k] == nil then
			sampler[k] = v
		end
	end

	return sampler
end

local sample_types = {
	U="u", V="v", W="w", 
	MIN="-", MAG="+", MIP="*",

	COMPARE="c",
	BOARD_COLOR="c",

	RT = "r", 
	RT_READWRITE = "r", 
	RT_MSAA="r",

	BLIT = "b",
	BLIT_READBACK = "b", 
	BLIT_COMPUTE = "b",

	SAMPLE = "s",
}

local sample_value = {
	CLAMP="c", BORDER="b", MIRROR="",	--default
	POINT="p", ANISOTROPIC="a", LINEAR="", --default,

	-- compare
	COMPARE_LESS = '<',
	COMPARE_LEQUAL = '[',
	COMPARE_EQUAL = '=',
	COMPARE_GEQUAL = ']',
	COMPARE_GREATER = '>',
	COMPARE_NOTEQUAL = '!',
	COMPARE_NEVER = '-',
	COMPARE_ALWAYS = '+',

	-- RT
	RT_ON='t', 
	RT_READ="", RT_WRITE="w",
	RT_MSAA2="2", RT_MSAA4="4", RT_MSAA8="8", RT_MSAAX="x",

	-- BLIT
	BLIT_AS_DST = 'w', 
	BLIT_READBACK_ON = 'r',
	BLIT_COMPUTEREAD = '',
	BLIT_COMPUTEWRITE = 'c',	

	--SAMPLE
	SAMPLE_STENCIL='s', SAMPLE_DEPTH='d',
}

function util.generate_sampler_flag(sampler)
	if sampler == nil then
		return nil
	end
	local flag = ""

	for k, v in pairs(sampler) do
		if k == "BOARD_COLOR" then
			flag = flag .. sample_types[k] .. v
		else
			local value = sample_value[v]
			if value == nil then
				error("not support data, sample value : %s", v)
			end
	
			if #value ~= 0 then
				local type = sample_types[k]
				if type == nil then
					error("not support data, sample type : %s", k)
				end
				
				flag = flag .. type .. value
			end
		end
	end

	return flag
end

function util.default_surface_type()
	return {
		lighting = "on",			-- "on"/"off"
		transparency = "opaticy",	-- "opaticy"/"transparent"
		shadow	= {
			cast = "on",			-- "on"/"off"
			receive = "on",			-- "on"/"off"
		},
		subsurface = "off",			-- "on"/"off"? maybe has other setting
	}
end

-- function util.create_frame_buffer(world,hwnd,w,h,viewid)
-- 	local fb_handle = bgfx.create_frame_buffer(hwnd, w, h)
-- 	bgfx.set_view_frame_buffer(viewid, assert(fb_handle))
-- 	local frame_buffer = {
-- 		render_buffers = {},
-- 		viewid = viewid,
-- 	}
-- 	local frame_buffer_com = world:create_component("frame_buffer",frame_buffer)
-- 	frame_buffer_com.handle = fb_handle
-- 	fbmgr.bind(viewid,frame_buffer_com)
-- end

--frame_buffer:component
function util.create_general_render_queue(world,view_rect,view_tag,viewid)
	local default_viewdir = { -25, -45, 0, 0 }
	local default_eyepos = { 5, 5, -5, 1 }
	local entity_id = util.create_render_queue_entity(world,view_rect,
					default_viewdir,
					default_eyepos,
					view_tag,
					viewid)
	local frame_buffer = {ref_viewid = viewid}
	-- if not frame_buffer.ref_viewid then
	-- 	local default_render_buffer = {
	-- 			w = viewsize.w,
	-- 			h = viewsize.h,
	-- 			layers = 1,
	-- 			format = "RGBA32",
	-- 			flags = util.generate_sampler_flag {
	-- 				RT="RT_ON",
	-- 				MIN="POINT",
	-- 				MAG="POINT",
	-- 				U="CLAMP",
	-- 				V="CLAMP"
	-- 			}
	-- 		}
	-- 	frame_buffer.render_buffers = frame_buffer.render_buffers or {default_render_buffer}
	-- 	frame_buffer.manager_buffer = true
	-- end
	-- world[entity_id].frame_buffer = frame_buffer
	world:add_component(entity_id,"frame_buffer",frame_buffer)

	return entity_id
end

local blitviewid = viewidmgr.generate "blit"

function util.get_main_view_rendertexture(world)
	local mq = world:first_entity "main_queue"
	return mq.render_target.frame_buffer.render_buffers[1].handle	
end

function util.create_blit_queue(world, viewrect)
	util.create_render_queue_entity(world, viewrect, nil, nil, "blit_view", blitviewid)
	computil.create_quad_entity(world, viewrect,
	fs.path "//ant.resources/depiction/materials/fullscreen.material", nil, "full_quad", "blit_view")
end

function util.create_renderbuffer(desc)
	return bgfx.create_texture2d(desc.w, desc.h, false, desc.layers, desc.format, desc.flags)
end

function util.create_framebuffer(renderbuffers, manager_buffer)
	local handles = {}
	for _, rb in ipairs(renderbuffers) do
		handles[#handles+1] = rb.handle
	end
	assert(#handles > 0)
	return bgfx.create_frame_buffer(handles, manager_buffer or true)
end

function util.modify_view_rect(world,rect)
	for _,eid in world:each("render_target") do
		local e = world[eid]
		world:add_component_child(
			e["render_target"]["viewport"],
			"rect",
			"rect",
			rect)
	end
end

return util