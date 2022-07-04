using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

public class UIController : MonoBehaviour
{
    public Text text;

    [Range(0.1f, 5)]
    public float updateTime = 0.5f;
    // Start is called before the first frame update
    void Start()
    {
        
    }

    private float time = 0;
    private int frameCount = 0;
    // Update is called once per frame
    void Update()
    {
        time += Time.deltaTime;
        frameCount ++;
        if (time > updateTime)
        {
            text.text = string.Format("{0:0.00}fps, {1:0.0}ms", (float)frameCount/time, Time.deltaTime * 1000); 
            time = 0;
            frameCount = 0;
        }
    }
}
