module engine.time;
public import lib.time : getTicks;
import lib.time;

struct Time {
	ulong frameStart;
	void frameEnd(ulong now) {
		deltaTime = (now - frameStart)/cast(double)getFreq;
		import lib.io;
	}
	double deltaTime = 0;
	debug ulong frameCount;

	void capFrame(double target) nothrow
	{
		if(deltaTime > target) {
			return;
		}
		uint sleepTime = cast(uint)((target - deltaTime)*1000);
		sleep(sleepTime);
	}
}