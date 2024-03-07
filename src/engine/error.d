module engine.error;

enum State {
	Exit = 0,
	OK,
	Error
}
static assert(State.OK != State.Exit);

int getErrorCode()
{
	version(Windows) return GetLastError();
}

version(Windows) extern(Windows) {
	uint GetLastError() nothrow;
}