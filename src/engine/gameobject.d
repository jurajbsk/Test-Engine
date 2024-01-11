module engine.gameobject;

enum string[] GameObjFuncs = ["OnStart", "OnFrameUpdate", "OnFixedUpdate"];


/** A standart object in the game */
struct GameObject {
	static foreach(string funcName; GameObjFuncs)
	{
		mixin("void delegate()" ~ funcName ~ ";");
	}
}


void instantiate(T)(GameObject gameobj)
{
}