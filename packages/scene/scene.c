#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>
#include <stdint.h>

#include "luaecs.h"
#include "set.h"

#define COMPONENT_SCENE 1
#define COMPONENT_ENTITYID 2
#define TAG_CHANGE 3

// todo:
struct scene {
	int64_t parent;
};

struct entity_id {
	int64_t id;
};

static int
lupdate_changes(lua_State *L) {
	struct ecs_context *ctx = (struct ecs_context *)lua_touserdata(L, 1);
	struct scene *v;
	int i;
	struct set change_set;
	set_init(&change_set);
	for (i=0;(v=(struct scene*)entity_iter(ctx, COMPONENT_SCENE, i));i++) {
		struct entity_id * e = (struct entity_id *)entity_sibling(ctx, COMPONENT_SCENE, i, COMPONENT_ENTITYID);
		if (e == NULL) {
			return luaL_error(L, "Entity id not found");
		}
		void * change = entity_sibling(ctx, COMPONENT_SCENE, i, TAG_CHANGE);
		printf("Changes %d : %d %s\n", (int)e->id, (int)v->parent, change ? "true" : "false");
		if (change) {
			set_insert(&change_set, e->id);
		} else if (set_exist(&change_set, v->parent)) {
			set_insert(&change_set, e->id);
			entity_enable_tag(ctx, COMPONENT_SCENE, i, TAG_CHANGE);
		}
	}

	set_deinit(&change_set);
	return 0;
}

LUAMOD_API int
luaopen_scene_core(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "update_changes", lupdate_changes },
		{ NULL, NULL },
	};
	luaL_newlib(L, l);
	return 1;
}

/*
testscene.lua

local scene = require "scene.core"

local ecs = require "ecs"

local w = ecs.world()

w:register {
	name = "scene",
	"parent:int64",
}

w:register {
	name = "entityid",
	type = "int64",
}

w:register {
	name = "change"
}

local context = w:context {
	"scene",
	"entityid",
	"change",
}



--[[
    1
   / \
  2   3
 / \
4   5
]]

w:new {
	entityid = 1,
	scene = {
		parent = 0,
	}
}


w:new {
	entityid = 2,
	scene = {
		parent = 1,
	}
}

w:new {
	entityid = 3,
	scene = {
		parent = 1,
	}
}

w:new {
	entityid = 4,
	scene = {
		parent = 2,
	}
}

w:new {
	entityid = 5,
	scene = {
		parent = 2,
	}
}

local function keys(t)
	local r =  {}
	for _, key in ipairs(t) do
		r[key] = true
	end
	return r
end

local changeset = keys { 2, 3 }

for v in w:select "entityid:in scene:in change?out" do
	if changeset[v.entityid] then
		v.change = true
	end
end

local function print_changes()
	for v in w:select "change entityid:in" do
		print(v.entityid, "CHANGE")
	end
end

print_changes()

print "Update"

scene.update_changes(context)

print_changes()

*/
