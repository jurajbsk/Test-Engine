module main;
////////////
import error;
import engine.window;
version(D_BetterC) {
	version(LDC) pragma(LDC_no_moduleinfo);
}

enum uint fpsCap = 10;
enum string windowName = "Test Engine";

struct RunInfo {
	void* instance;
	void* windowHndl;
	//char* args;
}
struct Time {
	ulong frame;
	ulong start;
}

version(Windows) {
	import lib.sys.windows.winmain;
	mixin WinMain;
}

extern(C) int main()
{
	RunInfo info;
	version(Windows) {
		import lib.sys.windows.kernel32;
		info.instance = GetModuleHandleA();
	}

	info.windowHndl = initializeWindow(windowName, info.instance);
	State result = info.windowHndl ? State.OK : State.Error;

	import lib.time;
	Time time;
	alias FuncType = State delegate();
	enum FuncType[] _mainFuncs = [
		{time.frame++; time.start = ticks(); return State.OK;},
		{return processMessages();},
		{return testFpsCap(time);},
		{return testPaint();},
		{return renderWindow(info.windowHndl);},
	];
	scope FuncType[_mainFuncs.length] mainFuncs = _mainFuncs;
	// Functions for when the window is resized
	WindowUpdate = cast(State delegate() nothrow[])mainFuncs[2..$];

 	for(ushort i=0; result == State.OK; ++i %= mainFuncs.length)
	{
		result = mainFuncs[i]();
	}

	// Exiting
	if(result == State.Error) return getErrorCode();
	debug return result;
	else return State.Exit;
}

State testPaint()
{
	import engine.graphics.flat.shapes;

	static ubyte test = 0;
	foreach(ref cur; bitmap)
	{
		static ubyte test2 = 0;
		union PixelPun{Pixel pixel; ubyte[4] colours;}
		(cast(PixelPun*)&cur).colours[(test2+1)%3] = test;

		test++;
		if(test == 0) test2 = (test2+1)%3;
	}
	test++;
	bitmap.pixels[] = Pixel();

	import engine.parts;
	with(bitmap) {
		uint d = height;
		Square(Vector2_32(width-200, height-200), 200, Pixel(255,255,255,0), 2);
		Square(Vector2_32(200, 200), 100, Pixel(255,255,255,0), 2);
	}
	return State.OK;
}

import lib.time;
State testFpsCap(Time time)
{
	double delay = cast(double)(ticks() - time.start)/freq;
	enum double target = double(1)/fpsCap;
	if(delay < target) {
		uint sleepTime = cast(uint)((target - delay)*1000);
		sleep(sleepTime);
	}
	return State.OK;
}