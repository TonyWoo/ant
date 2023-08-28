local ltask      = require "ltask"
local bgfx       = require "bgfx"
local datalist   = require "datalist"
local fastio     = require "fastio"
local textureman = require "textureman.server"
local cr         = require "thread.compile"

local mem_formats <const> = {
    RGBA8 = "bbbb",
    RGBA32F = "ffff",
}

local function readall(filename)
    return bgfx.memory_buffer(fastio.readall(filename))
end

local function createTexture(c)
    local h
    if c.value then
        local ti = c.info
        local v = c.value
        local memfmt = assert(mem_formats[ti.format], "not support memory texture format")
        local m = bgfx.memory_buffer(memfmt, v)
        if ti.cubeMap then
            assert(ti.width == ti.height)
            h = bgfx.create_texturecube(ti.width, ti.numMips ~= 0, ti.numLayers, ti.format, c.flag, m)
        elseif ti.depth == 1 then
            h = bgfx.create_texture2d(ti.width, ti.height, ti.numMips ~= 0, ti.numLayers, ti.format, c.flag, m)
        else
            assert(ti.depth > 1)
            error "not support 3d texture right now"
            h = bgfx.create_texture3d(ti.width, ti.height, ti.depth, ti.numMips ~= 0, ti.numLayers, ti.format, c.flag, m)
        end
    else
        h = bgfx.create_texture(readall(c.path), c.flag)
    end
    bgfx.set_name(h, c.name)
    return h
end

local function loadTexture(name)
    local c = datalist.parse(fastio.readall(cr.compile(name.."|main.cfg")))
    c.name = name
    if not c.value then
        c.path = cr.compile(name.."|main.bin")
    end
    return c
end

local DefaultTexture = {
    TEX2D = createTexture {
        info = {
            width = 1,
            height = 1,
            format = "RGBA8",
            mipmap = false,
            depth = 1,
            numLayers = 1,
            cubeMap = false,
            storageSize = 4,
            numMips = 1,
            bitsPerPixel = 32,
        },
        value = {0, 0, 0, 0},
        flag = "umwwvm+l*p-l",
        sampler = {
            MAG = "LINEAR",
            MIN = "LINEAR",
            U = "CLAMP",
            V = "CLAMP",
        },
        name = "<default2d>"
    },
    --TODO: not support 3d texture right now
    -- TEX3D = createTexture {
    --     info = {
    --         width = 1,
    --         height = 1,
    --         format = "RGBA8",
    --         mipmap = false,
    --         depth = 2,
    --         numLayers = 1,
    --         cubeMap = false,
    --         storageSize = 8,
    --         numMips = 1,
    --         bitsPerPixel = 32,
    --     },
    --     value = {
    --         0, 0, 0, 0, -- depth 1
    --         0, 0, 0, 0, -- depth 2
    --     },
    --     flag = "umwwvm+l*p-l",
    --     sampler = {
    --         MAG = "LINEAR",
    --         MIN = "LINEAR",
    --         U = "CLAMP",
    --         V = "CLAMP",
    --     },
    --     name = "<default3d>"
    -- },
    TEXCUBE = createTexture {
        info = {
            width = 1,
            height = 1,
            format = "RGBA8",
            mipmap = false,
            depth = 1,
            numLayers = 1,
            cubeMap = true,
            storageSize = 24,   -- 4 x 6
            numMips = 1,
            bitsPerPixel = 32,
        },
        value = {
            0, 0, 0, 0, --face 1
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0, --face 6
        },
        flag = "umwwvm+l*p-l",
        sampler = {
            MAG = "LINEAR",
            MIN = "LINEAR",
            U = "CLAMP",
            V = "CLAMP",
        },
        name = "<defaultcube>"
    },
}

local textureByName = {}
local textureById = {}
local loadQueue = {}
local createQueue = {}
local destroyQueue = {}
local token = {}

local function which_texture_type(info)
    if info.cubemap then
        return "TEXCUBE"
    end

    return info.depth > 1 and "TEX3D" or "TEX2D"
end

local function asyncCreateTexture(name, textureData)
    if createQueue[name] then
        return
    end
    createQueue[name] = textureData
    createQueue[#createQueue+1] = name
    if #createQueue == 1 then
        ltask.wakeup(token)
    end
end

local function asyncLoadTexture(c)
    local Token = loadQueue[c.id]
    if Token then
        return Token
    end
    Token = {}
    loadQueue[c.id] = Token
    ltask.fork(function ()
        local textureData = loadTexture(c.name)
        assert(c.type == which_texture_type(textureData.info))
        c.texinfo = textureData.info
        c.sampler = textureData.sampler
        asyncCreateTexture(c.name, textureData)
        loadQueue[c.id] = nil
        ltask.wakeup(Token)
    end)
    return Token
end

local function asyncDestroyTexture(c)
    if createQueue[c.name] then
        return
    end
    destroyQueue[#destroyQueue+1] = c.handle
    textureman.texture_set(c.id, DefaultTexture[c.type])
    c.handle = nil
end

local S = require "thread.main"

function S.texture_default()
    return DefaultTexture
end

function S.texture_create(name, type)
    local c = textureByName[name]
    if c then
        if c.texinfo then
            return {
                id = c.id,
                texinfo = c.texinfo,
                sampler = c.sampler,
            }
        end
    else
        type = type or "TEX2D"
        local id = textureman.texture_create(assert(DefaultTexture[type]))
        c = {
            name = name,
            id = id,
            type = type,
        }
        textureByName[name] = c
        textureById[id] = c
    end
    ltask.wait(asyncLoadTexture(c))
    return {
        id = c.id,
        texinfo = c.texinfo,
        sampler = c.sampler,
    }
end

function S.texture_create_fast(name, type)
    local c = textureByName[name]
    if not c then
        type = type or "TEX2D"
        local id = textureman.texture_create(assert(DefaultTexture[type]))
        c = {
            name = name,
            id = id,
            type = type,
        }
        textureByName[name] = c
        textureById[id] = c
        asyncLoadTexture(c)
    end
    return c.id
end

function S.texture_reload(name, type)
    textureByName[name] = nil
    return S.texture_create(name, type)
end

local FrameLoaded = 0
local MaxFrameLoaded <const> = 64
local rt_table = {}

ltask.fork(function ()
    while true do
        ltask.wait(token)
        while true do
            local name = table.remove(createQueue, 1)
            if not name then
                break
            end
            while FrameLoaded > MaxFrameLoaded do
                ltask.sleep(10)
            end
            local textureData = createQueue[name]
            createQueue[name] = nil
            local c = textureByName[name]
            local handle = createTexture(textureData)
            c.handle = handle
            textureman.texture_set(c.id, handle)
            FrameLoaded = FrameLoaded + 1
            ltask.sleep(0)
        end
    end
end)

local update; do
    local FrameNew = 0
    local FrameCur = 1
    local results = {}
    local UpdateNewInterval <const> = 30 *  1 --  1s
    local UpdateOldInterval <const> = 30 * 60 -- 60s
    local InvalidTexture <const> = ("HH"):pack(DefaultTexture.TEX2D & 0xffff, DefaultTexture.TEXCUBE & 0xffff)
    function update()
        for i = 1, #destroyQueue do
            bgfx.destroy(destroyQueue[i])
            destroyQueue[i] = nil
        end
        if FrameCur % UpdateNewInterval == 0 then
            if #createQueue == 0 then
                textureman.frame_new(FrameCur - FrameNew + 1, InvalidTexture, results)
                for i = 1, #results do
                    local id = results[i]
                    local c = textureById[id]
                    if c then
                        asyncLoadTexture(c)
                    end
                end
                FrameNew = FrameCur - 1
            end
        end
        if FrameCur % UpdateOldInterval == 0 then
            textureman.frame_old(UpdateOldInterval, InvalidTexture, results)
            for i = 1, #results do
                local id = results[i]
                local c = textureById[id]
                if c and (not rt_table[id]) then
                    asyncDestroyTexture(c)
                    print("Destroy Texture: " .. c.name)
                end
            end
        end
        FrameCur = FrameCur + 1
        FrameLoaded = 0
        textureman.frame_tick()
    end
end

function S.texture_timestamp(rtid_table)
    local id_table = {}
    for idx = 1, #rtid_table do
        id_table[#id_table+1] = rtid_table[idx]
    end
    local timestamp_table = textureman.texture_timestamp(id_table)
    local result_table = {}
    for idx = 1, #rtid_table do
        result_table[rtid_table[idx]] = timestamp_table[idx]
    end
    return result_table -- rt_id:timestamp
end

function S.texture_register_id()
    local rt_id = textureman.texture_create(DefaultTexture["TEX2D"])
    rt_table[rt_id] = true
    return rt_id
end

function S.texture_set_handle(rt_id, rt_handle)
    textureman.texture_set(rt_id, rt_handle)
end

function S.texture_destroy_handle(rt_id)
    textureman.texture_set(rt_id, DefaultTexture["TEX2D"])
    return true 
end

return {
    update = update
}