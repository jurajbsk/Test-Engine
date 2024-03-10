module backend.win32;
version(Windows) @safe nothrow:
import lib.memory;
import lib.memory.list;
import backend.window;
import engine.error;
import engine.primitives;
import engine.graphics.flat;

List!(Window*) windowList = {[null], 1};
enum string winClassName = "LLE";

import lib.sys.windows.user32;
import lib.sys.windows.gdi32;
alias user32 = lib.sys.windows.user32;
alias gdi32 = lib.sys.windows.gdi32;

State initializeWindow(ref Window buffer, const string windowName, void* winInstance) @trusted
{
	if(!windowList[0]) {
		windowList[0] = &buffer;
	}
	else {
		windowList.add(&buffer);
	}

	user32.moduleInit();
	gdi32.moduleInit();
	WindowClassEx windClass = {style:HREDRAW|VREDRAW, windowProc:&windowCallback,
								instance:winInstance, className:&winClassName[0]};
	if(RegisterClassExA(windClass) == 0) return State.Error;

	int ifdef(int x) => (x)? x : USEDEFAULT;
	void* windHandle;
	with(buffer) {
		windHandle = CreateWindowExA(
		0, className:&winClassName[0], windowName:&windowName[0], OVERLAPPEDWINDOW|VISIBLE,
		x:ifdef(position.x), y:ifdef(position.y), width:ifdef(size.x), height:ifdef(size.y), parent:null, menu:null, winInstance, null);
	}
	
	buffer.handle = windHandle;
	return State.OK;
}

State renderWindow(Window wind, Bitmap bitmap)
{
	void* winDC = GetDC(wind.handle);
	_stretchBits(wind.handle, winDC, bitmap);
	ReleaseDC(wind.handle, winDC);

	return State.OK;
}

void _stretchBits(void* winHndl, void* dcHndl, Bitmap bitmap) @trusted
{
	RECT window;
	GetClientRect(winHndl, window);
	with(window)
	{
		StretchDIBits(dcHndl,
						0, 0, right-left, bottom-top,
						0, 0, bitmap.width, bitmap.height,
						imageBits:bitmap.ptr, &bmInfo, BI_RGB, SRCCOPY);
	}
}

bool active = true;
State processMessages()
{
	static Message messageBuffer;
	State errCode;
	while(PeekMessageA(&messageBuffer, null, 0, 0, PeekMessageFlag.REMOVE))
	{
		TranslateMessage(&messageBuffer);
		DispatchMessageA(&messageBuffer);
	}
	if(!active) return State.Exit;
	return State.OK;
}

BITMAPINFO bmInfo;
extern(Windows) long windowCallback(void* winHndl, uint message, ulong wPar, long lPar)
{
	long result = 0;

	Window* windptr;
	foreach(Window* cur; windowList) {
		if(cur.handle == winHndl || cur.handle == null) {
			windptr = cur;
		}
	}

	with(WM) switch(message)
	{
		default: {
			result = DefWindowProcA(winHndl, message, wPar, lPar);
		} break;

		case SIZE: {
			RECT wRect;
			GetClientRect(winHndl, wRect);
			int width, height;
			with(wRect) {
				width = right-left;
				height = bottom-top;
			}
			bmInfo = BITMAPINFO(BITMAPINFOHEADER(width: width, height: height, bitCount: Pixel.sizeof*8, compression:BI_RGB));
			if(windptr.bitmap) {
				windptr.bitmap = Bitmap(realloc(windptr.bitmap, width*height), width, height);
			}
			else windptr.bitmap = Bitmap(malloc!Pixel(width*height), width, height);

			foreach(Func curFunc; windptr.onResize)
			{
				State ret = curFunc();
				if(ret == State.Exit) {
					break;
				}
			}
		} break;

		case DESTROY: {
			active = false;
		} break;

		case CLOSE: {
			active = false;
		} break;

		case PAINT: {
			PAINTSTRUCT paint;
			void* paintHndl = BeginPaint(winHndl, paint);
			EndPaint(winHndl, paint);
		} break;

		case ACTIVATEAPP: {
		} break;

		case SETCURSOR: {
			//SetCursor(null);
		} break;
	}
	return result;
}