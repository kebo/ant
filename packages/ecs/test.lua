-- test solve_depend

TEST = true

function log(name)
	local tag = "[" .. name .. "] "
	local write = io.write
	return function(fmt, ...)
		write(tag)
		write(string.format(fmt, ...))
		write("\n")
	end
end


local system = require "system"

local test = {
	a = { depend = { "b", "c" } },
	b = { depend = { "c" } },
	c = {},
	d = { depend = { "b", "a" } },
}

local list = system._solve_depend(test)
assert(table.concat(list) == "cbad")

-- test ecs

local ecs = require "ecs"

local mods = {}

function mods.basetype(...)
	local ecs = ...

	ecs.component_base("int", 0)
	ecs.component_base("real", 0.0)
	ecs.component_base("string", "")
	ecs.component_base("boolean", false)
end

function mods.dummy(...)
	local ecs = ...
	local world = ecs.world

	local dummy = ecs.system "dummy"

	dummy.singleton "init"
	dummy.depend "init"

	function dummy:init()
		print ("Dummy init")
		local eid = world:create_entity {
			foobar = {
				x = 0, y = 0,
			}
		}
	end

	function dummy:update()
		print ("Dummy update")
		for _, eid in world:each "foobar" do
			print("1. Dummy foobar", eid)
		end
		local newid = world:create_entity {
			foobar = {
				x = 1, y = 1,
			}
		}
		print("Create foobar", newid)
		for _, eid in world:each "foobar" do
			print("2. Dummy foobar", eid)
		end
	end

	local dby = ecs.system "dependby"
	dby.dependby "dummy"

	function dby:init()
		print("in dby:init()")
	end

	local newdummy = ecs.system "new"

	function newdummy:update()
		for eid in world:each_new "foobar" do
			print("New foobar", eid)
			world:remove_entity(eid)
		end
	end

	local delete = ecs.system "delete"

	function delete:delete()
		for eid in world:each_removed "foobar" do
			print("Delete foobar", eid)
		end
	end
end

function mods.init(...)
	local ecs = ...

	local init = ecs.singleton "init"
	local init_system = ecs.system "init"

	init_system.singleton "init"	-- depend singleton components

	function init_system:init()
		print ("Init system")
		self.init.foobar = "Hello"
	end

	function init_system:update()
		print "Init update"
	end
end

function mods.foobar(...)
	local ecs = ...

	local foobar = ecs.component "foobar"
		.x "real"
		.y "real"

	function foobar:init()
		print("New component foobar")
		self.temp = 0
		return self
	end

	function foobar:delete()
		print("Delete", self.x, self.y)
	end

end

local w = ecs.new_world {
	packages = { "basetype", "dummy", "init", "foobar" },
	systems = { "init", "dummy", "new", "delete" },
	loader = function(name) return mods[name] end,
	update_order = { "init" },
}

w:enable_system("dummy", true)

local init = w:update_func "init"
init()
local update = w:update_func "update"
local delete = w:update_func "delete"

local function update_all()
	update()
	delete()
	w:clear_removed()
end

print("Step 1")
update_all()

w:enable_system("dummy", true)

print("Step 2")
update_all()

print("disable dummy system")
w:enable_system("dummy", false)

print("Step 3")
update_all()
