module window;
//////////////
import engine.graphics.flat;
import lib.memory;
import error;

__gshared Bitmap bitmap;

version(Windows)
{
	import lib.sys.windows.user32;
	import lib.sys.windows.gdi32;
	alias user32 = lib.sys.windows.user32;
	alias gdi32 = lib.sys.windows.gdi32;

	string winClassName = "TestEngineWindow";

	nothrow:

	void* initializeWindow(string windowName, const void* winInstance, const int[2] size = [USEDEFAULT, USEDEFAULT])
	{
		user32.moduleInit();
		gdi32.moduleInit();

		{
			import lib.sys.windows.advapi32;
			lib.sys.windows.advapi32.moduleInit();
			char* buffer;
			int ssize = 0;
			GetUserNameA(buffer, &ssize);
			buffer = malloc!char(ssize).ptr;
			GetUserNameA(buffer, &ssize);
			windowName = cast(string)buffer[0..ssize];
		}

		immutable WindowClassEx windClass = {style:HREDRAW|VREDRAW, windowProc:&windowCallback,
		                         instance:cast(immutable)winInstance, className:winClassName.ptr};
		if(RegisterClassExA(&windClass) == 0) return null;

		void* windowHandle = CreateWindowExA(
			0, className:winClassName.ptr, windowName:windowName.ptr, OVERLAPPEDWINDOW|VISIBLE,
			x:USEDEFAULT, y:USEDEFAULT, width:size[0], height:size[1], parent:null, menu:null, winInstance, null);

		return windowHandle;
	}

	State renderWindow(void* winHndl)
	{
		void* winDC = GetDC(winHndl);
		_stretchBits(winHndl, winDC);
		ReleaseDC(winHndl, winDC);

		return State.OK;
	}

	void _stretchBits(void* winHndl, void* dcHndl)
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
	extern(Windows) long windowCallback(void* winHndl, uint message, ulong wPar, long lPar) nothrow
	{
		long result = 0;

		switch(message)
		{
			default: {
				result = DefWindowProcA(winHndl, message, wPar, lPar);
			} break;

			case WM.SIZE: {
				RECT wRect;
				GetClientRect(winHndl, wRect);
				int width, height;
				with(wRect) {
					width = right-left;
					height = bottom-top;
				}
				bmInfo = BITMAPINFO(BITMAPINFOHEADER(width: width, height: height, bitCount: Pixel.sizeof*8, compression:BI_RGB));
				if(bitmap) {
					bitmap = Bitmap(realloc(bitmap, width*height), width, height);
				}
				else bitmap = Bitmap(malloc!Pixel(width*height), width, height);
			} break;

			case WM.DESTROY: {
				active = false;
			} break;

			case WM.CLOSE: {
				active = false;
			} break;

			case WM.PAINT: {
				PAINTSTRUCT paint;
				void* paintHndl = BeginPaint(winHndl, &paint);
				//_stretchBits(winHndl, paintHndl);
				EndPaint(winHndl, &paint);
			} break;

			case WM.ACTIVATEAPP: {
			} break;

			case WM.SETCURSOR: {
				//SetCursor(null);
			} break;
		}
		return result;
	}
}