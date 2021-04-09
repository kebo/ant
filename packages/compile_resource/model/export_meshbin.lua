local gltfutil  = require "model.glTF.util"
local renderpkg = import_package "ant.render"
local declmgr   = renderpkg.declmgr
local math3d    = require "math3d"
local utility   = require "model.utility"

local function sort_pairs(t)
    local s = {}
    for k in pairs(t) do
        s[#s+1] = k
    end

    table.sort(s)

    local n = 1
    return function ()
        local k = s[n]
        if k == nil then
            return
        end
        n = n + 1
        return k, t[k]
    end
end

local function get_desc(name, accessor)
	local shortname, channel = declmgr.parse_attri_name(name)
	local comptype_name = gltfutil.comptype_name_mapper[accessor.componentType]

	return 	shortname .. 
			tostring(gltfutil.type_count_mapper[accessor.type]) .. 
			tostring(channel) .. 
			(accessor.normalized and "n" or "N") .. 
			"I" .. 
			gltfutil.decl_comptype_mapper[comptype_name]
end

local function fetch_ib_buffer(gltfscene, bindata, index_accessor)
	local bv = gltfscene.bufferViews[index_accessor.bufferView + 1]
	local elemsize = gltfutil.accessor_elemsize(index_accessor)

	local accoffset = index_accessor.byteOffset or 0
	local bvoffset = bv.byteOffset or 0
	local offset = accoffset + bvoffset + 1
	assert((bv.byteStride or elemsize) == elemsize)
	local value
	if elemsize == 1 then
		local buffers = {}
		local begidx = offset
		for i=1, index_accessor.count do
			local endidx = begidx+elemsize-1
			local v = bindata:sub(begidx, endidx)
			begidx = endidx + 1
			local idx = string.unpack("<B", v)
			buffers[#buffers+1] = string.pack("H", idx)
		end
		value = table.concat(buffers, "")
	elseif elemsize == 2 or elemsize == 4 then
		local numbytes = elemsize * index_accessor.count
		value = bindata:sub(offset, offset + numbytes -1)
	else
		error(("invalid index buffer elemenet size: %d"):format(elemsize))
	end
	return {
		memory = {value, 1, #value},
		flag = (elemsize == 4 and 'd' or ''),
		start 	= 0,
		num 	= index_accessor.count,
	}
end

local function create_prim_bounding(meshscene, prim)	
	local posacc = meshscene.accessors[assert(prim.attributes.POSITION)+1]
	if posacc.min then
		assert(#posacc.min == 3)
		assert(#posacc.max == 3)
		local bounding = {
			aabb = {posacc.min, posacc.max}
		}
		prim.bounding = bounding
		return bounding
	end
end

local function fetch_skininfo(gltfscene, skin, bindata)
	local ibm_idx 	= skin.inverseBindMatrices
	local ibm 		= gltfscene.accessors[ibm_idx+1]
	local ibm_bv 	= gltfscene.bufferViews[ibm.bufferView+1]

	local start_offset = ibm_bv.byteOffset + 1
	local end_offset = start_offset + ibm_bv.byteLength

	return {
		inverse_bind_matrices = {
			num		= ibm.count,
			value 	= bindata:sub(start_offset, end_offset-1),
		},
		joints 	= skin.joints,
	}
end

local function get_obj_name(obj, idx, defname)
	if obj.name then
		return obj.name
	end

	return defname .. idx
end

local default_layouts = {
	POSITION	= 1,
	NORMAL 		= 1,
	TANGENT 	= 1,
	BITANGENT 	= 1,

	JOINTS_0 	= 2,
	WEIGHTS_0 	= 2,

	COLOR_0		= 3,
	COLOR_1		= 3,
	COLOR_2		= 3,
	COLOR_3		= 3,
	TEXCOORD_0 	= 3,
	TEXCOORD_1 	= 3,
	TEXCOORD_2 	= 3,
	TEXCOORD_3 	= 3,
	TEXCOORD_4 	= 3,
	TEXCOORD_5 	= 3,
	TEXCOORD_6 	= 3,
	TEXCOORD_7 	= 3,
}

local function fetch_vb_buffers(gltfscene, gltfbin, prim)
	local attributes = prim.attributes
	local attribclasses = {}
	for attribname, accidx in pairs(attributes) do
		local which_layout = default_layouts[attribname]
		if which_layout == nil then
			error(("invalid attrib name:%s"):format(attribname))
		end
		local attriclass = attribclasses[which_layout]
		if attriclass == nil then
			attriclass = {}
			attribclasses[which_layout] = attriclass
		end

		attriclass[#attriclass+1] = {attribname, accidx}
	end

	local accessors = gltfscene.accessors
	local bufferviews = gltfscene.bufferViews
	local attribuffers = {}
	local numv = accessors[attributes.POSITION+1].count
	local bufferidx = 1
	for _, attribclass in sort_pairs(attribclasses) do
		local declname = {}
		local cacheclass = {}
		for _, info in ipairs(attribclass) do
			local attribname, accidx = info[1], info[2]
			local acc = accessors[accidx+1]
			local bv = bufferviews[acc.bufferView+1]

			local acc_offset = acc.byteOffset or 0
			local bv_offset = bv.byteOffset or 0

			local elemsize = gltfutil.accessor_elemsize(acc)
			cacheclass[#cacheclass+1] = {acc_offset, bv_offset, elemsize, bv.byteStride or elemsize}
			declname[#declname+1] = get_desc(attribname, acc)
		end

		local buffer = {}
		for ii=0, numv-1 do
			for jj=1, #cacheclass do
				local c = cacheclass[jj]
				local acc_offset, bv_offset, elemsize, stride = c[1], c[2], c[3], c[4]
				local elemoffset = bv_offset + ii * stride + acc_offset + 1
				buffer[#buffer+1] = gltfbin:sub(elemoffset, elemoffset + elemsize - 1)

				-- local buf = gltfbin:sub(elemoffset, elemoffset + elemsize - 1)
				-- local size = elemsize / 4
				-- local formats = {[1] = "f", [2] = "ff", [3] = "fff", [4] = "ffff"}

				-- local t = table.pack(string.unpack(formats[size], buf))
				-- print(table.concat(t, " "))
				-- buffer[#buffer+1] = buf
			end
		end

		local bindata = table.concat(buffer, "")
		attribuffers[bufferidx] = {
			declname = table.concat(declname, "|"),
			memory = {bindata, 1, #bindata},
		}
		bufferidx = bufferidx+1
	end

	attribuffers.start 	= 0
	attribuffers.num 	= gltfutil.num_vertices(prim, gltfscene)
	return attribuffers
end

local function find_skin_roots(scene, skin)
	local joints = skin.joints
	if joints == nil then
		error(string.format("invalid mesh, skin node must have joints"))
	end

	if skin.skeleton then
		return skin.skeleton;
	end

	local parents = {}
	for _, nodeidx in ipairs(joints) do
		local c = scene.nodes[nodeidx+1].children
		if c then
			for _,  cnodeidx in ipairs(c) do
				parents[cnodeidx] = nodeidx
			end
		end
	end

	local roots = {}
	for _, jidx in ipairs(joints) do
		if parents[jidx] == nil then
			roots[#roots+1] = jidx
		end
	end

	return roots;
end

local function redirect_skin_joints(gltfscene, skin)
	local joints = skin.joints
	local skeleton_roots = find_skin_roots(gltfscene, skin)

	local mapper = {}
	local node_index = 0
	-- follow with ozz-animation:SkeleteBuilder, IterateJointsDF
	local function iterate_hierarchy_DF(nodes)
		for _, nidx in ipairs(nodes) do
			mapper[nidx] = node_index
			node_index = node_index + 1
			local node = gltfscene.nodes[nidx+1]
			local c = node.children
			if c then
				iterate_hierarchy_DF(c)
			end
		end
	end
	iterate_hierarchy_DF(skeleton_roots)

	for i=1, #joints do
		local joint_nodeidx = joints[i]
		joints[i] = assert(mapper[joint_nodeidx])
	end

	print ""
end

local function export_skinbin(gltfscene, bindata, exports)
	exports.skin = {}
	local skins = gltfscene.skins
	if skins == nil then
		return
	end
	for skinidx, skin in ipairs(gltfscene.skins) do
		redirect_skin_joints(gltfscene, skin)
		local skinname = get_obj_name(skin, skinidx, "skin")
		local resname = "./meshes/"..skinname .. ".skinbin"
		utility.save_bin_file(resname, fetch_skininfo(gltfscene, skin, bindata))
		exports.skin[skinidx] = resname
	end
end

local function export_meshbin(gltfscene, bindata, exports)
	exports.mesh = {}
	local meshes = gltfscene.meshes
	if meshes == nil then
		return
	end
	for meshidx, mesh in ipairs(meshes) do
		local meshname = get_obj_name(mesh, meshidx, "mesh")
		local meshaabb = math3d.aabb()
		exports.mesh[meshidx] = {}
		for primidx, prim in ipairs(mesh.primitives) do
			local group = {}
			group.vb = fetch_vb_buffers(gltfscene, bindata, prim)
			local indices_accidx = prim.indices
			if indices_accidx then
				local idxacc = gltfscene.accessors[indices_accidx+1]
				group.ib = fetch_ib_buffer(gltfscene, bindata, idxacc)
			end
			local bb = create_prim_bounding(gltfscene, prim)
			if bb then
				group.bounding = bb
				meshaabb = math3d.aabb_merge(meshaabb, math3d.aabb(bb.aabb[1], bb.aabb[2]))
			end
			local primname = "P" .. primidx
			local resname = "./meshes/"..meshname .. "_" .. primname .. ".meshbin"
			utility.save_bin_file(resname, group)
			exports.mesh[meshidx][primidx] = resname
		end
	end
end

return function (_, glbdata, exports)
	export_meshbin(glbdata.info, glbdata.bin, exports)
	export_skinbin(glbdata.info, glbdata.bin, exports)
	return exports
end
