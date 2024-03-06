module engine.window;

version(Windows) {
	public import engine.backend.windows :
		bitmap,
		WindowUpdate,
		initializeWindow,
		renderWindow,
		processMessages;
}