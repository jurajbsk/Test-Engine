module engine.primitives;

struct Vector2(T = float) {
	T x;
	T y;
}

struct Transform {
	Vector2!() pos;
	alias pos this;
}