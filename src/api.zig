/// Idiomatic zig api for the  flecs bindings
const z = @import("zflecs.zig");

const World = struct {
    world: *z.world_t,

    pub fn init() World {
        return .{ .world = z.init() };
    }

    pub fn deinit(self: World) void {
        z.fini(self.world);
    }
};
