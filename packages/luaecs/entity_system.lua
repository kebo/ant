local ecs = ...
local w = ecs.world.w

local m = ecs.system "entity_system"

function m:entity_create()
    for v in w:select "create_entity:in" do
        local initargs = v.create_entity
        initargs.INIT = true
        w:new(initargs)
    end
    w:clear "create_entity"
end

function m:entity_ready()
    w:clear "INIT"
end

function m:update_world()
    w:update()
end
