local lm = require "luamake"

lm:build {
    "$luamake", "lua", "@embed.lua", "$in",
    "@.", "FirmwareBootstrap",
    input = "../../engine/firmware/bootstrap.lua",
    output = "FirmwareBootstrap.h",
}

lm:build {
    "$luamake", "lua", "@embed.lua", "$in",
    "@.", "FirmwareIo",
    input = "../../engine/firmware/io.lua",
    output = "FirmwareIo.h",
}

lm:build {
    "$luamake", "lua", "@embed.lua", "$in",
    "@.", "FirmwareVfs",
    input = "../../engine/firmware/vfs.lua",
    output = "FirmwareVfs.h",
}

lm:phony {
    input = {
        "FirmwareBootstrap.h",
        "FirmwareIo.h",
        "FirmwareVfs.h",
    },
    output = "firmware.cpp",
}

lm:lua_source "firmware" {
    sources = {
        "firmware.cpp",
    }
}
