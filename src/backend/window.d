module backend.window;
import engine.error;
import engine.primitives;
import engine.graphics.flat.shapes;
public import engine.input;

alias Func = nothrow State delegate() @safe;
struct Window {
	void* handle;
	Vector2!short size;
	Vector2!short position;
	Func[] onResize;
	bool shouldQuit;
	Input input;
	Bitmap bitmap;
}