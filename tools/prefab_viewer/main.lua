package.path = "engine/?.lua"
require "bootstrap"
import_package "ant.window".start {
    enable_mouse = true,
    import = {
        "@tools.prefab_viewer",
    },
    pipeline = {
        "init",
        "update",
        "exit",
    },
    feature = {
        "ant.sky|sky",
    },
    system = {
        "tools.prefab_viewer|init_system",
    },
    policy = {
        "ant.scene|scene_object",
        "ant.render|render",
        "ant.render|render_queue",
    }
}
