module engine.window;

version(Windows) {
	public import engine.backend.windows :
		bitmap,
		initializeWindow,
		renderWindow,
		processMessages;
}