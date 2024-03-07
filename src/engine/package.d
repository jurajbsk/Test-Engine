module engine;
import lib.memory.list;

@safe pure:

struct GameObject {
	void delegate() OnStart, OnUpdate;
}

struct Scene {
	List!GameObject objlist;

	void Clear()
	{
		objlist.clear();
	}
	void Instantiate(GameObject obj)
	{
		objlist.add(obj);
	}
}

struct SceneLoader() {
	Scene currentScene;
	bool firstLoad = true;
	void Load()(Scene scene)
	{
		if(firstLoad) {
			firstLoad = false;
		}
		else {
			currentScene.Clear();
		}
		currentScene = scene;
	}
}