-- luacheck: globals import
-- luacheck: globals log
local require = import and import(...) or require
local log = log and log(...) or print

local rawtable = require "rawtable"
local path = require "filesystem.path"
local mesh_loader = require "modelloader.loader"
local assetmgr = require "asset"

return function (filename)
	local fn = assetmgr.find_valid_asset_path(filename)
	if fn == nil then
		error(string.format("invalid filename in ext_mesh", filename))
	end
	
    local mesh = rawtable(fn)
    
    local mesh_path = mesh.mesh_path
    assert(mesh_path ~= nil)
    if #mesh_path ~= 0 then
		
		local function check_path(fp)
			if path.ext(fp) == nil then					
				for _, ext in ipairs {".fbx", ".bin", ".ozz"} do
					local pp = assetmgr.find_valid_asset_path(fp .. ext)
					if pp then
						return pp
					end
				end
			end

			return assetmgr.find_valid_asset_path(fp)
		end

		mesh_path = check_path(mesh_path)
		if mesh_path then
			mesh.handle = mesh_loader.load(mesh_path)
        else
            log(string.format("load mesh path %s failed", mesh_path))
        end 
    end
    
    return mesh
end
