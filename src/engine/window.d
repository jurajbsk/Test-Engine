module engine.window;

version(Windows) {
	public import backend.win32 :
		bitmap,
		WindowUpdate,
		initializeWindow,
		renderWindow,
		processMessages;
}