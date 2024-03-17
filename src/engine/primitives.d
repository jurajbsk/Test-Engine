module engine.primitives;

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
}

struct Transform {
	Vector2!() pos;
	alias pos this;
}