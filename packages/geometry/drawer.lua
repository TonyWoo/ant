local draw = {}; draw.__index = {}

local math3d = import_package "ant.math"
local ms = math3d.stack

local geo = require "geometry"


local function gen_color_vertex(pt, color, transform)
	assert(#pt == 3)
	local npt = ms(transform, {pt[1], pt[2], pt[3], 1}, "*T")
	npt[4] = color
	return npt
end

local function gen_color_vertices(pts, color, transform, vb)
	local vnum = #pts
	if transform then
		for i=1, vnum do
			table.insert(vb, gen_color_vertex(pts[i], color, transform))
		end
	else
		for i=1, vnum do
			local pt = pts[i]
			table.insert(vb, {pt[1], pt[2], pt[3], color})
		end
	end
end

local function add_primitive(primitives, voffset, vnum, ioffset, inum)
	table.insert(primitives, {start_vertex=voffset, num_vertices=vnum, start_index=ioffset, num_indices=inum})
end

local function append_array(from, to)
	table.move(from, 1, #from, #to+1, to)
end

local function offset_index_buffer(ib, istart, iend, offset)	
	for i=istart, iend do
		ib[i] = offset + ib[i]
	end	
end

local function create_bone(ratio)
	local vb, ib = geo.cone(4, ratio, 0.25, true, true)
	local vbdown, ibdown = geo.cone(4, -(1-ratio), 0.25, true, true)
	offset_index_buffer(ibdown, 1, #ibdown, #vb)
	
	append_array(vbdown, vb)
	append_array(ibdown, ib)
	return vb, ib
end

-- local function print_bone(bone)
-- 	local begidx, endidx = bone[1], bone[2]
-- 	local jbeg, jend = joints[begidx], joints[endidx]
-- 	print(string.format("begin joint:%d %s", begidx, jbeg.name))
-- 	print(string.format("end joint:%d %s", endidx, jend.name))
-- 	print(string.format("begin joint:\n\ts:(%2f, %2f, %2f)\n\tr:(%2f, %2f, %2f, %2f)\n\tt(%2f, %2f, %2f)", 
-- 		jbeg.s[1], jbeg.s[2], jbeg.s[3],
-- 		jbeg.r[1], jbeg.r[2], jbeg.r[3], jbeg.r[4],
-- 		jbeg.t[1], jbeg.t[2], jbeg.t[3]))

-- 	print(string.format("end joint:\n\ts:(%2f, %2f, %2f)\n\tr:(%2f, %2f, %2f, %2f)\n\tt(%2f, %2f, %2f)", 
-- 		jend.s[1], jend.s[2], jend.s[3],
-- 		jend.r[1], jend.r[2], jend.r[3], jend.r[4],
-- 		jend.t[1], jend.t[2], jend.t[3]))
-- end

local function generate_bones(ske)	
	local bones = {}
	for i=1, #ske do
		if not ske:isroot(i) then
			table.insert(bones, {ske:parent(i), i})
		end
	end
	return bones
end

local function generate_joints_worldpos(ske)
	local function load_world_trans(idx, worldpos)
		local srt = worldpos[idx]
		if srt == nil then
			local function build_hierarchy_indices(idx)
				local indices = {}
				local curidx = idx
				while not ske:isroot(curidx) do
					table.insert(indices, curidx)
					curidx = ske:parent(curidx)
				end
				assert(ske:isroot(curidx))
				table.insert(indices, curidx)
				return indices				
			end

			local indices = build_hierarchy_indices(idx)

			local function get_matrix(i)
				local ii = indices[i]				
				local fsrt = worldpos[ii]
				if fsrt then
					return fsrt, true
				end
				return ms:matrix(ske:joint_matrix(ii)), false
			end
	
			local num_indices = #indices
			
			srt = get_matrix(num_indices)
			for i=num_indices-1, 1, -1 do
				local csrt, isworld = get_matrix(i)
				if isworld then
					srt = csrt
				else
					srt = ms(srt, csrt, "*P")
				end
			end
		
			worldpos[idx] = srt
		end
		
		return srt
	end

	local worldpos = {}
	for i=1, #ske do
		load_world_trans(i, worldpos)
	end	

	return worldpos
end

function draw.draw_skeleton(ske, ani, color, transform, desc)	
	local bones = generate_bones(ske)

	local joints = ani and ani:joints() or generate_joints_worldpos(ske)
	return draw.draw_bones(bones, joints, color, transform, desc)
end

function draw.draw_bones(bones, joints, color, transform, desc)
	local dvb = desc.vb
	local dib = desc.ib
	local updown_ratio = 0.3

	local bonevb, boneib = create_bone(updown_ratio)
	local localtrans = ms({type="srt", r={-90, 0, 0}, t={0, 0, updown_ratio}}, "P")

	local poitions = {}
	local origin = ms({0 ,0, 0, 1}, "P")
	for _, j in ipairs(joints) do
		local p = ms(ms:matrix(j), origin, "*P")	-- extract poistion
		table.insert(poitions, p)
	end

	for _, b in ipairs(bones) do
		local beg_pos, end_pos = poitions[b[1]], poitions[b[2]]
		local vec = ms(end_pos, beg_pos, "-P")
		local len = math.sqrt(ms(vec, vec, ".T")[1])
		local rotation = ms(vec, "neP")
		
		local finaltrans = ms({type="srt", r=rotation, s={len, len, len}, t=beg_pos}, localtrans, "*P")
		if transform then
			finaltrans = ms(transform, finaltrans, "*P")
		end

		local vstart = #dvb
		append_array(bonevb, dvb)
		local istart = #dib+1
		append_array(boneib, dib)
		if vstart ~= 0 then
			offset_index_buffer(dib, istart, #dib, vstart)			
		end
		
		for i=vstart+1, #dvb do
			local v = dvb[i]
			local nv = ms(finaltrans, {v[1], v[2], v[3], 1}, "*T")
			nv[4] = color
			dvb[i] = nv
		end	
	end
end

function draw.draw_line(pts, color, transform, desc)
	local vb = assert(desc.vb)

	local offset = #vb
	local num = #pts
	gen_color_vertices(pts, color, transform, vb)
	add_primitive(desc.primitives, offset, num)
end

local function draw_primitve(color, transform, desc, buffer_generator)
	--local vb, ib = geo.sphere(1, sphere.radius, true, true)
	local vb, ib = buffer_generator()

	local desc_vb = assert(desc.vb)
	local offset = #desc_vb
	gen_color_vertices(vb, color, transform, desc_vb)
	local desc_ib = assert(desc.ib)
	local ioffset = #desc_ib
	append_array(ib, desc_ib)
	add_primitive(desc.primitives, offset, #vb, ioffset, #ib)
end

function draw.draw_cone(cone, color, transform, desc)
	draw_primitve(color, transform, desc, 
	function()
		return geo.cone(cone.slices, cone.height, cone.radius, true, true)
	end)
end

function draw.draw_sphere(sphere, color, transform, desc)
	draw_primitve(color, transform, desc, function()
		return geo.sphere(sphere.tessellation, sphere.radius, true, true)
	end)
end

return draw