/// Idiomatic zig api for the  flecs bindings
pub const z = @import("zflecs.zig");

// NOTE: currently only 1 world at a time is supported
// This is fine because upstream also has this restriction
var world: *z.world_t = undefined;

pub fn init() void {
    world = z.init();
}

pub fn deinit() void {
    z.fini(world);
}

pub fn entity() Entity {
    return .{ .entity = z.new_id(world) };
}

pub fn entity_named(name: []const u8) Entity {
    return .{ .entity = z.entity_init(world, .{ .name = name }) };
}

pub fn lookup(name: []const u8) Entity {
    return .{ .entity = z.lookup(world, name) };
}

pub fn component(comptime T: type) void {
    z.COMPONENT(world, T);
}

pub fn id(comptime T: type) Id {
    return z.id(T);
}

pub fn pair(comptime First: type, comptime Second: type) Entity {
    return z.pair(id(First), id(Second));
}

pub const Id = struct {
    id: z.id_t,
};

pub const Entity = struct {
    entity: z.entity_t,

    pub fn isAlive(self: Entity) bool {
        return z.is_alive(world, self.entity);
    }

    pub fn destruct(self: Entity) void {
        z.delete(world, self.entity);
    }

    pub fn name(self: Entity) []const u8 {
        return z.get_name(world, self.entity);
    }

    pub fn add(self: Entity, comptime T: type) void {
        z.add(world, self.entity, T);
    }

    pub fn set(self: Entity, comptime T: type, val: T) void {
        z.set(world, self.entity, T, val);
    }

    pub fn get(self: Entity, comptime T: type) T {
        return z.get(world, self.entity, T);
    }

    pub fn remove(self: Entity, comptime T: type) void {
        z.remove(world, self.entity, T);
    }

    pub fn has(self: Entity, comptime T: type) bool {
        return z.has_id(world, self.entity, id(T));
    }

    pub fn hasPair(self: Entity, comptime First: type, comptime Second: type) bool {
        return z.has_pair(world, self.entity, id(First), id(Second));
    }

    pub fn hasId(self: Entity, e: Entity) bool {
        return z.has_id(world, self.entity, e.entity);
    }

    pub fn hasPairId(self: Entity, first: Entity, second: Entity) bool {
        return z.has_pair(world, self.entity, first, second);
    }
};
