local ecs = ...
local world = ecs.world

local point2d = require "math.point2d"
local bgfx = require "bgfx"
local ru = require "render.util"
local mu = require "math.util"
local asset = require "asset"
local cu = require "common.util"

local math_baselib = require "math3d.baselib"

local pickup_fb_viewid = 2
local pickup_blit_viewid = pickup_fb_viewid + 1

-- pickup component
ecs.component "pickup"{}

-- pickup helper
local pickup = {} 
pickup.__index = pickup

local function packeid_as_rgba(eid)
    return {(eid & 0x000000ff) / 0xff,
            ((eid & 0x0000ff00) >> 8) / 0xff,
            ((eid & 0x00ff0000) >> 16) / 0xff,
            ((eid & 0xff000000) >> 24) / 0xff}    -- rgba
end

local function unpackrgba_to_eid(rgba)
    local r =  rgba & 0x000000ff
    local g = (rgba & 0x0000ff00) >> 8
    local b = (rgba & 0x00ff0000) >> 16
    local a = (rgba & 0xff000000) >> 24
    
    return r + g + b + a
end

function pickup:init_material()
	local mname = "pickup.material"
	local normal_material = asset.load(mname) 
	normal_material.name = mname

	local transparent_material = cu.deep_copy(normal_material)
	transparent_material.surface_type.transparency = "transparent"
	transparent_material.name = ""

	local state = transparent_material.state
	state.WRITE_MASK = "RGBA"
	state.DEPTH_TEST = "ALWAYS"

	self.materials = {
		opaticy = normal_material,
		transparent = transparent_material,
	}    
end

local function bind_frame_buffer(e)
    local comp = e.pickup    
    local vid = e.viewid.id
    bgfx.set_view_frame_buffer(vid, assert(comp.pick_fb))
end

function pickup:init(pickup_entity)
    self:init_material()
    local comp = pickup_entity.pickup
    --[@ init hardware resource
    local vr = pickup_entity.view_rect
    local w, h = vr.w, vr.h
    comp.pick_buffer = bgfx.create_texture2d(w, h, false, 1, "RGBA8", "rt-p+p*pucvc")
    comp.pick_dbuffer = bgfx.create_texture2d(w, h, false, 1, "D24S8", "rt-p+p*pucvc")

    comp.pick_fb = bgfx.create_frame_buffer({comp.pick_buffer, comp.pick_dbuffer}, true)
    comp.rb_buffer = bgfx.create_texture2d(w, h, false, 1, "RGBA8", "bwbr-p+p*pucvc")
    --@]

    bind_frame_buffer(pickup_entity)
end

function pickup:render_to_pickup_buffer(pickup_entity, select_filter)
	local ms = self.ms
	
	local results = {
		{result=select_filter.result, mode = '', material = self.materials.opaticy},
		{result=select_filter.transparent_result, mode = 'D', material = self.materials.transparent},
	}

	local vid = pickup_entity.viewid.id

	for _, r in ipairs(results) do
		bgfx.set_view_mode(vid, r.mode)
		for _, prim in ipairs(r.result) do
			local pick_prim = {}
			for k, v in pairs(prim) do
				pick_prim[k] = v
			end

			pick_prim.material = r.material
			pick_prim.properties = {
				u_id = {type="color", value=packeid_as_rgba(assert(prim.eid))}
			}
			
			local srt = pick_prim.srt
			local mat = ms({type="srt", s=srt.s, r=srt.r, t=srt.t}, "m")
			ru.draw_primitive(vid, pick_prim, mat)
		end
	end
end

function pickup:readback_render_data(pickup_entity)    
    local comp = pickup_entity.pickup    
    bgfx.blit(pickup_blit_viewid, assert(comp.rb_buffer), 0, 0, assert(comp.pick_buffer))
    assert(self.reading_frame == nil)
    return bgfx.read_texture(comp.rb_buffer, comp.blitdata)
end

function pickup:which_entity_hitted(pickup_entity)
    local comp = pickup_entity.pickup
    local vr = pickup_entity.view_rect
	local w, h = vr.w, vr.h
	
	local cw, ch = 2, 2	
	local startidx = ((h - ch) * w + (w - cw)) * 0.5


	local found_eid = nil
	for ix = 1, cw do		
		for iy = 1, ch do 
			local cidx = startidx + (ix - 1) + (iy - 1) * w
			local rgba = comp.blitdata[cidx]
			if rgba ~= 0 then
				found_eid = unpackrgba_to_eid(rgba)
				break
			end
		end
	end

    return found_eid
end

function pickup:pick(p_eid, current_frame_num, select_filter)
    local pickup_entity = world[p_eid]
    if self.reading_frame == nil then        
		bind_frame_buffer(pickup_entity)
		world:change_component(-1, "create_selection_filter")
		world:notify()
        self:render_to_pickup_buffer(pickup_entity, select_filter)
        self.reading_frame = self:readback_render_data(pickup_entity)        
    end

    if self.reading_frame == current_frame_num then
        local comp = pickup_entity.pickup
        local eid = self:which_entity_hitted(pickup_entity)
        if eid then
            local name = assert(world[eid]).name.n
            print("pick entity id : ", eid, ", name : ", name)
        else
            print("not found any eid")
        end

        comp.last_eid_hit = eid
        world:change_component(p_eid, "pickup")
        world.notify()
        self.reading_frame = nil
    end
    self.is_picking = self.reading_frame ~= nil
end

local function update_viewinfo(ms, e, clickpt)    
	local maincamera = world:first_entity("main_camera")  
	local mc_vr = maincamera.view_rect
	local w, h = mc_vr.w, mc_vr.h
	
	local pos = ms(maincamera.position.v, "T")
	local rot = ms(maincamera.rotation.v, "T")
	local pt3d = math_baselib.screenpt_to_3d(
		{
			clickpt.x, clickpt.y, 0,
			clickpt.x, clickpt.y, 1
		}, maincamera.frustum, pos, rot, {w=w, h=h})

	local eye, at = {pt3d[1], pt3d[2], pt3d[3]}, {pt3d[4], pt3d[5], pt3d[6]}
	local dir = ms(at, eye, "-nT")
	
	ms(assert(e.position).v, eye, "=")
	ms(assert(e.rotation).v, dir, "D=")

end

-- system
local pickup_sys = ecs.system "pickup_system"

pickup_sys.singleton "math_stack"
pickup_sys.singleton "frame_stat"
pickup_sys.singleton "select_filter"
pickup_sys.singleton "message_component"

pickup_sys.dependby "end_frame"

local function add_pick_entity(ms)
	local eid = world:new_entity("pickup", "viewid", 
	"view_rect", "clear_component", 
	"position", "rotation", 
	"frustum", 
	"name")        
	local entity = assert(world[eid])
	entity.viewid.id = pickup_fb_viewid
	entity.name.n = "pickup"

	local cc = entity.clear_component
	cc.color = 0

	local vr = entity.view_rect
	vr.w = 8
	vr.h = 8

	local comp = entity.pickup
	comp.blitdata = bgfx.memory_texture(vr.w*vr.h * 4)

	local frustum = entity.frustum
	mu.frustum_from_fov(frustum, 0.1, 100, 1, vr.w / vr.h)
	
	local pos = entity.position.v
	local rot = entity.rotation.v
	ms(pos, {0, 0, 0, 1}, "=")
	ms(rot, {0, 0, 0, 0}, "=")

	return entity
end

function pickup_sys:init()
    local entity = add_pick_entity(self.math_stack)

	local ms = self.math_stack
    pickup.ms = ms
	pickup:init(entity)

	self.message_component.msg_observers:add({
		button = function (_, b, p, x, y)
			if b == "LEFT" and p then
				local clickpt = point2d(x, y)

				local pu_entity = world:first_entity("pickup")
				update_viewinfo(ms, pu_entity, clickpt)

				pickup.is_picking = true
			end
		end
	})
end

function pickup_sys:update()
    if pickup.is_picking then
        local eid = assert(world:first_entity_id("pickup"))    
        pickup:pick(eid, self.frame_stat.frame_num, self.select_filter)
    end
end

