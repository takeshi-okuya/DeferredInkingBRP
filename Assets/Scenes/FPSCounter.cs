using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

public class FPSCounter : MonoBehaviour
{
    public TMPro.TextMeshProUGUI text;
    public WCGL.DeferredInkingCamera deferredInkingCamera;

    float preTime = 0;
    int frameCount;

    private void Start()
    {
        text.text = "000";
    }

    void Update()
    {
        frameCount++;
        float time = Time.time;

        if (preTime == 0)
        {
            preTime = time;
            frameCount = 0;
        }
        else if (time - preTime > 1.0f)
        {
            float fps = frameCount / (time - preTime);
            text.text = fps.ToString();

            preTime = time;
            frameCount = 0;
        }

        if(Input.GetKey(KeyCode.UpArrow))
        {
            deferredInkingCamera.enabled = true;
        }
        else if (Input.GetKey(KeyCode.DownArrow))
        {
            deferredInkingCamera.enabled = false;
        }

        if (Input.GetKey(KeyCode.Escape))
        {
            UnityEngine.Application.Quit();
        }

    }
}
