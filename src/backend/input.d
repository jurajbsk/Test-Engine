module backend.input;

version(Windows) {
	import lib.sys.windows.user32 : VK;

	enum Mouse : ubyte {
		Left = VK.LBUTTON,
		Right = VK.RBUTTON,
		Middle = VK.MBUTTON,
		Button4 = VK.XBUTTON1,
		Button5 = VK.XBUTTON2
	}
	enum Keys : ubyte {
		ControlBreak = VK.CANCEL,
		Backspace = VK.BACK, Tab,
		Clear = VK.CLEAR, Enter,
		Shift = VK.SHIFT, Ctrl, Alt, Pause,
		Esc = VK.ESCAPE,
		Space = VK.SPACE, PageUp, PageDown, End, Home,
		LeftArrow, UpArrow, RightArrow, DownArrow,
		Select, Print, Execute, PrintScreen, Insert, Delete, Help,
		Top0, Top1, Top2, Top3, Top4, Top5, Top6, Top7, Top8, Top9,
		A = 0x41, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
		LHome, RHome, Apps,
		Sleep = VK.SLEEP, Num0, Num1, Num2, Num3, Num4, Num5, Num6, Num7, Num8, Num9,
		NumStar, NumPlus, Separator, NumMinus, NumDot, NumSlash,
		F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12, F13, F14, F15, F16, F17, F18, F19, F20, F21, F22, F23, F24,
		NumLock = VK.NUMLOCK, Scroll,
		LShift = VK.LSHIFT, RShift, LControl, RControl, LAlt, RAlt,
		BrowserBack, BrowserForward, BrowserRefresh, BrowserStop, BrowserSearch, BrowserFavourites, BrowserHome,
		VolumeMute, VolumeDown, VolumeUp, MediaNext, MediaPrev, MediaStop, MediaPlay,
		LaunchMail, LaunchMediaSelect, LaunchApp1, LaunchApp2,
		// "Special" keys named after default symbol on Polish Programmers keyboard (or US keyboard I guess)
		SpecialSemicolon, SpecialPlus, SpecialComma, SpecialMinus, SpecialDot, SpecialSlash, SpecialTilde, // M-mjau~~ ~
		SpecialLeftBracket, SpecialReverseSlash, SpecialRightBracket, SpecialQuotes, SpecialSurprise,
		SpecialAngle
	}
	enum InputMax = 254;
}