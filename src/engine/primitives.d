module engine.primitives;

union Vector2(T = float) {
	T[2] pos;
	alias pos this;
	struct {
		T x;
		T y;
	}
}

struct Transform {
	Vector2!() pos;
	alias pos this;
}