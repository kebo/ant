local ecs   = ...
local world = ecs.world
local w     = world.w
local iom = ecs.import.interface "ant.objcontroller|iobj_motion"

local mt_sys = ecs.system "mesh_terrain_system"

local function instance(pid, mp, centerpos)
    local p = ecs.create_instance(mp, pid)
    p.on_ready = function (ee)
        if centerpos then
            iom.set_position(world:entity(ee.root), centerpos)
        end
    end
    world:create_object(p)
    return p
end

function mt_sys:entity_init()
    for e in w:select "INIT shape_terrain:in id:in" do
        local st = e.shape_terrain
        local ms = st.mesh_shape
        local tw, th = st.width, st.height
        local mw, mh = ms.w, ms.h
        local ww, hh = tw // mw, th //mh
        local unit = st.unit
        assert(ww * hh == #ms, "Invalid mesh indices")

        local terrainid = e.id
        local meshprefabs = ms.meshes
        local instances = {}
        for ih=1, hh do
            local ridx = (ih-1) * ww
            for iw=1, ww do
                local idx = iw+ridx
                local midx = ms[idx]
                local centerpos = {mw * (iw-1+0.5) * unit, 0.0, mh * (ih-1+0.5) * unit}
                instances[idx] = instance(terrainid, assert(meshprefabs[midx]), centerpos)
            end
        end
        ms.instances = instances
    end
end

local ims = ecs.interface "imeshshape"
function ims.set(teid, midx, iw, ih)
    local te = world:entity(teid)
    local st = te.shape_terrain
    local ms = st.mesh_shape
    local instances = ms.instances
    local idx = iw+(ih-1)*ms.w
    local inst = instances[idx]
    if inst then
        for e in ipairs(inst.tag['*']) do
            world:remove(e)
        end
    end

    instances[idx] = instance(teid, ms.meshes[midx])
end

function ims.set_resource(te, idx, prefabres)
    local st = te.shape_terrain
    st.mesh_shape.meshes[idx] = prefabres
end