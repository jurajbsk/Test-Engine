module engine.graphics.flat.shapes;
import engine.primitives;

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

	import lib.math;
	void Square(Vector2!int pos, uint side, Pixel colour = Pixel(), int outline = 0)
	{
		// TODO: Simplify breaking by first printing colour, then checking x outline for next pixel
		uint d = min(side+pos.y, height-pos.y);
		d = height;
		with(pos)
		for(int i = max(y, 0); i < min(side+y, height); i++)
		{
			bool yinside = cast(int)i+1 > outline+y && i < side-outline+y;
			bool end;
			int xstart = max(x, 0);
			int xend = min(side+x, width);
			for(int j = xstart; j < xend; j++)
			{
				// Empty space inside
				bool xinside = j > outline-1+x;
				if(outline && !end && yinside && xinside) {
					j = xend;
					if(j == width) break;
					else j -= outline;
					//if(x < 0) j += x + outline;
					end = true;
				}

				this[j, i] = colour;
			}
		}
	}
}