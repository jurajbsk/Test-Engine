module engine.gameobj;

struct GameObject {
	void delegate() OnStart, OnUpdate;
}

void instantiate(GameObject gameobj)()
{
}
void instantiate(GameObject gameobj)
{
}