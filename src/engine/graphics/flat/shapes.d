module engine.graphics.flat.shapes;
import engine.parts;

nothrow pure @safe:

struct Pixel {
	ubyte blue;
	ubyte green;
	ubyte red;
	ubyte alpha;
}
struct Bitmap {
	Pixel[] pixels;
	alias pixels this;
	int width;
	int height;

	ref Pixel opIndex(size_t x, size_t y) nothrow pure
	{
		return pixels[x + width*y];
	}
}