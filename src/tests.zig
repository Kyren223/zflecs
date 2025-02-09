const std = @import("std");
const ecs = @import("zflecs.zig");
const api = @import("ecs.zig");
const builtin = @import("builtin");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const print = std.log.info;

const Position = struct { x: f32, y: f32 };
const Velocity = struct { x: f32, y: f32 };
const Walking = struct {};
const Direction = enum { north, south, east, west };

test {
    std.testing.refAllDeclsRecursive(@This());
}

test "extern struct ABI compatibility" {
    @setEvalBranchQuota(50_000);
    const flecs_c = @cImport({
        @cDefine("FLECS_SANITIZE", if (builtin.mode == .Debug) "1" else {});
        @cDefine("FLECS_USE_OS_ALLOC", "1");
        @cDefine("FLECS_NO_CPP", "1");
        @cInclude("flecs.h");
    });
    inline for (comptime std.meta.declarations(@This())) |decl| {
        const ZigType = @field(@This(), decl.name);
        if (@TypeOf(ZigType) != type) {
            continue;
        }
        if (comptime std.meta.activeTag(@typeInfo(ZigType)) == .@"struct" and
            @typeInfo(ZigType).@"struct".layout == .@"extern")
        {
            const flecs_name = if (comptime std.mem.startsWith(u8, decl.name, "Ecs")) decl.name else "ecs_" ++ decl.name;

            const CType = @field(flecs_c, flecs_name);
            std.testing.expectEqual(@sizeOf(CType), @sizeOf(ZigType)) catch |err| {
                std.log.err("@sizeOf({s}) != @sizeOf({s})", .{ flecs_name, decl.name });
                return err;
            };
            comptime var i: usize = 0;
            inline for (comptime std.meta.fieldNames(CType)) |c_field_name| {
                std.testing.expectEqual(
                    @offsetOf(CType, c_field_name),
                    @offsetOf(ZigType, std.meta.fieldNames(ZigType)[i]),
                ) catch |err| {
                    std.log.err(
                        "@offsetOf({s}, {s}) != @offsetOf({s}, {s})",
                        .{ flecs_name, c_field_name, decl.name, std.meta.fieldNames(ZigType)[i] },
                    );
                    return err;
                };
                i += 1;
            }
        }
    }
}

test "zflecs.entities.basics" {
    print("\n", .{});

    const world = ecs.init();
    defer _ = ecs.fini(world);

    ecs.COMPONENT(world, Position);
    ecs.TAG(world, Walking);

    const bob = ecs.set_name(world, 0, "Bob");

    _ = ecs.set(world, bob, Position, .{ .x = 10, .y = 20 });
    ecs.add(world, bob, Walking);

    const ptr = ecs.get(world, bob, Position).?;
    print("({d}, {d})\n", .{ ptr.x, ptr.y });

    _ = ecs.set(world, bob, Position, .{ .x = 20, .y = 30 });

    const alice = ecs.set_name(world, 0, "Alice");
    _ = ecs.set(world, alice, Position, .{ .x = 10, .y = 20 });
    ecs.add(world, alice, Walking);

    const str = ecs.type_str(world, ecs.get_type(world, alice)).?;
    defer ecs.os.free(str);
    print("[{s}]\n", .{str});

    ecs.remove(world, alice, Walking);

    {
        var term = ecs.term_t{ .id = ecs.id(Position) };
        var it = ecs.each(world, &term);
        while (ecs.each_next(&it)) {
            if (ecs.field(&it, Position, 0)) |positions| {
                for (positions, it.entities()) |p, e| {
                    print(
                        "Term loop: {s}: ({d}, {d})\n",
                        .{ ecs.get_name(world, e).?, p.x, p.y },
                    );
                }
            }
        }
    }

    {
        var desc = ecs.query_desc_t{};
        desc.terms[0].id = ecs.id(Position);
        const query = try ecs.query_init(world, &desc);
        defer ecs.query_fini(query);
    }

    {
        const query = try ecs.query_init(world, &.{
            .terms = [_]ecs.term_t{
                .{ .id = ecs.id(Position) },
                .{ .id = ecs.id(Walking) },
            } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2),
        });
        defer ecs.query_fini(query);

        var it = ecs.query_iter(world, query);
        while (ecs.query_next(&it)) {
            for (it.entities()) |e| {
                print("Filter loop: {s}\n", .{ecs.get_name(world, e).?});
            }
        }
    }

    {
        const query = _: {
            var desc = ecs.query_desc_t{};
            desc.terms[0].id = ecs.id(Position);
            desc.terms[1].id = ecs.id(Walking);
            break :_ try ecs.query_init(world, &desc);
        };
        defer ecs.query_fini(query);
    }

    {
        const query = try ecs.query_init(world, &.{
            .terms = [_]ecs.term_t{
                .{ .id = ecs.id(Position) },
                .{ .id = ecs.id(Walking) },
            } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2),
        });
        defer ecs.query_fini(query);
    }
}

fn registerComponents(world: *ecs.world_t) void {
    ecs.COMPONENT(world, *const Position);
    ecs.COMPONENT(world, ?*const Position);
}

test "zflecs.basic" {
    print("\n", .{});

    const world = ecs.init();
    defer _ = ecs.fini(world);

    try expect(ecs.is_fini(world) == false);

    ecs.dim(world, 100);

    const e0 = ecs.entity_init(world, &.{ .name = "aaa" });
    try expect(e0 != 0);
    try expect(ecs.is_alive(world, e0));
    try expect(ecs.is_valid(world, e0));

    const e1 = ecs.new_id(world);
    try expect(ecs.is_alive(world, e1));
    try expect(ecs.is_valid(world, e1));

    _ = ecs.clone(world, e1, e0, false);
    try expect(ecs.is_alive(world, e1));
    try expect(ecs.is_valid(world, e1));

    ecs.delete(world, e1);
    try expect(!ecs.is_alive(world, e1));
    try expect(!ecs.is_valid(world, e1));

    registerComponents(world);
    ecs.COMPONENT(world, *Position);
    ecs.COMPONENT(world, Position);
    ecs.COMPONENT(world, ?*const Position);
    ecs.COMPONENT(world, Direction);
    ecs.COMPONENT(world, f64);
    ecs.COMPONENT(world, u31);
    ecs.COMPONENT(world, u32);
    ecs.COMPONENT(world, f32);
    ecs.COMPONENT(world, f64);
    ecs.COMPONENT(world, i8);
    ecs.COMPONENT(world, ?*const i8);

    {
        const p0 = ecs.pair(ecs.id(u31), e0);
        const p1 = ecs.pair(e0, e0);
        const p2 = ecs.pair(ecs.OnUpdate, ecs.id(Direction));
        {
            const str = ecs.id_str(world, p0).?;
            defer ecs.os.free(str);
            print("{s}\n", .{str});
        }
        {
            const str = ecs.id_str(world, p1).?;
            defer ecs.os.free(str);
            print("{s}\n", .{str});
        }
        {
            const str = ecs.id_str(world, p2).?;
            defer ecs.os.free(str);
            print("{s}\n", .{str});
        }
    }

    const S0 = struct {
        a: f32 = 3.0,
    };
    ecs.COMPONENT(world, S0);

    ecs.TAG(world, Walking);

    const PrintIdHelper = struct {
        fn printId(in_world: *ecs.world_t, comptime T: type) void {
            const id_str = ecs.id_str(in_world, ecs.id(T)).?;
            defer ecs.os.free(id_str);

            print("{s} id: {d}\n", .{ id_str, ecs.id(T) });
        }
    };

    PrintIdHelper.printId(world, *const Position);
    PrintIdHelper.printId(world, ?*const Position);
    PrintIdHelper.printId(world, *Position);
    PrintIdHelper.printId(world, Position);
    PrintIdHelper.printId(world, *Direction);
    PrintIdHelper.printId(world, *Walking);
    PrintIdHelper.printId(world, *u31);

    const p: Position = .{ .x = 1.0, .y = 2.0 };
    _ = ecs.set(world, e0, *const Position, &p);
    _ = ecs.set(world, e0, ?*const Position, null);
    _ = ecs.set(world, e0, Position, .{ .x = 1.0, .y = 2.0 });
    _ = ecs.set(world, e0, Direction, .west);
    _ = ecs.set(world, e0, u31, 123);
    _ = ecs.set(world, e0, u31, 1234);
    _ = ecs.set(world, e0, u32, 987);
    _ = ecs.set(world, e0, S0, .{});

    ecs.add(world, e0, Walking);

    try expect(ecs.get(world, e0, u31).?.* == 1234);
    try expect(ecs.get(world, e0, u32).?.* == 987);
    try expect(ecs.get(world, e0, S0).?.a == 3.0);
    try expect(ecs.get(world, e0, ?*const Position).?.* == null);
    try expect(ecs.get(world, e0, *const Position).?.* == &p);
    if (ecs.get(world, e0, Position)) |pos| {
        try expect(pos.x == p.x and pos.y == p.y);
    }

    const e0_type_str = ecs.type_str(world, ecs.get_type(world, e0)).?;
    defer ecs.os.free(e0_type_str);

    const e0_table_str = ecs.table_str(world, ecs.get_table(world, e0)).?;
    defer ecs.os.free(e0_table_str);

    const e0_str = ecs.entity_str(world, e0).?;
    defer ecs.os.free(e0_str);

    print("type str: {s}\n", .{e0_type_str});
    print("table str: {s}\n", .{e0_table_str});
    print("entity str: {s}\n", .{e0_str});

    {
        const str = ecs.type_str(world, ecs.get_type(world, ecs.id(Position))).?;
        defer ecs.os.free(str);
        print("{s}\n", .{str});
    }
    {
        const str = ecs.id_str(world, ecs.id(Position)).?;
        defer ecs.os.free(str);
        print("{s}\n", .{str});
    }
}

const Eats = struct {};
const Apples = struct {};

fn move(it: *ecs.iter_t) callconv(.C) void {
    const p = ecs.field(it, Position, 0).?;
    const v = ecs.field(it, Velocity, 1).?;

    const type_str = ecs.table_str(it.world, it.table).?;
    print("Move entities with [{s}]\n", .{type_str});
    defer ecs.os.free(type_str);

    for (0..it.count()) |i| {
        p[i].x += v[i].x;
        p[i].y += v[i].y;
    }
}

test "zflecs.helloworld" {
    print("\n", .{});

    const world = ecs.init();
    defer _ = ecs.fini(world);

    ecs.COMPONENT(world, Position);
    ecs.COMPONENT(world, Velocity);

    ecs.TAG(world, Eats);
    ecs.TAG(world, Apples);

    {
        _ = ecs.ADD_SYSTEM_WITH_FILTERS(world, "move system", ecs.OnUpdate, move, &.{
            .{ .id = ecs.id(Position) },
            .{ .id = ecs.id(Velocity) },
        });
    }

    const bob = ecs.new_entity(world, "Bob");
    _ = ecs.set(world, bob, Position, .{ .x = 0, .y = 0 });
    _ = ecs.set(world, bob, Velocity, .{ .x = 1, .y = 2 });
    ecs.add_pair(world, bob, ecs.id(Eats), ecs.id(Apples));

    _ = ecs.progress(world, 0);
    _ = ecs.progress(world, 0);

    const p = ecs.get(world, bob, Position).?;
    print("Bob's position is ({d}, {d})\n", .{ p.x, p.y });
}

fn move_system(positions: []Position, velocities: []const Velocity) void {
    for (positions, velocities) |*p, v| {
        p.x += v.x;
        p.y += v.y;
    }
}

//Optionally, systems can receive the components iterator (usually not necessary)
fn move_system_with_it(it: *ecs.iter_t, positions: []Position, velocities: []const Velocity) void {
    const type_str = ecs.table_str(it.world, it.table).?;
    print("Move entities with [{s}]\n", .{type_str});
    defer ecs.os.free(type_str);

    for (positions, velocities) |*p, v| {
        p.x += v.x;
        p.y += v.y;
    }
}

test "zflecs.helloworld_systemcomptime" {
    print("\n", .{});

    const world = ecs.init();
    defer _ = ecs.fini(world);

    ecs.COMPONENT(world, Position);
    ecs.COMPONENT(world, Velocity);

    ecs.TAG(world, Eats);
    ecs.TAG(world, Apples);

    _ = ecs.ADD_SYSTEM(world, "move system", ecs.OnUpdate, move_system);
    _ = ecs.ADD_SYSTEM(world, "move system with iterator", ecs.OnUpdate, move_system_with_it);

    const bob = ecs.new_entity(world, "Bob");
    _ = ecs.set(world, bob, Position, .{ .x = 0, .y = 0 });
    _ = ecs.set(world, bob, Velocity, .{ .x = 1, .y = 2 });
    ecs.add_pair(world, bob, ecs.id(Eats), ecs.id(Apples));

    _ = ecs.progress(world, 0);
    _ = ecs.progress(world, 0);

    const p = ecs.get(world, bob, Position).?;
    print("Bob's position is ({d}, {d})\n", .{ p.x, p.y });
}

test "zflecs.try_different_alignments" {
    const world = ecs.init();
    defer _ = ecs.fini(world);

    const AlignmentsToTest = [_]usize{ 1, 2, 4, 8, 16 };
    inline for (AlignmentsToTest) |component_alignment| {
        const AlignedComponent = struct {
            fn Component(comptime alignment: usize) type {
                return struct { dummy: u32 align(alignment) = 0 };
            }
        };

        const Component = AlignedComponent.Component(component_alignment);

        ecs.COMPONENT(world, Component);
        const entity = ecs.new_entity(world, "");

        _ = ecs.set(world, entity, Component, .{});
        _ = ecs.get(world, entity, Component);
    }
}

test "zflecs.pairs.tag-tag" {
    const world = ecs.init();
    defer _ = ecs.fini(world);

    const Slowly = struct {};
    ecs.TAG(world, Slowly);
    ecs.TAG(world, Walking);

    const entity = ecs.new_entity(world, "Bob");

    _ = ecs.add_pair(world, entity, ecs.id(Slowly), ecs.id(Walking));
    try expect(ecs.has_pair(world, entity, ecs.id(Slowly), ecs.id(Walking)));

    _ = ecs.remove_pair(world, entity, ecs.id(Slowly), ecs.id(Walking));
    try expect(!ecs.has_pair(world, entity, ecs.id(Slowly), ecs.id(Walking)));
}

test "zflecs.pairs.component-tag" {
    const world = ecs.init();
    defer _ = ecs.fini(world);

    const Speed = u8;
    ecs.COMPONENT(world, Speed);
    ecs.TAG(world, Walking);

    const entity = ecs.new_entity(world, "Bob");

    _ = ecs.set_pair(world, entity, ecs.id(Speed), ecs.id(Walking), Speed, 2);
    try expect(ecs.has_pair(world, entity, ecs.id(Speed), ecs.id(Walking)));
    try expectEqual(@as(u8, 2), ecs.get_pair(world, entity, ecs.id(Speed), ecs.id(Walking), Speed).?.*);

    _ = ecs.remove_pair(world, entity, ecs.id(Speed), ecs.id(Walking));
    try expect(!ecs.has_pair(world, entity, ecs.id(Speed), ecs.id(Walking)));
    try expectEqual(@as(?*const u8, null), ecs.get_pair(world, entity, ecs.id(Speed), ecs.id(Walking), Speed));
}

test "zflecs.pairs.delete-children" {
    const world = ecs.init();
    defer _ = ecs.fini(world);

    const Camera = struct { id: u8 };

    ecs.COMPONENT(world, Camera);

    const entity = ecs.new_entity(world, "scene");

    const fps = ecs.new_w_pair(world, ecs.ChildOf, entity);
    _ = ecs.set(world, fps, Camera, .{ .id = 1 });
    const third_person = ecs.new_w_pair(world, ecs.ChildOf, entity);
    _ = ecs.set(world, third_person, Camera, .{ .id = 2 });

    var found: u8 = 0;
    var it = ecs.children(world, entity);
    while (ecs.children_next(&it)) {
        for (0..it.count()) |i| {
            const child_entity = it.entities()[i];
            const p: ?*const Camera = ecs.get(world, child_entity, Camera);
            try expectEqual(@as(u8, @intCast(i)), p.?.id - @as(u8, 1));
            found += 1;
        }
    }
    try expectEqual(@as(u8, 2), found);
    ecs.delete_children(world, entity);

    found = 0;
    it = ecs.children(world, entity);
    while (ecs.children_next(&it)) {
        for (0..it.count()) |_| {
            found += 1;
        }
    }
    try expectEqual(@as(u8, 0), found);
}

test "zflecs.struct-dtor-hook" {
    const world = ecs.init();
    defer _ = ecs.fini(world);

    const Chat = struct {
        messages: std.ArrayList([]const u8),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return @This(){
                .messages = std.ArrayList([]const u8).init(allocator),
            };
        }

        pub fn dtor(self: @This()) void {
            self.messages.deinit();
        }
    };

    ecs.COMPONENT(world, Chat);
    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = struct {
            pub fn chatSystem(it: *ecs.iter_t) callconv(.C) void {
                const chat_components = ecs.field(it, Chat, 0).?;
                for (0..it.count()) |i| {
                    chat_components[i].messages.append("some words hi") catch @panic("whomp");
                }
            }
        }.chatSystem;
        system_desc.query.terms[0] = .{ .id = ecs.id(Chat) };
        _ = ecs.SYSTEM(world, "Chat system", ecs.OnUpdate, &system_desc);
    }

    const chat_entity = ecs.new_entity(world, "Chat entity");
    _ = ecs.set(world, chat_entity, Chat, Chat.init(std.testing.allocator));

    _ = ecs.progress(world, 0);

    const chat_component = ecs.get(world, chat_entity, Chat).?;
    try std.testing.expect(chat_component.messages.items.len == 1);

    // This test fails if the ".hooks = .{ .dtor = ... }" from COMPONENT is
    // commented out since the cleanup is never called to free the ArrayList
    // memory.
}

test "zflecs.api.entities.basics" {
    print("\n", .{});

    api.init();
    defer api.deinit();

    api.component(Position);
    api.tag(Walking);

    const bob = api.namedEntity("Bob");

    _ = bob.set(Position, .{ .x = 10, .y = 20 });
    bob.add(Walking);

    const ptr = bob.get(Position).?;
    print("({d}, {d})\n", .{ ptr.x, ptr.y });

    _ = bob.set(Position, .{ .x = 20, .y = 30 });

    const alice = api.namedEntity("Alice");
    _ = alice.set(Position, .{ .x = 10, .y = 20 });
    alice.add(Walking);

    const str = alice.getType().?.string().?;
    defer api.os.free(str);
    print("[{s}]\n", .{str});

    alice.remove(Walking);

    {
        // var term = api.z.term_t{ .id = api.id(Position).entity };
        // var it = api.z.each(world, &term);
        // while (api.z.each_next(&it)) {
        //     if (api.z.field(&it, Position, 0)) |positions| {
        //         for (positions, it.entities()) |p, e| {
        //             print(
        //                 "Term loop: {s}: ({d}, {d})\n",
        //                 .{ api.z.get_name(world, e).?, p.x, p.y },
        //             );
        //         }
        //     }
        // }
    }

    {
        const query = try api.query(&.{Position});
        defer query.deinit();
    }

    {
        const query = try api.query(&.{ Position, Walking });
        defer query.deinit();

        var it = query.iter();
        while (it.next()) {
            for (it.entities()) |e| {
                print("Filter loop: {s}\n", .{e.name().?});
            }
        }
    }

    {
        var qbuilder = api.queryBuilder(&.{ Position, Walking });
        var query = try qbuilder.build();
        defer query.deinit();
    }
}

test "zflecs.api.basic" {
    print("\n", .{});

    api.init();
    defer api.deinit();

    try expect(api.hasWorld());

    api.dim(100);

    const e0 = api.namedEntity("aaa");
    try expect(e0 != api.Entity.invalid);
    try expect(e0.isAlive());
    try expect(e0.isValid());

    const e1 = api.entity();
    try expect(e1.isAlive());
    try expect(e1.isValid());

    _ = api.clone(e1, e0, false);
    try expect(e1.isAlive());
    try expect(e1.isValid());

    e1.deinit();
    try expect(!e1.isAlive());
    try expect(!e1.isValid());

    registerComponents(api.world);
    api.component(*Position);
    api.component(Position);
    api.component(?*const Position);
    api.component(Direction);
    api.component(f64);
    api.component(u31);
    api.component(u32);
    api.component(f32);
    api.component(f64);
    api.component(i8);
    api.component(?*const i8);

    {
        const p0 = api.pairId(api.id(u31), e0);
        const p1 = api.pairId(e0, e0);
        const p2 = api.pair(api.OnUpdate, Direction);
        {
            const str = p0.string().?;
            defer ecs.os.free(str);
            print("{s}\n", .{str});
        }
        {
            const str = p1.string().?;
            defer ecs.os.free(str);
            print("{s}\n", .{str});
        }
        {
            const str = p2.string().?;
            defer ecs.os.free(str);
            print("{s}\n", .{str});
        }
    }

    const S0 = struct {
        a: f32 = 3.0,
    };
    api.component(S0);

    api.tag(Walking);

    const PrintIdHelper = struct {
        fn printId(comptime T: type) void {
            const id_str = api.id(T).string().?;
            defer ecs.os.free(id_str);

            print("{s} id: {d}\n", .{ id_str, api.id(T).entity });
        }
    };

    PrintIdHelper.printId(*const Position);
    PrintIdHelper.printId(?*const Position);
    PrintIdHelper.printId(*Position);
    PrintIdHelper.printId(Position);
    PrintIdHelper.printId(*Direction);
    PrintIdHelper.printId(*Walking);
    PrintIdHelper.printId(*u31);

    const p: Position = .{ .x = 1.0, .y = 2.0 };
    _ = e0.set(*const Position, &p);
    _ = e0.set(?*const Position, null);
    _ = e0.set(Position, .{ .x = 1.0, .y = 2.0 });
    _ = e0.set(Direction, .west);
    _ = e0.set(u31, 123);
    _ = e0.set(u31, 1234);
    _ = e0.set(u32, 987);
    _ = e0.set(S0, .{});

    e0.add(Walking);

    try expect(e0.get(u31).?.* == 1234);
    try expect(e0.get(u32).?.* == 987);
    try expect(e0.get(S0).?.a == 3.0);
    try expect(e0.get(?*const Position).?.* == null);
    try expect(e0.get(*const Position).?.* == &p);
    if (e0.get(Position)) |pos| {
        try expect(pos.x == p.x and pos.y == p.y);
    }

    const e0_type_str = e0.getType().?.string().?;
    defer ecs.os.free(e0_type_str);

    const e0_table_str = e0.table().?.string().?;
    defer ecs.os.free(e0_table_str);

    const e0_str = e0.string().?;
    defer ecs.os.free(e0_str);

    print("type str: {s}\n", .{e0_type_str});
    print("table str: {s}\n", .{e0_table_str});
    print("entity str: {s}\n", .{e0_str});

    {
        const str = api.id(Position).getType().?.string().?;
        defer ecs.os.free(str);
        print("{s}\n", .{str});
    }
    {
        const str = api.id(Position).string().?;
        defer ecs.os.free(str);
        print("{s}\n", .{str});
    }
}

test "zflecs.api.helloworld" {
    print("\n", .{});

    api.init();
    defer api.deinit();

    api.component(Position);
    api.component(Velocity);

    api.tag(Eats);
    api.tag(Apples);

    {
        var qb = api.queryBuilder(&.{});
        const terms = &qb.with(Position).with(Velocity).buildTerms();
        _ = api.addSystemWithFilters("move_system", api.OnUpdate, move, terms);
    }

    const bob = api.namedEntity("Bob");
    _ = bob.set(Position, .{ .x = 0, .y = 0 });
    _ = bob.set(Velocity, .{ .x = 1, .y = 2 });
    bob.addPair(Eats, Apples);

    _ = api.progress(0);
    _ = api.progress(0);

    const p = bob.get(Position).?;
    print("Bob's position is ({d}, {d})\n", .{ p.x, p.y });
}

const Moveable = struct {};

test "zflecs.api.prefab" {
    print("\n", .{});

    api.init();
    defer api.deinit();

    api.component(Position);
    api.component(Velocity);

    const prefab = api.prefab(Moveable)
        .set(Position, .{ .x = 0, .y = 0 })
        .set(Velocity, .{ .x = 2, .y = 1 });

    try expect(prefab.entity != 0);

    const bob = api.namedEntity("Bob").isA(Moveable);

    var p = bob.get(Position).?;
    const v = bob.get(Velocity).?;

    try expect(p.x == 0);
    try expect(p.y == 0);

    try expect(v.x == 2);
    try expect(v.y == 1);
    print("Name: {s}\n", .{@typeName(@TypeOf(v))});

    _ = bob.set(Position, .{ .x = 7, .y = 4 });
    p = bob.get(Position).?;
    try expect(p.x == 7);
    try expect(p.y == 4);

    print("Bob's position is ({d}, {d})\n", .{ p.x, p.y });
}

test "zflecs.api.helloworld_systemcomptime" {
    print("\n", .{});

    api.init();
    defer api.deinit();

    api.component(Position);
    api.component(Velocity);

    api.tag(Eats);
    api.tag(Apples);

    _ = api.addSystem("move system", api.OnUpdate, move_system);
    _ = api.addSystem("move system with iterator", api.OnUpdate, move_system_with_it);

    const bob = api.namedEntity("Bob");
    _ = bob.set(Position, .{ .x = 0, .y = 0 });
    _ = bob.set(Velocity, .{ .x = 1, .y = 2 });
    bob.addPair(Eats, Apples);

    _ = api.progress(0);
    _ = api.progress(0);

    const p = bob.get(Position).?;
    print("Bob's position is ({d}, {d})\n", .{ p.x, p.y });
}
