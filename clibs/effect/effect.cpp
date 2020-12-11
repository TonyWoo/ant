#include "pch.h"
#define LUA_LIB
#include "particle.h"
#include "random.h"

#include "attributes.h"

#include "quadcache.h"
#include "lua2struct.h"

#include "lua.hpp"

#define EXPORT_BGFX_INTERFACE
#include "bgfx/bgfx_interface.h"

static int
leffect_init(lua_State *L){
    particle_mgr::create();
    return 0;
}

static int
leffect_shutdown(lua_State *L){
    particle_mgr::destroy();
    return 0;
}

static int
leffect_create_emitter(lua_State *L){
    luaL_checktype(L, 1, LUA_TTABLE);

    lua_struct::unpack(L, 1, particle_mgr::get().get_rd());

    if (LUA_TTABLE == lua_getfield(L, 1, "emitter")){
        comp_ids ids;
        ids.push_back(ID_TAG_emitter);

        const char* emitter_tags[] = {"spawn", "emitter_lifetime"};
        for (auto tag : emitter_tags){
            if (LUA_TTABLE == lua_getfield(L, -1, tag)){
                auto reader = find_attrib_reader(tag);
                reader(L, -1, ids);
            } else {
                luaL_error(L, "invalid field:%s", tag);
            }
            lua_pop(L, 1);
        }

        auto is_emitter_tag = [emitter_tags](const std::string &s){
            for (auto tag:emitter_tags){
                if (tag == s)
                    return true;
            }

            return false;
        };

        for(lua_pushnil(L); lua_next(L, -2); lua_pop(L, 1)){
           if (LUA_TSTRING == lua_type(L, -2)){
                const std::string key = lua_tostring(L, -2);
                if (!is_emitter_tag(key)){
                    auto reader = find_attrib_reader(key);
                    reader(L, -1, ids);
                }
           }
        }
        particle_mgr::get().add(ids);
    } else {
        luaL_error(L, "invalid 'emitter'");
    }
    lua_pop(L, 1);

    return 1;
}

static int
leffect_update(lua_State *L){
    const float dt = (float)luaL_checknumber(L, 1);
    particle_mgr::get().update(dt);
    return 0;
}

extern "C" {
    LUAMOD_API int
    luaopen_effect(lua_State *L){
        init_interface(L);

        luaL_Reg l[] = {
            { "init",               leffect_init },
            { "shutdown",           leffect_shutdown },
            { "create_emitter",     leffect_create_emitter},
            { "update",             leffect_update},
            { nullptr, nullptr },
        };
        luaL_newlib(L, l);
        return 1;
    }
}