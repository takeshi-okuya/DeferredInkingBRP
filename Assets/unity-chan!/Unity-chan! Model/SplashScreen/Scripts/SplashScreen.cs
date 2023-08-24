using UnityEngine;
using System.Collections;

namespace UnityChan
{
	[ExecuteInEditMode]
	public class SplashScreen : MonoBehaviour
	{
		void NextLevel ()
		{
			UnityEngine.SceneManagement.SceneManager.LoadScene(Application.loadedLevel + 1);
			//Application.LoadLevel (Application.loadedLevel + 1);
		}
	}
}