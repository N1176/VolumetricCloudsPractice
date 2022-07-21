using System;
using UnityEditor;
using UnityEngine;

public class WeatherMapEditorToolWindow : EditorWindow
{
    public Action<int> onLayerChanged = null;
    public Func<string> onSave = null;

    public int brushActionLayer = 0;
    public int brushModeIdx = 0;
    public float brushRadius = 1;
    public float brushSoftEdge = 0.5f;
    public float brushHardness = 0.5f;

    private readonly string[] kActions = new string[] { "Density", "Height", "Flow Map" };
    private readonly string[] kBrushModes = new string[] { "+", "-" };

    private void OnGUI()
    {
        GUILayout.Label("Layers", EditorStyles.boldLabel);

        // 图层
        int lastIdx = brushActionLayer;
        brushActionLayer = GUILayout.Toolbar(brushActionLayer, kActions);
        if (null != onLayerChanged && lastIdx != brushActionLayer)
        {
            onLayerChanged(brushActionLayer);
        }

        // 笔刷是加还是减
        brushModeIdx = GUILayout.Toolbar(brushModeIdx, kBrushModes);

        // 笔刷半径
        brushRadius = EditorGUILayout.FloatField("Brush Radius", brushRadius);

        // 笔刷软边
        brushSoftEdge = EditorGUILayout.Slider("Brush Soft Edge", brushSoftEdge, 0, 1);

        // 笔刷硬度
        brushHardness = EditorGUILayout.Slider("Brush Hardness", brushHardness, 0, 1);

        // 保存按钮
        if (null != onSave && GUILayout.Button("Save Texture") )
        {
            onSave();
        }
    }
}