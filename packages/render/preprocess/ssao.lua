local ecs   = ...
local world = ecs.world
local w     = world.w

local mathpkg   = import_package "ant.math"
local mu, mc    = mathpkg.util, mathpkg.constant

local settingpkg = import_package "ant.settings"
local setting, def_setting = settingpkg.setting, settingpkg.default

local viewidmgr = require "viewid_mgr"
local fbmgr     = require "framebuffer_mgr"
local sampler   = require "sampler"

local math3d    = require "math3d"

local util      = ecs.require "postprocess.util"

local icompute  = ecs.import.interface "ant.render|icompute"
local imaterial = ecs.import.interface "ant.asset|imaterial"
local iom       = ecs.import.interface "ant.objcontroller|iobj_motion"

local ao_setting<const> = setting:data().graphic.ao or def_setting.graphic.ao

local ssao_sys  = ecs.system "ssao_system"

local ENABLE_SSAO<const>                = ao_setting.enable

if not ENABLE_SSAO then
    local function DEF_FUNC() end
    ssao_sys.init = DEF_FUNC
    ssao_sys.init_world = DEF_FUNC
    ssao_sys.build_ssao = DEF_FUNC
    ssao_sys.bilateral_filter = DEF_FUNC
    return
end

local ENABLE_BENT_NORMAL<const>         = ao_setting.bent_normal
local SSAO_MATERIAL<const>              = ENABLE_BENT_NORMAL and "/pkg/ant.resources/materials/postprocess/ssao_bentnormal.material" or "/pkg/ant.resources/materials/postprocess/ssao.material"
local BILATERAL_FILTER_MATERIAL<const>  = ENABLE_BENT_NORMAL and "/pkg/ant.resources/materials/postprocess/bilateral_filter_bentnormal.material" or "/pkg/ant.resources/materials/postprocess/bilateral_filter.material"

local SAMPLE_CONFIG<const> = {
    low = {
        sample_count = 3,
        spiral_turns = 1,
        bilateral_filter_raidus = 3,
    },
    medium = {
        sample_count = 5,
        spiral_turns = 2,
        bilateral_filter_raidus = 4,
    },
    high = {
        sample_count = 7,
        spiral_turns = 3,
        bilateral_filter_raidus = 6,
    }
}

local HOWTO_SAMPLE<const> = SAMPLE_CONFIG[ao_setting.quality]

local ssao_configs = setmetatable({
    sample_count = HOWTO_SAMPLE.sample_count,
    spiral_turns = HOWTO_SAMPLE.spiral_turns,

    --TODO: need push to ao_setting
    --screen space cone trace
    ssct                        = {
        enable                  = true,
        light_cone              = 1.0,          -- full cone angle in radian, between 0 and pi/2
        shadow_distance         = 0.3,          -- how far shadows can be cast
        contact_distance_max    = 1.0,          -- max distance for contact
        --TODO: need fix cone tracing bug
        intensity               = 0,
        --intensity               = 0.8,          -- intensity
        lightdir                = math3d.ref(math3d.vector(0, 1, 0)),  --light direction
        depth_bias              = 0.01,         -- depth bias in world units (mitigate self shadowing)
        depth_slope_bias        = 0.01,         -- depth slope bias (mitigate self shadowing)
        sample_count            = 4,            -- tracing sample count, between 1 and 255
        ray_count               = 1,            -- # of rays to trace, between 1 and 255
    }
}, {__index=ao_setting})

do
    ssao_configs.inv_radius_squared             = 1.0/(ssao_configs.radius * ssao_configs.radius)
    ssao_configs.min_horizon_angle_sine_squared = math.sin(ssao_configs.min_horizon_angle) ^ 2.0

    local peak = 0.1 * ssao_configs.radius
    ssao_configs.peak2 = peak * peak

    ssao_configs.visible_power = ssao_configs.power * 2.0

    local TAU<const> = math.pi * 2.0
    ssao_configs.ssao_intentsity = ssao_configs.intensity * (TAU * peak)
    ssao_configs.intensity_pre_sample = ssao_configs.ssao_intentsity / ssao_configs.sample_count

    ssao_configs.inv_sample_count = 1.0 / (ssao_configs.sample_count - 0.5)

    local inc = ssao_configs.inv_sample_count * ssao_configs.spiral_turns * TAU
    ssao_configs.sin_inc, ssao_configs.cos_inc = math.sin(inc), math.cos(inc)

    --ssct
    local ssct = ssao_configs.ssct
    ssct.tan_cone_angle            = math.tan(ssao_configs.ssct.light_cone*0.5)
    ssct.inv_contact_distance_max  = 1.0 / ssct.contact_distance_max
end

function ssao_sys:init()
    icompute.create_compute_entity("ssao_dispatcher", SSAO_MATERIAL, {0, 0, 1})
    icompute.create_compute_entity("bilateral_filter_dispatcher", BILATERAL_FILTER_MATERIAL, {0, 0, 1})
end

local ssao_viewid<const> = viewidmgr.get "ssao"
local bilateral_filter_viewid<const>, bilateral_filter_count<const> = viewidmgr.get_range "bilateral_filter"
assert(bilateral_filter_count == 2, "need 2 pass blur: horizontal and vertical")
local Hbilateral_filter_viewid<const>, Vbilateral_filter_viewid<const> = bilateral_filter_viewid, bilateral_filter_viewid+1

local function create_framebuffer(ww, hh)
    local rb_flags = sampler{
        MIN="LINEAR",
        MAG="LINEAR",
        U="CLAMP",
        V="CLAMP",
        RT="RT_ON",
        BLIT="BLIT_COMPUTEWRITE",
    }

    if ENABLE_BENT_NORMAL then
        local rbidx = fbmgr.create_rb{w=ww, h=hh, layers=2, format="RGBA8", flags=rb_flags}
        return fbmgr.create(
            {
                rbidx   = rbidx,
                access  = "w",
                mip     = 0,
                layer   = 0,
                numLayers=2,
                resolve = "",
            },
            {
                rbidx   = rbidx,
                access  = "w",
                mip     = 0,
                layer   = 1,
                numLayers=2,
                resolve = "",
            }
        )
    end

    return fbmgr.create{
        rbidx = fbmgr.create_rb{w=ww, h=hh, layers=1, format="RGBA8", flags=rb_flags}
    }
end

function ssao_sys:init_world()
    local vr = mu.calc_viewport(mu.copy_viewrect(world.args.viewport), ssao_configs.resolution)
    local fbidx = create_framebuffer(vr.w, vr.h)

    local aod = w:first "ssao_dispatcher dispatch:in"
    aod.dispatch.fb_idx = fbidx

    local sqd = w:first "scene_depth_queue visible?out"
    sqd.visible = true
    w:submit(sqd)

    local bfd = w:first "bilateral_filter_dispatcher dispatch:in"

    local fbidx_blur = create_framebuffer(vr.w, vr.h)
    bfd.dispatch.fb_idx = fbidx_blur

    local sa = imaterial.system_attribs()
    local ssao_fb = fbmgr.get(fbidx)
    sa:update("s_ssao", ssao_fb[1].handle)
end

local texmatrix<const> = mu.calc_texture_matrix()

local function calc_ssao_config(camera, lightdir, depthwidth, depthheight, depthdepth)
    --calc projection scale
    ssao_configs.projection_scale = util.projection_scale(depthwidth, depthheight, camera.projmat)
    ssao_configs.projection_scale_radius = ssao_configs.projection_scale * ssao_configs.radius
    ssao_configs.max_level = depthdepth - 1
    ssao_configs.edge_distance = 1.0 / ssao_configs.bilateral_threshold
    ssao_configs.ssct.lightdir.v = math3d.normalize(math3d.inverse(math3d.transform(camera.viewmat, lightdir, 0)))
end

local ssao_property = {
    type = "i",
    access = "w",
    mip = 0,
    stage = 0,
    value = nil,
}

local function calc_dispatch_size(ww, hh)
    return (ww // 16)+1, (hh//16)+1
end

local function update_properties(dispatcher, ce)
    local sdq = w:first "scene_depth_queue render_target:in"
    local m = dispatcher.material
    m.s_depth = fbmgr.get_depth(sdq.render_target.fb_idx).handle

    local rb = fbmgr.get_rb(dispatcher.fb_idx, 1)
    m.s_ssao_result = {
        type = "i",
        stage = 1,
        access = "w",
        mip = 0,
        value = rb.handle
    }

    icompute.calc_dispatch_size_2d(rb.w, rb.h, dispatcher.size)

    local vr = sdq.render_target.view_rect
    local depthwidth, depthheight, depthdepth = vr.w, vr.h, 1
    local camera = ce.camera
    local projmat = camera.projmat

    local directional_light = w:first "directional_light scene:in"
    local lightdir = directional_light and iom.get_direction(directional_light) or mc.ZAXIS
    calc_ssao_config(camera, lightdir, depthwidth, depthheight, depthdepth)

    m.u_ssao_param = math3d.vector(
        ssao_configs.visible_power,
        ssao_configs.cos_inc, ssao_configs.sin_inc,
        ssao_configs.projection_scale_radius)

    m.u_ssao_param2 = math3d.vector(
        ssao_configs.sample_count, ssao_configs.inv_sample_count,
        ssao_configs.intensity_pre_sample, ssao_configs.bias)

    m.u_ssao_param3 = math3d.vector(
        ssao_configs.inv_radius_squared,
        ssao_configs.min_horizon_angle_sine_squared,
        ssao_configs.peak2,
        ssao_configs.spiral_turns)

    m.u_ssao_param4 = math3d.vector(
        depthwidth, depthheight, ssao_configs.max_level,
        ssao_configs.edge_distance)

    --screen space cone trace
    local ssct = ssao_configs.ssct
    local lx, ly, lz = math3d.index(ssct.lightdir, 1, 2, 3)
    m.u_ssct_param = math3d.vector(lx, ly, lz, ssct.intensity)

    m.u_ssct_param2 = math3d.vector(
        ssct.tan_cone_angle,
        ssao_configs.projection_scale,
        ssct.inv_contact_distance_max,
        ssct.shadow_distance)

    m.u_ssct_param3 = math3d.vector(
        ssct.sample_count,
        ssct.ray_count,
        ssct.depth_bias,
        ssct.depth_slope_bias)
    --screen matrix
    do
        local baismatrix = math3d.mul(math3d.matrix(
            depthwidth, 0.0, 0.0, 0.0,
            0.0, depthheight, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            depthwidth, depthheight, 0.0, 1.0
        ), texmatrix)
        m.u_ssct_screen_from_view_mat = math3d.mul(baismatrix, projmat)
    end
end

local bilateral_config = {
    kernel_radius = HOWTO_SAMPLE.bilateral_filter_raidus,
    std_deviation = 4.0,
    bilateral_threshold = ssao_configs.bilateral_threshold,
}

local KERNEL_MAX_RADIUS_SIZE<const> = 8

local function generate_gaussian_kernels(radius, std_dev, kernels)
    radius = math.min(KERNEL_MAX_RADIUS_SIZE, radius)
    for i=1, radius do
        local x = i-1
        local kidx = (x // 4)+1
        local vidx = (x %  4)+1
        local k = kernels[kidx]
        k[vidx] = math.exp(-(x * x) / (2.0 * std_dev * std_dev))
    end
    return radius
end

local KERNELS       = {math3d.ref(mc.ZERO),math3d.ref(mc.ZERO),}
local KERNELS_COUNT = generate_gaussian_kernels(bilateral_config.kernel_radius, bilateral_config.std_deviation, KERNELS)

local function update_bilateral_filter_properties(material, inputhandle, outputhandle, offset, inv_camera_far_with_bilateral_threshold)
    material.s_ssao_result = inputhandle
    material.s_filter_result = {
        type = "i",
        access = "w",
        mip = 0,
        stage = 1,
        value = outputhandle
    }

    material.u_bilateral_kernels = KERNELS
    material.u_bilateral_param = math3d.vector(offset[1], offset[2], KERNELS_COUNT, inv_camera_far_with_bilateral_threshold)
end

function ssao_sys:build_ssao()
    local aod = w:first "ssao_dispatcher dispatch:in"
    local mq = w:first "main_queue camera_ref:in"
    local ce = w:entity(mq.camera_ref, "camera:in")
    local d = aod.dispatch
    update_properties(d, ce)

    icompute.dispatch(ssao_viewid, d)
end

function ssao_sys:bilateral_filter()
    local mq = w:first "main_queue camera_ref:in"
    local ce = w:entity(mq.camera_ref, "camera:in")
    local inv_camera_far_with_bilateral_threshold<const> = ce.camera.frustum.f / bilateral_config.bilateral_threshold
    
    local bfd = w:first "bilateral_filter_dispatcher dispatch:in"

    local sd = w:first "ssao_dispatcher dispatch:in"
    local inputrb = fbmgr.get_rb(sd.dispatch.fb_idx, 1)
    local inputhandle = inputrb.handle
    local outputrb = fbmgr.get_rb(bfd.dispatch.fb_idx, 1)
    local outputhandle = outputrb.handle

    assert(outputrb.w == inputrb.w and outputrb.h == inputrb.h)
    local bf_dis = bfd.dispatch
    icompute.calc_dispatch_size_2d(inputrb.w, inputrb.h, bf_dis.size)

    local bfdmaterial = bf_dis.material
    update_bilateral_filter_properties(bfdmaterial, inputhandle, outputhandle, {1.0/inputrb.w, 0.0}, inv_camera_far_with_bilateral_threshold)
    icompute.dispatch(Hbilateral_filter_viewid, bf_dis)

    update_bilateral_filter_properties(bfdmaterial, outputhandle, inputhandle, {0.0, 1.0/inputrb.h}, inv_camera_far_with_bilateral_threshold)
    icompute.dispatch(Vbilateral_filter_viewid, bf_dis)

end