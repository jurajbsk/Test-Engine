module engine.primitives.vector;

alias Vec2_i16 = Vector2!short;
alias Vec2_u16 = Vector2!ushort;
alias Vec2_i32 = Vector2!int;
alias Vec2_u32 = Vector2!uint;
alias Vec2_i64 = Vector2!long;
alias Vec2_u64 = Vector2!ulong;

union Vector2(T = float) {
	struct {
		T x;
		T y;
	}
	T[2] arr;
	alias arr this;

	
	void opAssign(T[2] other) {
		arr = other;
	}
	
	Vector2!U opCast(U : Vector2!U)() const {
		return Vector2!U(cast(U)x, cast(U)y);
	}
	Vector2!T opBinary(string op, U : Vector2)(U rhs)
    {
        return Vector2!T(mixin("x", op, "rhs.x"), mixin("y", op, "rhs.y"));
    }
	Vector2!T opBinary(string op, U)(U rhs)
    {
        return Vector2!T(mixin("x", op, "rhs"), mixin("y", op, "rhs"));
    }
	Vector2!T opBinaryRight(string op, U)(U lhs) => opBinary!(op)(lhs);

	enum one = Vector2!T(1,1);
}