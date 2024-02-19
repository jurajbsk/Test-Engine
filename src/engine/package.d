module engine;
import lib.memory.list;

@safe pure:

struct SceneObject {
	void delegate() OnStart, OnUpdate;
}

struct Scene {
	List!SceneObject objlist;

	void Clear()
	{
		objlist.clear();
	}
	void Instantiate(SceneObject obj)
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