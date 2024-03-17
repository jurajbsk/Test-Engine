module backend.win32;
import lib.memory;
import lib.memory.list;
import backend.window;
import engine.error;
import engine.primitives;
import engine.graphics.flat;
import lib.sys.windows.user32;
import lib.sys.windows.gdi32;
alias user32 = lib.sys.windows.user32;
alias gdi32 = lib.sys.windows.gdi32;

version(Windows) @safe nothrow:
List!(Window*) windowList = {[null], 1};
enum string winClassName = "LLE";

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

	Window* window;
	foreach(Window* cur; windowList) {
		if(cur.handle == winHndl || cur.handle == null) {
			window = cur;
		}
	}

	with(WM) switch(message)
	{
		case LBUTTONDOWN, LBUTTONUP, RBUTTONDOWN, RBUTTONUP, MBUTTONDOWN, MBUTTONUP, XBUTTONDOWN, XBUTTONUP: with(Mouse) {
			foreach(i, button; [Left, Right, Keys.Shift, Keys.Ctrl, Middle, Button4, Button5]) {
				window.input[button].wasDown = window.input[button].isDown;
				window.input[button].isDown = cast(bool)(wPar & (1<<i));
			}
			window.input.mouse.position = cast(short[2])[cast(short)lPar, window.size.y - cast(short)(lPar >>> 16)];
		} break;
		case KEYDOWN, KEYUP, SYSKEYDOWN, SYSKEYUP: {
			Keys keycode = cast(Keys) wPar;
			window.input[keycode].wasDown = cast(bool)(lPar & (1<<30));
			window.input[keycode].isDown = cast(bool)(lPar & (1<<31));
			window.input[keycode].wasDown = !!(lPar & (1<<30));
			window.input[keycode].isDown = !(lPar & (1<<31));
		} break;

		case PAINT: {
			PAINTSTRUCT paint;
			void* paintHndl = BeginPaint(winHndl, paint);
			EndPaint(winHndl, paint);
		} break;

		case SETCURSOR: {
			//SetCursor(null);
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
			if(window.bitmap) {
				window.bitmap = Bitmap(realloc(window.bitmap, width*height), width, height);
			}
			else window.bitmap = Bitmap(malloc!Pixel(width*height), width, height);

			foreach(Func curFunc; window.onResize)
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

		case ACTIVATEAPP: {
		} break;

		default: {
			result = DefWindowProcA(winHndl, message, wPar, lPar);
		} break;
	}
	return result;
}