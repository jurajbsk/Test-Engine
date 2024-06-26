module engine.primitives.vector;

string opError(string op, T, U)()
{
	return "Operator "~op~" cannot be used with types "~T.stringof~" and "~U.stringof;
}

union Vec2(T = float) {
	struct {
		T x;
		T y;
	}
	T[2] arr;
	alias arr this;

	
	void opAssign(T[2] other) {
		arr = other;
	}
	
	Vec2!U opCast(U: Vec2!U)() {
		return Vec2!U(cast(U)x, cast(U)y);
	}
	Vec2!T opBinary(string op, U)(U rhs)
    {
        return Vec2!T(mixin("x", op, "rhs"), mixin("y", op, "rhs"));
    }
	Vec2!T opBinaryRight(string op, U)(U lhs) => opBinary!(op)(lhs);

	enum one = Vec2!T(1,1);
}