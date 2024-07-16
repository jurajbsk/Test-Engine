module engine.input;
import engine.primitives;
public import backend.input;

@safe nothrow pure:

struct KeyData {
	bool isDown;
	alias isDown this;
	alias pressed = isDown;
	bool wasDown;
	alias wasPressed = wasDown;
}
bool KeyDown(KeyData key) {
	return key.isDown && !key.wasDown;
}
bool KeyUp(KeyData key) {
	return key.wasDown && !key.isDown;
}

struct Input {
	KeyData[InputMax] keys;
	alias keys this;
	MouseData mouse;
}

// Stuff not covered by 'KeyData' struct
struct MouseData {
	Vec2_u16 position;
	bool dblClick;
}