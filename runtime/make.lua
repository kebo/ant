local lm = require "luamake"
local fs = require "bee.filesystem"
local platform = require "bee.platform"

local RuntimeBacklist <const> = {
    filedialog = true,
    window = platform.os == "android" or platform.os == "linux",
    debugger = lm.luaversion == "lua55",
}

local EditorBacklist <const> = {
    firmware = true,
    window = platform.os == "android" or platform.os == "linux",
    debugger = lm.luaversion == "lua55",
}

local RuntimeModules = {}
local EditorModules = {}

local function checkAddModule(name, makefile)
    if not RuntimeBacklist[name] or not EditorBacklist[name] then
        lm:import(makefile)
    end
    if not RuntimeBacklist[name] then
        if lm:has(name) then
            RuntimeModules[#RuntimeModules + 1] = name
        end
    end
    if not EditorBacklist[name] then
        if lm:has(name) then
            EditorModules[#EditorModules + 1] = name
        end
    end
end

for path in fs.pairs(fs.path(lm.workdir) / "../clibs") do
    if fs.exists(path / "make.lua") then
        local name = path:stem():string()
        local makefile = ("../clibs/%s/make.lua"):format(name)
        checkAddModule(name, makefile)
    end
end

for path in fs.pairs(fs.path(lm.workdir) / "../pkg") do
    if fs.exists(path / "make.lua") then
        local name = path:filename():string()
        local makefile = ("../pkg/%s/make.lua"):format(name)
        checkAddModule(name:sub(5, -1), makefile)
    end
end

lm:copy "copy_mainlua" {
    inputs = "common/main.lua",
    outputs = "$bin/main.lua",
}

lm:lua_source "ant_common" {
    deps = "lua_source",
    includes = {
        lm.AntDir .. "/3rd/bgfx/include",
        lm.AntDir .. "/3rd/bx/include",
        lm.AntDir .. "/3rd/bee.lua",
        "common"
    },
    sources = "common/runtime.cpp",
    windows = {
        sources = {
            "windows/main.cpp",
            lm.AntDir .. "/3rd/bee.lua/3rd/lua/bee_utf8_main.c",
        }
    },
    linux = {
        sources = "posix/main.cpp",
    },
    macos = {
        sources = "posix/main.cpp",
    },
    ios = {
        sources = {
            "common/ios/main.mm",
            "common/ios/ios_error.mm",
        }
    }
}
lm:lua_source "ant_openlibs" {
    sources = "common/ant_openlibs.c",
}

lm:source_set "ant_links" {
    windows = {
        links = {
            "shlwapi",
            "user32",
            "gdi32",
            "shell32",
            "ole32",
            "oleaut32",
            "wbemuuid",
            "winmm",
            "ws2_32",
            "imm32",
            "advapi32",
            "version",
        }
    },
    macos = {
        frameworks = {
            "Carbon",
            "IOKit",
            "Foundation",
            "Metal",
            "QuartzCore",
            "Cocoa"
        }
    },
    ios = {
        frameworks = {
            "CoreTelephony",
            "SystemConfiguration",
            "Foundation",
            "CoreText",
            "UIKit",
            "Metal",
            "QuartzCore",
            "IOSurface",
            "CoreGraphics"
        },
        ldflags = {
            "-fembed-bitcode",
            "-fobjc-arc"
        }
    },
    android = {
        links = {
            "android",
            "log",
            "m",
        }
    }
}

local antrt_defines = {
    "ANT_RUNTIME",
}

local anted_defines = {}

if lm.mode == "debug" then
    antrt_defines[#antrt_defines+1] = "MATH3D_ADAPTER_TEST"
    anted_defines[#anted_defines+1] = "MATH3D_ADAPTER_TEST"
end

lm:lua_source "ant_runtime" {
    deps = {
        "ant_common",
        RuntimeModules,
    },
    includes = {
        "../3rd/bgfx/include",
        "../3rd/bx/include",
    },
    defines = antrt_defines,
    sources = "common/modules.c",
}

lm:lua_source "ant_editor" {
    deps = {
        "ant_common",
        EditorModules,
    },
    includes = {
        "../3rd/bgfx/include",
        "../3rd/bx/include",
    },
    defines = anted_defines,
    sources = {
        "common/modules.c",
    },
}

if lm.os == "android" then
    lm:dll "ant" {
        deps = {
            "ant_runtime",
            "ant_openlibs",
            "bgfx-lib",
            "ant_links",
            "copy_mainlua"
        }
    }
    lm:phony "runtime" {
        deps = "ant"
    }
    return
end

lm:exe "lua" {
    deps = {
        "ant_editor",
        "ant_openlibs",
        "bgfx-lib",
        "ant_links",
        "copy_mainlua"
    },
    windows = {
        sources = "windows/lua.rc",
    },
}

lm:exe "ant" {
    deps = {
        "ant_runtime",
        "ant_openlibs",
        "bgfx-lib",
        "ant_links",
        "copy_mainlua"
    },
    windows = {
        sources = "windows/lua.rc",
    },
}

lm:phony "editor" {
    deps = "lua"
}

lm:phony "runtime" {
    deps = "ant"
}