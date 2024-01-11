module main;
////////////
import error;
import window;
version(D_BetterC) {
	version(LDC) pragma(LDC_no_moduleinfo);
}

enum uint fpsCap = 10;
immutable string windowName = "Test Engine";

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
	__gshared RunInfo info;
	version(Windows) {
		import lib.sys.windows.kernel32;
		info.instance = GetModuleHandleA();
	}

	info.windowHndl = initializeWindow(windowName, info.instance);
	State result = info.windowHndl ? State.OK : State.Error;

	import lib.time;
	static Time time;
	enum State function()[] mainFuncsEnum = [
		{time.frame++; time.start = ticks(); return State.OK;},
		&processMessages,
		&testPaint,
		{return renderWindow(info.windowHndl);},
		{return testFpsCap(time);}
	];
	State function()[mainFuncsEnum.length] mainFuncs = mainFuncsEnum;

 	for(ushort i=0; result == State.OK; ++i %= mainFuncs.length)
	{
		result = mainFuncs[i]();
	}

	if(result == State.Error) return getErrorCode();
	debug return result;
	else return State.Exit;
}

State testPaint()
{
	import graphics.structs;
	static ubyte test = 0;
	foreach(ref cur; bitmap)
	{
		static ubyte test2 = 0;
		//cur.red = test;
		//cur.green = cast(ubyte)(test*2);
		//cur.blue = cast(ubyte)(test*3);
		/*switch(test2) {
			case 0: cur.red = test; break;
			case 1: cur.blue = test; break;
			case 2: cur.green = test; break;
			default: break;
		}*/
		union PixelPun{RGBPixel pixel; ubyte[4] colours;}
		(cast(PixelPun*)&cur).colours[(test2+1)%3] = test;

		test++;
		if(test == 0) test2 = (test2+1)%3;
	}
	test++;
	return State.OK;
}
State testFpsCap(Time time)
{
	import lib.time;
	double delay = cast(double)(ticks() - time.start)/freq;
	double target = double(1)/fpsCap;
	if(delay < target) {
		uint sleepT = cast(uint)((target - delay)*1000);
		sleep(sleepT);
	}
	return State.OK;
}