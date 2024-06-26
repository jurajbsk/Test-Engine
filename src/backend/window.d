module backend.window;
import engine.error;
import engine.primitives;
import engine.graphics.flat.shapes;
public import engine.input;

alias Func = State delegate();
struct Window {
	Vec2!short size;
	Vec2!short position;

	void* handle;
	Func[] onResize;
	bool shouldQuit;
	Input input;
	Bitmap bitmap;
}