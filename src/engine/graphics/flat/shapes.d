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
	ushort width;
	ushort height;

	ref Pixel opIndex(size_t x, size_t y) nothrow pure
	{
		return pixels[x + width*y];
	}
}

import lib.math;
void Square(ref Bitmap bits, Vec2_i16 pos, ushort side, Pixel colour = Pixel(), ushort outline = 0)
{
	// TODO: Simplify breaking by first printing colour, then checking x outline for next pixel
	for(short i = max!short(pos.y, 0); i < min(side+pos.y, bits.height); i++)
	{
		bool yinside = cast(short)i+1 > outline+pos.y && i < side-outline+pos.y;
		bool end;
		short xstart = max!short(pos.x, 0);
		short xend = min!short(cast(short)(side+pos.x), cast(short)bits.width);
		for(short j = xstart; j < xend; j++)
		{
			// Empty space inside
			bool xinside = j > outline-1+pos.x;
			if(outline && !end && yinside && xinside) {
				j = xend;
				if(j == bits.width) break;
				else j -= outline;
				//if(x < 0) j += x + outline;
				end = true;
			}

			bits[j, i] = colour;
		}
	}
}