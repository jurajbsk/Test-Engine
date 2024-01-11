module graphics.structs;

nothrow pure @safe:

struct Rectangle(T = long) {
	T x; T y;
	T xSize; T ySize;
	alias width = xSize;
	alias height = ySize;
}
struct StretchRectangle(T = long) {
	T left; T top;
	T right; T bottom;
}

struct RGBPixel {
	ubyte blue;
	ubyte green;
	ubyte red;
	ubyte alpha;
}
struct Bitmap {
	RGBPixel[] pixels;
	alias pixels this;
	int width;
	int height;

	RGBPixel opIndex(size_t i, size_t j)
	{
		return pixels[i + width*j];
	}
}