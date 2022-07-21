using System;
using System.IO;
using UnityEditor;
using UnityEditor.EditorTools;
using UnityEngine;
using Object = UnityEngine.Object;

// Tagging a class with the EditorTool attribute and no target type registers a global tool. Global tools are valid for any selection, and are accessible through the top left toolbar in the editor.
[EditorTool("Weather Map Tool")]
public class WeatherMapEditorTool : EditorTool
{
    // Serialize this value to set a default value in the Inspector.
    [SerializeField]
    Texture2D m_ToolIcon;
    GUIContent m_IconContent;

    public readonly int kWeatherPropID = Shader.PropertyToID("_WeatherMap");
    public readonly int kLayerPropID = Shader.PropertyToID("_Layer");
    public readonly int kActStartPropID = Shader.PropertyToID("_ActStart");
    public readonly int kActEndPropID = Shader.PropertyToID("_ActEnd");
    public readonly int kDeltaPropID = Shader.PropertyToID("_DeltaTime");
    public readonly int kEditorPropID = Shader.PropertyToID("_EditorPamas01");

    private Material cloudMat;
    private string weatherMapPath = null;
    private bool adjustingCamera = false;
    private bool hijackingControl = false;
    private GameObject activeGO = null;
    void OnEnable()
    {
        m_IconContent = new GUIContent()
        {
            image = m_ToolIcon,
            text = "Volumetric Cloud Tool",
            tooltip = "Volumetric Cloud Tool"
        };
    }


    public override GUIContent toolbarIcon
    {
        get { return m_IconContent; }
    }

    //
    // 摘要:
    //     Checks whether the custom editor tool is available based on the state of the
    //     editor.
    //
    // 返回结果:
    //     Returns true if the custom editor tool is available. Returns false otherwise.
    public override bool IsAvailable()
    {
        GameObject go = Selection.activeGameObject;
        if (null != go && Selection.count == 1)
        {
            if (go == activeGO)
            {
                return true;
            }

            var comp = go.GetComponent<VolumetricRenderer>();
            if (null != comp && null != comp.material)
            {
                activeGO = go;
                cloudMat = comp.material;
                var txt = comp.material.GetTexture(kWeatherPropID);
                if (null != txt)
                {
                    weatherMapPath = AssetDatabase.GetAssetPath(txt);
                    CopyWeatherMapToRT();
                }
                else
                {
                    weatherMapPath = AssetDatabase.GetAssetPath(cloudMat);
                }
                return true;
            }
        }

        if (cloudMat != null)
        {
            SaveTexureAndRestoreMat();
        }

        weatherMapPath = null;
        activeGO = null;
        cloudMat = null;
        ReleaseControl();
        return false;
    }

    private WeatherMapEditorToolWindow toolWnd; 
    //
    // 摘要:
    //     Invoked after this EditorTool becomes the active tool.
    public override void OnActivated()
    {
        CreatedRT();
        toolWnd = EditorWindow.GetWindow<WeatherMapEditorToolWindow>();
        toolWnd.onSave = this.SaveTargetRT;
        toolWnd.onLayerChanged = this.OnLayerChanged;
    }

    public void OnLayerChanged(int layer)
    {
        if (null != cloudMat)
        {
            cloudMat.SetInt(kLayerPropID, layer);
        }
    }

    //
    // 摘要: 右键拖动鼠标时，工具临时变成手形工具，这个时候，函数是不会被调用的。
    //     Invoked before this EditorTool stops being the active tool.
    public override void OnWillBeDeactivated()
    {
        ReleaseControl();
        if (cloudMat != null)
        {
            SaveTexureAndRestoreMat();
            cloudMat = null;
            activeGO = null;
            weatherMapPath = null;
        }
        DestroyRT();
    }

    //
    // 摘要:
    //     Use this method to implement a custom editor tool.
    //
    // 参数:
    //   window:
    //     The window that is displaying the custom editor tool.
    public override void OnToolGUI(EditorWindow window)
    {
        if (!(window is SceneView sceneView))
        {
            return;
        }

        var evt = Event.current;
        if (IsAdjustingCamera(evt))
        {
            ReleaseControl();
            return;
        }

        if (!RaycastCloudBox(evt, out var hitInfo))
        {
            return;
        }

        if (activeGO == null)
        {
            return;
        }

        HijackControl();
        if (HandleKeyboardEvent(evt))
        {
            evt.Use();
        }

        if (HandleMouseEvent(evt, hitInfo))
        {
            evt.Use();
        }
        DrawCursour(hitInfo);
    }

    private void HijackControl()
    {
        if (!hijackingControl)
        {
            hijackingControl = true;
            int controlID = GUIUtility.GetControlID(FocusType.Passive);
            GUIUtility.hotControl = controlID;
        }
    }

    private void ReleaseControl()
    {
        if (hijackingControl)
        {
            hijackingControl = false;
            GUIUtility.hotControl = 0;
        }
    }

    // 是否在调整相机位置
    private bool IsAdjustingCamera(Event evt)
    {
        bool curAdjusting = adjustingCamera;
        if (evt.isMouse && evt.button == 1)
        {
            switch (evt.type)
            {
                case EventType.MouseDown:
                    adjustingCamera = true;
                    break;
                case EventType.MouseUp:
                    adjustingCamera = false;
                    break;
                default:
                    break;
            }
        }
        return adjustingCamera || curAdjusting;
    }

    private bool RaycastCloudBox(Event evt, out RaycastHit hitInfo)
    {
        var camera = SceneView.lastActiveSceneView.camera;
        Vector3 mousePos = evt.mousePosition;
        mousePos.y = camera.pixelHeight - mousePos.y;
        mousePos.z = camera.nearClipPlane;
        var ray = camera.ScreenPointToRay(mousePos);
        if (!Physics.Raycast(ray, out hitInfo))
        {
            ReleaseControl();
            return false;
        }

        var hitGo = hitInfo.collider.gameObject;
        if (hitGo != activeGO)
        {
            if (evt.type == EventType.MouseUp && evt.button == 0)
            {
                if (hitGo.GetComponent<VolumetricRenderer>() != null)
                {
                    Selection.activeGameObject = hitGo;
                    Debug.LogError(evt);
                }
            }
            ReleaseControl();
            return false;
        }
        return true;
    }

    private void DrawCursour(RaycastHit hitInfo)
    {
        HandleUtility.AddDefaultControl(-1);
        Handles.color = new Color(0, 1, 0, 1f);
        Handles.DrawLine(hitInfo.point, hitInfo.point + hitInfo.normal * toolWnd.brushRadius);
        Handles.DrawWireDisc(hitInfo.point, hitInfo.normal, toolWnd.brushRadius);
        Handles.color = new Color(0, 1, 1, 0.2f);
        Handles.DrawSolidDisc(hitInfo.point, hitInfo.normal, toolWnd.brushRadius);
    }

    Vector3 lastMousePosition;
    float lastMouseTime; 

    private bool HandleMouseEvent(Event evt, RaycastHit hit)
    {
        if (evt.button == 0)
        {
            var pos = activeGO.transform.InverseTransformPoint(hit.point) + new Vector3(0.5f, 0.5f, 0.5f);
            var time = Time.time;
            switch (evt.type)
            {
                case EventType.MouseDown:
                    lastMousePosition = pos;
                    lastMouseTime = time;
                    return true;
                case EventType.MouseUp:
                    lastMousePosition = Vector3.zero;
                    lastMouseTime = 0;
                    return true;
                case EventType.MouseDrag:
                    ApplyMouseMovement(pos, time);
                    lastMousePosition = pos;
                    lastMouseTime = time;
                    return true;
                default:
                    break;
            }
        }
        return false;
    }

    private bool HandleKeyboardEvent(Event evt)
    {
        if (evt.isKey)
        {
            switch (evt.keyCode)
            {
                case KeyCode.RightBracket:
                    toolWnd.brushRadius *= 1.1f;
                    break;
                case KeyCode.LeftBracket:
                    toolWnd.brushRadius *= 0.9f;
                    break;
                default:
                    break;
            }
            return true;
        }
        return false;
    }

    private RenderTexture rt0 = null;
    private RenderTexture rt1 = null;
    private int targetRtIdx = 0;
    private Material editorMat = null;
    private const int kRtWidth = 512;
    private const int kRtHeight = 512;

    /// <summary>
    /// 创建编辑器的相机很RenderTexture
    /// </summary>
    // 第一版， 各项参数先定死，后面再暴露给UI
    private void CreatedRT()
    {
        if (null == rt0)
        {
            rt0 = new RenderTexture(kRtWidth, kRtHeight, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB);
            rt1 = new RenderTexture(rt0);
            targetRtIdx = 0;
            var shader = Shader.Find("Volumetric/Tools/WeatherMapEditor");
            editorMat = new Material(shader);
        }
    }

    private void DestroyRT()
    {
        if (null != rt0)
        {
            rt0.Release();
            GameObject.DestroyImmediate(rt0);
            rt0 = null;

            rt1.Release();
            GameObject.DestroyImmediate(rt1);
            rt1 = null;

            GameObject.DestroyImmediate(editorMat);
            editorMat = null;
        }
    }

    /// <summary>
    /// 将原始的天气图赋值给RT，并将RT作为材质的纹理
    /// </summary>
    /// <param name="txt">原始贴图</param>
    private void CopyWeatherMapToRT()
    {
        SwapRT();
        var activeRT = RenderTexture.active;
        Graphics.Blit(cloudMat.GetTexture(kWeatherPropID), targetRT, editorMat, 3);
        RenderTexture.active = activeRT;
        tempRT.DiscardContents();
        cloudMat.SetTexture(kWeatherPropID, targetRT);
    }

    /// <summary>
    /// 将鼠标移动丢给材质渲新的天气图
    /// </summary>
    /// <param name="from">UV坐标：鼠标的起点位置</param>
    /// <param name="to">UV坐标：鼠标的终点位置</param>
    private void ApplyMouseMovement(Vector3 to, float deltaTime)
    {
        SwapRT();
        int passIdx = toolWnd.brushActionLayer;// 刚好能跟Shader里Pass的顺序对上
        var activeRT = RenderTexture.active;
        Vector3 scale = activeGO.transform.lossyScale;

        editorMat.SetVector(kActStartPropID, lastMousePosition);
        editorMat.SetVector(kActEndPropID, to);
        editorMat.SetFloat(kDeltaPropID, deltaTime);
        editorMat.SetVector(kEditorPropID, new Vector4(
            toolWnd.brushRadius / Mathf.Min(scale.x, scale.z),
            toolWnd.brushSoftEdge,
            toolWnd.brushHardness,
            0.5f - toolWnd.brushModeIdx
        ));

        Graphics.Blit(tempRT, targetRT, editorMat, passIdx);
        RenderTexture.active = activeRT;
        tempRT.DiscardContents();
        cloudMat.SetTexture(kWeatherPropID, targetRT);
    }

    /// <summary>
    /// 将生成的天气图dump出来，并且还原云材质的天气图设置。
    /// </summary>
    private void SaveTexureAndRestoreMat()
    {
        var path = SaveTargetRT();
        if (null != path)
        { 
            cloudMat.SetTexture(kWeatherPropID, AssetDatabase.LoadAssetAtPath<Texture>(path));
        }
    }

    public string SaveTargetRT()
    {
        var rt = targetRT;
        if (null == rt)
        {
            Debug.LogError("RT为空，保存失败！");
            return null;
        }
        // Texture2D tex = new Texture2D(rt.width, rt.height, TextureFormat.RGBA32, false);
        // RenderTexture.active = rt;
        // tex.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
        // RenderTexture.active = null;
        // var bytes = tex.EncodeToTGA();
        var path = weatherMapPath;
        // if (!path.EndsWith(".tga"))
        // {
        //     path += ".tga";
        // }
        // File.WriteAllBytes(path, bytes);
        // AssetDatabase.ImportAsset(path);
        return path;
    }

    private RenderTexture targetRT
    {
        get
        {
            return targetRtIdx == 0 ? rt0 : rt1;
        }
    }

    private RenderTexture tempRT
    {
        get
        {
            return targetRtIdx == 0 ? rt1 : rt0;
        }
    }

    private void SwapRT()
    {
        targetRtIdx = targetRtIdx == 0 ? 1 : 0;
    }
}