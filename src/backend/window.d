module backend.window;
import engine.error;
import engine.primitives;
import engine.graphics.flat.shapes;

alias Func = nothrow State delegate() @safe;
struct Window {
	void* handle;
	Vector2!int size;
	Vector2!int position;
	Func[] onResize;
	Bitmap bitmap;
	bool shouldQuit;
}