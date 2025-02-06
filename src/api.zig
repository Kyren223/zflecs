/// Idiomatic zig api for the  flecs bindings
pub const z = @import("zflecs.zig");

// NOTE: currently only 1 world at a time is supported
// This is fine because upstream also has this restriction
var world: *z.world_t = undefined;

pub fn init() *z.world_t {
    world = z.init();
    return world;
}

pub fn deinit() void {
    _ = z.fini(world);
}

pub fn entity() Entity {
    return @bitCast(z.new_id(world));
}

pub fn namedEntity(name: [:0]const u8) Entity {
    return @bitCast(z.set_name(world, 0, name));
}

pub fn lookup(name: []const u8) Entity {
    return @bitCast(z.lookup(world, name));
}

pub fn component(comptime T: type) void {
    z.COMPONENT(world, T);
}

pub fn tag(comptime T: type) void {
    z.TAG(world, T);
}

pub fn id(comptime T: type) Entity {
    return @bitCast(z.id(T));
}

pub const Pair = z.id_t;

pub fn pair(comptime First: type, comptime Second: type) Pair {
    return z.pair(id(First), id(Second));
}

pub fn setScope(e: Entity) Entity {
    return @bitCast(z.set_scope(world, e));
}

pub const EntityDesc = z.entity_desc_t;

pub const Entity = packed struct {
    entity: u64,

    pub fn destruct(self: Entity) void {
        z.delete(world, self.entity);
    }

    pub fn isAlive(self: Entity) bool {
        return z.is_alive(world, self.entity);
    }

    pub fn isValid(self: Entity) bool {
        return z.is_valid(world, self.entity);
    }

    pub fn name(self: Entity) []const u8 {
        return z.get_name(world, self.entity);
    }

    pub fn setName(self: Entity, new_name: []const u8) Entity {
        _ = z.set_name(world, self.entity, new_name);
        return self;
    }

    pub fn add(self: Entity, comptime T: type) void {
        z.add(world, self.entity, T);
    }

    pub fn set(self: Entity, comptime T: type, val: T) Entity {
        _ = z.set(world, self.entity, T, val);
        return self;
    }

    pub fn get(self: Entity, comptime T: type) ?*const T {
        return z.get(world, self.entity, T);
    }

    pub fn getMut(self: Entity, comptime T: type) ?*T {
        return z.get_mut(world, self.entity, T);
    }

    pub fn ensure(self: Entity, comptime T: type) void {
        z.ensure(world, self.entity, T);
    }

    pub fn remove(self: Entity, comptime T: type) void {
        z.remove(world, self.entity, T);
    }

    pub fn clear(self: Entity) void {
        z.clear(world, self.entity);
    }

    pub fn modified(self: Entity, comptime T: type) void {
        z.modified(world, self.entity, T);
    }

    pub fn has(self: Entity, comptime T: type) bool {
        return z.has_id(world, self.entity, id(T).entity);
    }

    pub fn hasId(self: Entity, e: Entity) bool {
        return z.has_id(world, self.entity, e);
    }

    pub fn hasPair(self: Entity, comptime First: type, comptime Second: type) bool {
        return z.has_pair(world, self.entity, id(First), id(Second));
    }

    pub fn hasPairId(self: Entity, first: Entity, second: Entity) bool {
        return z.has_pair(world, self.entity, first, second);
    }

    pub fn lookup(self: Entity, child_name: []const u8) Entity {
        return @bitCast(z.lookup_child(world, self.entity, child_name));
    }

    pub fn enable(self: Entity) void {
        z.enable(world, self.entity, true);
    }

    pub fn disable(self: Entity) void {
        z.enable(world, self.entity, false);
    }

    pub fn enableComponent(self: Entity, comptime T: type) void {
        z.enable_id(world, self.entity, id(T), true);
    }

    pub fn disableComponent(self: Entity, comptime T: type) void {
        z.enable_id(world, self.entity, id(T), false);
    }

    pub fn addPair(self: Entity, comptime First: type, comptime Second: type) void {
        z.add_pair(world, self.entity, id(First), id(Second));
    }

    pub fn addPairId(self: Entity, first: Entity, second: Entity) void {
        z.add_pair(world, self.entity, first, second);
    }

    pub fn removePair(self: Entity, comptime First: type, comptime Second: type) void {
        z.remove_pair(world, self.entity, id(First), id(Second));
    }

    pub fn removePairId(self: Entity, first: Entity, second: Entity) void {
        z.remove_pair(world, self.entity, first, second);
    }

    pub fn setPair(self: Entity, comptime First: type, comptime Second: type, val: First) void {
        z.set_pair(world, self.entity, id(First), id(Second), First, val);
    }

    pub fn setPairSecond(self: Entity, comptime First: type, comptime Second: type, val: Second) void {
        z.set_pair(world, self.entity, id(First), id(Second), Second, val);
    }

    pub fn setPairId(self: Entity, first: Entity, second: Entity, comptime T: type, val: T) void {
        z.set_pair(world, self.entity, first, second, T, val);
    }

    pub fn parent(self: Entity) Entity {
        return @bitCast(z.get_parent(world, self.entity));
    }

    pub fn target(self: Entity, comptime T: type, index: i32) Entity {
        z.get_target(world, self.entity, id(T), index);
    }

    pub fn isA(self: Entity, comptime T: type) void {
        self.addPairId(z.IsA, id(T));
    }

    pub fn isAnId(self: Entity, e: Entity) void {
        self.addPairId(z.IsA, e);
    }

    pub fn childOf(self: Entity, comptime T: type) void {
        self.addPairId(z.ChildOf, id(T));
    }

    pub fn childOfId(self: Entity, e: Entity) void {
        self.addPairId(z.ChildOf, e);
    }
};

pub const singleton = struct {
    pub fn add(comptime T: type) void {
        z.singleton_add(world, T);
    }

    pub fn set(comptime T: type) void {
        _ = z.singleton_set(world, T);
    }

    pub fn remove(comptime T: type) void {
        z.singleton_remove(world, T);
    }

    pub fn get(comptime T: type) ?*const T {
        z.singleton_get(world, T);
    }

    pub fn getMut(comptime T: type) ?*T {
        return z.singleton_get_mut(world, T);
    }

    pub fn modified(comptime T: type) void {
        z.singleton_modified(world, T);
    }
};

pub fn query(comptime Ts: [z.FLECS_TERM_COUNT_MAX]type) !Query {
    var desc = z.query_desc_t{};
    for (Ts, 0..) |T, i| {
        desc.terms[i].id = id(T).entity;
    }
    const q = try z.query_init(world, &desc);
    return .{ .query = q };
}

pub const Query = struct {
    query: *z.query_t,

    pub fn deinit() void {}
};
