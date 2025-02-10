/// Idiomatic zig api for the  flecs bindings
const std = @import("std");
const assert = std.debug.assert;
pub const z = @import("zflecs.zig");
pub const os = z.os;

test {
    std.testing.refAllDecls(@This());
}

// NOTE: currently only 1 world at a time is supported
// This is fine because upstream also has this restriction
pub const World = z.world_t;
pub var world: *World = undefined;
var has_world = false;

//--------------------------------------------------------------------------------------------------
//
// Top level functions
//
//--------------------------------------------------------------------------------------------------
pub fn init() void {
    assert(!has_world);
    world = z.init();
    has_world = true;
}

pub fn deinit() void {
    assert(has_world);
    _ = z.fini(world);
    has_world = false;
}

pub fn hasWorld() bool {
    return has_world;
}

pub fn entity() Entity {
    return @bitCast(z.new_id(world));
}

pub fn namedEntity(name: [:0]const u8) Entity {
    return @bitCast(z.set_name(world, 0, name));
}

pub fn prefab(comptime T: type) Entity {
    tag(T);
    const e = id(T);
    e.add(Prefab);
    return e;
}

pub fn prefabId() Entity {
    var e = entity();
    e.add(Prefab);
    return e;
}

pub fn namedPrefab(name: [:0]const u8) Entity {
    return @bitCast(z.new_prefab(world, name));
}

pub fn lookup(name: [*:0]const u8) Entity {
    return @bitCast(z.lookup(world, name));
}

pub fn component(comptime T: type) void {
    z.COMPONENT(world, T);
}

const TypeHooks = z.type_hooks_t;

pub fn componentWithHooks(comptime T: type, hooks: TypeHooks) void {
    if (@sizeOf(T) == 0)
        @compileError("Size of the type must be greater than zero");

    const type_id_ptr = z.perTypeGlobalVarPtr(T);
    if (type_id_ptr.* != 0)
        return;

    z.component_ids_hm.put(type_id_ptr, 0) catch @panic("OOM");

    type_id_ptr.* = z.ecs_component_init(world, &.{
        .entity = z.ecs_entity_init(world, &.{
            .use_low_id = true,
            .name = z.typeName(T),
            .symbol = z.typeName(T),
        }),
        .type = .{
            .alignment = @alignOf(T),
            .size = @sizeOf(T),
            .hooks = hooks,
        },
    });
}

pub fn tag(comptime T: type) void {
    z.TAG(world, T);
}

pub fn id(comptime T: type) Entity {
    return @bitCast(entityFromType(T));
}

pub const Pair = packed struct {
    pair: z.id_t,

    /// Caller must free the returned memory (if it's not null)
    /// Use `@import("zflecs").os.free(str)`
    pub fn string(self: Pair) ?[*:0]u8 {
        return z.id_str(world, self.pair);
    }
};

pub fn pair(comptime First: type, comptime Second: type) Pair {
    return pairId(id(First), id(Second));
}

pub fn pairId(first: Entity, second: Entity) Pair {
    return @bitCast(z.pair(first.entity, second.entity));
}

pub fn setScope(e: Entity) Entity {
    return @bitCast(z.set_scope(world, e.entity));
}

pub fn deferBegin() bool {
    return z.defer_begin(world);
}

pub fn deferEnd() bool {
    return z.defer_end(world);
}

pub fn deferSuspend() void {
    z.defer_suspend(world);
}

pub fn deferResume() void {
    z.defer_resume(world);
}

pub fn isDeferred() bool {
    return z.is_deferred(world);
}

pub fn dim(entity_count: i32) void {
    z.dim(world, entity_count);
}

pub fn clone(dst: Entity, src: Entity, copy: bool) Entity {
    return @bitCast(z.clone(world, dst.entity, src.entity, copy));
}

pub const Ftime = z.ftime_t;

pub fn progress(delta_time: Ftime) bool {
    return z.progress(world, delta_time);
}

pub fn system(name: [:0]const u8, comptime Phase: type, comptime fn_system: anytype) Entity {
    return @bitCast(z.ADD_SYSTEM(world, name, id(Phase).entity, fn_system));
}

pub fn systemWithFilters(name: [:0]const u8, comptime Phase: type, comptime fn_system: anytype, filters: []const Term) Entity {
    return @bitCast(z.ADD_SYSTEM_WITH_FILTERS(world, name, id(Phase).entity, fn_system, filters));
}

//--------------------------------------------------------------------------------------------------
//
// Entities, components and tags
//
//--------------------------------------------------------------------------------------------------
pub const EntityDesc = z.entity_desc_t;

pub const Entity = packed struct {
    pub const invalid: Entity = .{ .entity = 0 };

    entity: u64,

    pub fn deinit(self: Entity) void {
        z.delete(world, self.entity);
    }

    pub fn isAlive(self: Entity) bool {
        return z.is_alive(world, self.entity);
    }

    pub fn isValid(self: Entity) bool {
        return z.is_valid(world, self.entity);
    }

    /// Caller must free the returned memory (if it's not null)
    /// Use `@import("zflecs").os.free(str)`
    pub fn string(self: Entity) ?[*:0]u8 {
        return z.id_str(world, self.entity);
    }

    pub fn entityString(self: Entity) ?[*:0]u8 {
        return z.entity_str(world, self.entity);
    }

    pub fn name(self: Entity) ?[*:0]const u8 {
        return z.get_name(world, self.entity);
    }

    pub fn setName(self: Entity, new_name: []const u8) Entity {
        _ = z.set_name(world, self.entity, new_name);
        return self;
    }

    pub fn add(self: Entity, comptime T: type) void {
        return self.addId(id(T));
    }

    pub fn addId(self: Entity, e: Entity) void {
        z.add_id(world, self.entity, e.entity);
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
        return self.hasId(id(T));
    }

    pub fn hasId(self: Entity, e: Entity) bool {
        return z.has_id(world, self.entity, e.entity);
    }

    pub fn hasPair(self: Entity, comptime First: type, comptime Second: type) bool {
        return self.hasPairId(id(First), id(Second));
    }

    pub fn hasPairId(self: Entity, first: Entity, second: Entity) bool {
        return z.has_pair(world, self.entity, first.entity, second.entity);
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
        z.enable_id(world, self.entity, id(T).entity, true);
    }

    pub fn disableComponent(self: Entity, comptime T: type) void {
        z.enable_id(world, self.entity, id(T).entity, false);
    }

    pub fn addPair(self: Entity, comptime First: type, comptime Second: type) void {
        self.addPairId(id(First), id(Second));
    }

    pub fn addPairId(self: Entity, first: Entity, second: Entity) void {
        z.add_pair(world, self.entity, first.entity, second.entity);
    }

    pub fn removePair(self: Entity, comptime First: type, comptime Second: type) void {
        self.removePairId(id(First), id(Second));
    }

    pub fn removePairId(self: Entity, first: Entity, second: Entity) void {
        z.remove_pair(world, self.entity, first.entity, second.entity);
    }

    pub fn setPair(self: Entity, comptime First: type, comptime Second: type, val: First) void {
        self.setPairId(id(First), id(Second), First, val);
    }

    pub fn setPairSecond(self: Entity, comptime First: type, comptime Second: type, val: Second) void {
        self.setPairId(id(First), id(Second), Second, val);
    }

    pub fn setPairId(self: Entity, first: Entity, second: Entity, comptime T: type, val: T) void {
        z.set_pair(world, self.entity, first.entity, second.entity, T, val);
    }

    pub fn parent(self: Entity) Entity {
        return @bitCast(z.get_parent(world, self.entity));
    }

    pub fn target(self: Entity, comptime T: type, index: i32) Entity {
        z.get_target(world, self.entity, id(T).entity, index);
    }

    pub fn isA(self: Entity, comptime T: type) Entity {
        self.addPair(IsA, T);
        return self;
    }

    pub fn isAnId(self: Entity, e: Entity) Entity {
        self.addPairId(id(IsA), e);
        return self;
    }

    pub fn childOf(self: Entity, comptime T: type) void {
        self.addPair(ChildOf, id(T));
    }

    pub fn childOfId(self: Entity, e: Entity) void {
        self.addPairId(id(ChildOf), e);
    }

    pub fn getType(self: Entity) ?*const EntityType {
        return @ptrCast(z.get_type(world, self.entity));
    }

    pub fn table(self: Entity) ?Table {
        const t: *const z.table_t = z.get_table(world, self.entity) orelse return null;
        return .{ .table = t };
    }

    pub fn owns(self: Entity, comptime T: type) bool {
        return self.ownsId(id(T));
    }

    pub fn ownsId(self: Entity, e: Entity) bool {
        return z.owns_id(world, self.entity, e.entity);
    }
};

pub const singleton = struct {
    pub fn add(comptime T: type) void {
        z.singleton_add(world, T);
    }

    pub fn set(comptime T: type, val: T) void {
        _ = z.singleton_set(world, T, val);
    }

    pub fn remove(comptime T: type) void {
        z.singleton_remove(world, T);
    }

    pub fn get(comptime T: type) ?*const T {
        return z.singleton_get(world, T);
    }

    pub fn getMut(comptime T: type) ?*T {
        return z.singleton_get_mut(world, T);
    }

    pub fn modified(comptime T: type) void {
        z.singleton_modified(world, T);
    }
};

pub const EntityType = struct {
    t: z.type_t,

    /// Caller must free the returned memory (if it's not null)
    /// Use `@import("zflecs").os.free(str)`
    pub fn string(self: *const EntityType) ?[*:0]u8 {
        return z.type_str(world, @ptrCast(self));
    }

    pub fn array(self: *const EntityType) []Entity {
        return self.t.array[0..self.t.count];
    }
};

pub const Table = struct {
    table: *const z.table_t,

    /// Caller must free the returned memory (if it's not null)
    /// Use `@import("zflecs").os.free(str)`
    pub fn string(self: Table) ?[*:0]u8 {
        return z.table_str(world, self.table);
    }
};

//--------------------------------------------------------------------------------------------------
//
// Queries and query iterators
//
//--------------------------------------------------------------------------------------------------
pub fn query(comptime Ts: []const type) !Query {
    if (Ts.len > z.FLECS_TERM_COUNT_MAX) comptime {
        @compileLog(std.fmt.comptimePrint(
            \\query exceeded maximum term count
            \\note: maximum expected length is {}
            \\note: provided length is {}
        , .{ z.FLECS_TERM_COUNT_MAX, Ts.len }));
    };
    var desc = z.query_desc_t{};
    inline for (Ts, 0..) |T, i| {
        desc.terms[i].id = id(T).entity;
    }
    const q = try z.query_init(world, &desc);
    return .{ .query = q };
}

pub fn queryBuilder(comptime Ts: []const type) QueryBuilder {
    return QueryBuilder.init(Ts);
}

pub const Query = packed struct {
    query: *z.query_t,

    pub fn deinit(self: Query) void {
        z.query_fini(self.query);
    }

    pub fn iter(self: Query) QueryIter {
        return .{ .it = z.query_iter(world, self.query) };
    }

    pub fn each(self: Query, comptime f: anytype) void {
        const Q = QueryImpl(f);
        const it = self.iter().it;

        z.table_lock(it.table);
        defer z.table_unlock(it.table);

        while (z.query_next(&it)) {
            Q.exec(&it);
        }
    }
};

pub const InoutKind = z.inout_kind_t;
pub const OperKind = z.oper_kind_t;
pub const Term = z.term_t;

pub const QueryBuilder = struct {
    terms: [z.FLECS_TERM_COUNT_MAX]z.term_t = [_]z.term_t{.{}} ** z.FLECS_TERM_COUNT_MAX,
    current: z.term_t = .{},
    index: i8 = -1,

    pub fn init(comptime Ts: []const type) QueryBuilder {
        if (Ts.len > z.FLECS_TERM_COUNT_MAX) {
            @compileError(std.fmt.comptimePrint(
                \\query exceeded maximum term count
                \\note: maximum expected length is {}
                \\note: provided length is {}
            , .{ z.FLECS_TERM_COUNT_MAX, Ts.len }));
        }
        var self: QueryBuilder = .{};
        inline for (Ts) |T| {
            _ = self.with(T);
        }
        return self;
    }

    pub fn term(self: *QueryBuilder) *QueryBuilder {
        if (self.index != -1) {
            self.terms[@intCast(self.index)] = self.current;
            self.current = .{}; // ensure default state
        }
        self.index += 1;
        assert(self.index < z.FLECS_TERM_COUNT_MAX);
        return self;
    }

    pub fn with(self: *QueryBuilder, comptime T: type) *QueryBuilder {
        _ = self.term();
        self.current.id = id(T).entity;
        if (@typeInfo(T) == .optional) {
            self.current.oper = .Optional;
        }
        return self;
    }

    pub fn withId(self: *QueryBuilder, e: Entity) *QueryBuilder {
        _ = self.term();
        self.current.id = e.entity;
        return self;
    }

    pub fn withPair(self: *QueryBuilder, comptime First: type, comptime Second: type) *QueryBuilder {
        _ = self.term();
        self.current.first.id = id(First).entity;
        self.current.second.id = id(Second).entity;
        return self;
    }

    pub fn withPairFirst(self: *QueryBuilder, comptime First: type, second: Entity) *QueryBuilder {
        _ = self.term();
        self.current.first.id = id(First).entity;
        self.current.second.id = second.entity;
        return self;
    }

    pub fn withPairId(self: *QueryBuilder, first: Entity, second: Entity) *QueryBuilder {
        _ = self.term();
        self.current.first.id = first.entity;
        self.current.second.id = second.entity;
        return self;
    }

    pub fn setFirst(self: *QueryBuilder, comptime First: type) *QueryBuilder {
        self.current.first.id = id(First).entity;
        return self;
    }

    pub fn setFirstId(self: *QueryBuilder, first: Entity) *QueryBuilder {
        self.current.first.id = first.entity;
        return self;
    }

    pub fn setFirstName(self: *QueryBuilder, name: [:0]const u8) *QueryBuilder {
        self.current.first.name = name;
        return self;
    }

    pub fn setSecond(self: *QueryBuilder, comptime Second: type) *QueryBuilder {
        self.current.second.id = id(Second).entity;
        return self;
    }

    pub fn setSecondId(self: *QueryBuilder, second: Entity) *QueryBuilder {
        self.current.second.id = second.entity;
        return self;
    }

    pub fn setSecondName(self: *QueryBuilder, name: [:0]const u8) *QueryBuilder {
        self.current.second.name = name;
        return self;
    }

    pub fn inoutKind(self: *QueryBuilder, kind: InoutKind) *QueryBuilder {
        self.current.inout = kind;
        return self;
    }

    pub fn in(self: *QueryBuilder) *QueryBuilder {
        self.current.inout = .In;
        return self;
    }

    pub fn out(self: *QueryBuilder) *QueryBuilder {
        self.current.inout = .Out;
        return self;
    }

    pub fn inout(self: *QueryBuilder) *QueryBuilder {
        self.current.inout = .InOut;
        return self;
    }

    pub fn inoutNone(self: *QueryBuilder) *QueryBuilder {
        self.current.inout = .InOutNone;
        return self;
    }

    pub fn oper(self: *QueryBuilder, kind: OperKind) *QueryBuilder {
        self.current.oper = kind;
        return self;
    }

    pub fn and_(self: *QueryBuilder) *QueryBuilder {
        self.current.oper = .And;
        return self;
    }

    pub fn or_(self: *QueryBuilder) *QueryBuilder {
        self.current.oper = .Or;
        return self;
    }

    pub fn not(self: *QueryBuilder) *QueryBuilder {
        self.current.oper = .Not;
        return self;
    }

    pub fn without(self: *QueryBuilder, comptime T: type) *QueryBuilder {
        _ = self.term();
        self.current.id = id(T).entity;
        self.current.oper = .Not;
        return self;
    }

    pub fn withoutId(self: *QueryBuilder, e: Entity) *QueryBuilder {
        _ = self.term();
        self.current.id = e.entity;
        self.current.oper = .Not;
        return self;
    }

    pub fn optional(self: *QueryBuilder) *QueryBuilder {
        self.current.oper = .Optional;
        return self;
    }

    pub fn isName(self: *QueryBuilder) *QueryBuilder {
        self.current.second.id = z.IsName;
        return self;
    }

    pub fn andFrom(self: *QueryBuilder) *QueryBuilder {
        self.current.oper = .AndFrom;
        return self;
    }

    pub fn orFrom(self: *QueryBuilder) *QueryBuilder {
        self.current.oper = .OrFrom;
        return self;
    }

    pub fn notFrom(self: *QueryBuilder) *QueryBuilder {
        self.current.oper = .NotFrom;
        return self;
    }

    pub fn scopeOpen(self: *QueryBuilder) *QueryBuilder {
        _ = self.term();
        self.current.id = id(ScopeOpen).entity;
        self.current.src.id = .IsEntity;
        return self;
    }

    pub fn scopeClose(self: *QueryBuilder) *QueryBuilder {
        _ = self.term();
        self.current.id = id(ScopeClose).entity;
        self.current.src.id = .IsEntity;
        return self;
    }

    pub fn src(self: *QueryBuilder, comptime T: type) *QueryBuilder {
        self.current.src.id = id(T).entity;
        return self;
    }

    pub fn srcId(self: *QueryBuilder, e: Entity) *QueryBuilder {
        self.current.src.id = e.entity;
        return self;
    }

    pub fn singleton(self: *QueryBuilder) *QueryBuilder {
        self.current.src.id = self.current.id;
        return self;
    }

    pub fn self_(self: *QueryBuilder, comptime T: type) *QueryBuilder {
        self.current.src.id |= z.Self;
        self.current.trav = id(T);
        return self;
    }

    pub fn up(self: *QueryBuilder, comptime T: type) *QueryBuilder {
        self.current.src.id |= z.Up;
        self.current.trav = id(T);
        return self;
    }

    pub fn parent(self: *QueryBuilder) *QueryBuilder {
        return self.up(ChildOf);
    }

    pub fn cascade(self: *QueryBuilder, comptime T: type) *QueryBuilder {
        self.current.src.id |= z.Cascade;
        self.current.trav = id(T);
        return self;
    }

    pub fn descend(self: *QueryBuilder, comptime T: type) *QueryBuilder {
        self.current.src.id = z.Desc;
        self.current.trav = id(T);
        return self;
    }

    pub fn build(self: *QueryBuilder) !Query {
        assert(self.index < z.FLECS_TERM_COUNT_MAX);
        self.terms[@intCast(self.index)] = self.current;

        var desc = z.query_desc_t{};
        desc.terms = self.terms;
        const q = try z.query_init(world, &desc);
        return .{ .query = q };
    }

    pub fn buildTerms(self: *QueryBuilder) [z.FLECS_TERM_COUNT_MAX]Term {
        assert(self.index < z.FLECS_TERM_COUNT_MAX);
        self.terms[@intCast(self.index)] = self.current;
        return self.terms;
    }
};

pub const QueryIter = struct {
    it: Iter,

    pub fn field(self: *QueryIter, comptime T: type, index: i32) ?[]T {
        return z.field(&self.it, T, index);
    }

    pub fn next(self: *QueryIter) bool {
        return z.query_next(&self.it);
    }

    pub fn count(self: QueryIter) usize {
        return self.it.count();
    }

    pub fn entities(self: QueryIter) []const Entity {
        return @ptrCast(self.it.entities());
    }
};

pub const Iter = z.iter_t;

fn QueryImpl(comptime fn_query: anytype) type {
    const fn_type = @typeInfo(@TypeOf(fn_query));
    if (fn_type.@"fn".params.len == 0) {
        @compileError("Query needs at least one parameter");
    }

    return struct {
        fn exec(it: *Iter) callconv(.C) void {
            const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(fn_query));
            var args_tuple: ArgsTupleType = undefined;

            const has_it_param = fn_type.@"fn".params[0].type == *Iter;
            if (has_it_param) {
                args_tuple[0] = it;
            }

            const start_index = if (has_it_param) 1 else 0;

            inline for (start_index..fn_type.@"fn".params.len) |i| {
                const p = fn_type.@"fn".params[i];
                args_tuple[i] = z.field(it, @typeInfo(p.type.?).pointer.child, i - start_index).?;
            }

            // NOTE: .always_inline seems ok, but unsure. Replace to .auto if it breaks
            _ = @call(.always_inline, fn_query, args_tuple);
        }
    };
}

//--------------------------------------------------------------------------------------------------
//
// Types for special entities
//
//--------------------------------------------------------------------------------------------------

// pub const Query = struct {};
pub const Observer = struct {};
pub const System = struct {};
pub const Flecs = struct {};
pub const FlecsCore = struct {};
// pub const World = struct {};
pub const Wildcard = struct {};
pub const Any = struct {};
pub const This = struct {};
pub const Variable = struct {};
pub const Transitive = struct {};
pub const Reflexive = struct {};
pub const Final = struct {};
pub const OnInstantiate = struct {};
pub const Override = struct {};
pub const Inherit = struct {};
pub const DontInherit = struct {};
pub const Symmetric = struct {};
pub const Exclusive = struct {};
pub const Acyclic = struct {};
pub const Traversable = struct {};
pub const With = struct {};
pub const OneOf = struct {};
pub const CanToggle = struct {};
pub const Trait = struct {};
pub const Relationship = struct {};
pub const Target = struct {};
pub const PairIsTag = struct {};
pub const Name = struct {};
pub const Symbol = struct {};
pub const Alias = struct {};
pub const ChildOf = struct {};
pub const IsA = struct {};
pub const DependsOn = struct {};
pub const SlotOf = struct {};
pub const Module = struct {};
pub const Private = struct {};
pub const Prefab = struct {};
pub const Disabled = struct {};
pub const NotQueryable = struct {};
pub const OnAdd = struct {};
pub const OnRemove = struct {};
pub const OnSet = struct {};
pub const Monitor = struct {};
pub const OnTableCreate = struct {};
pub const OnTableDelete = struct {};
pub const OnDelete = struct {};
pub const OnDeleteTarget = struct {};
pub const Remove = struct {};
pub const Delete = struct {};
pub const Panic = struct {};
pub const Sparse = struct {};
pub const Union = struct {};
pub const PredEq = struct {};
pub const PredMatch = struct {};
pub const PredLookup = struct {};
pub const ScopeOpen = struct {};
pub const ScopeClose = struct {};
pub const Empty = struct {};

pub const OnStart = struct {};
pub const PreFrame = struct {};
pub const OnLoad = struct {};
pub const PostLoad = struct {};
pub const PreUpdate = struct {};
pub const OnUpdate = struct {};
pub const OnValidate = struct {};
pub const PostUpdate = struct {};
pub const PreStore = struct {};
pub const OnStore = struct {};
pub const PostFrame = struct {};
// pub const Phase = struct {};

fn entityFromType(comptime T: type) z.entity_t {
    return switch (T) {
        // Query => z.Query,
        Observer => z.Observer,
        System => z.System,
        Flecs => z.Flecs,
        FlecsCore => z.FlecsCore,
        // World => z.World,
        Wildcard => z.Wildcard,
        Any => z.Any,
        This => z.This,
        Variable => z.Variable,
        Transitive => z.Transitive,
        Reflexive => z.Reflexive,
        Final => z.Final,
        OnInstantiate => z.OnInstantiate,
        Override => z.Override,
        Inherit => z.Inherit,
        DontInherit => z.DontInherit,
        Symmetric => z.Symmetric,
        Exclusive => z.Exclusive,
        Acyclic => z.Acyclic,
        Traversable => z.Traversable,
        With => z.With,
        OneOf => z.OneOf,
        CanToggle => z.CanToggle,
        Trait => z.Trait,
        Relationship => z.Relationship,
        Target => z.Target,
        PairIsTag => z.PairIsTag,
        Name => z.Name,
        Symbol => z.Symbol,
        Alias => z.Alias,
        ChildOf => z.ChildOf,
        IsA => z.IsA,
        DependsOn => z.DependsOn,
        SlotOf => z.SlotOf,
        Module => z.Module,
        Private => z.Private,
        Prefab => z.Prefab,
        Disabled => z.Disabled,
        NotQueryable => z.NotQueryable,
        OnAdd => z.OnAdd,
        OnRemove => z.OnRemove,
        OnSet => z.OnSet,
        Monitor => z.Monitor,
        OnTableCreate => z.OnTableCreate,
        OnTableDelete => z.OnTableDelete,
        OnDelete => z.OnDelete,
        OnDeleteTarget => z.OnDeleteTarget,
        Remove => z.Remove,
        Delete => z.Delete,
        Panic => z.Panic,
        Sparse => z.Sparse,
        Union => z.Union,
        PredEq => z.PredEq,
        PredMatch => z.PredMatch,
        PredLookup => z.PredLookup,
        ScopeOpen => z.ScopeOpen,
        ScopeClose => z.ScopeClose,
        Empty => z.Empty,
        OnStart => z.OnStart,
        PreFrame => z.PreFrame,
        OnLoad => z.OnLoad,
        PostLoad => z.PostLoad,
        PreUpdate => z.PreUpdate,
        OnUpdate => z.OnUpdate,
        OnValidate => z.OnValidate,
        PostUpdate => z.PostUpdate,
        PreStore => z.PreStore,
        OnStore => z.OnStore,
        PostFrame => z.PostFrame,
        // Phase => z.Phase,
        else => z.id(T),
    };
}
