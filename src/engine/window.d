module engine.window;

public import backend.window;
version(Windows) {
	public import backend.win32 :
		initializeWindow,
		renderWindow,
		processMessages;
}