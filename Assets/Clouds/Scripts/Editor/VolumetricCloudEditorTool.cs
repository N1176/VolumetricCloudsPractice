using System;
using UnityEditor;
using UnityEditor.EditorTools;
using UnityEngine;

// Tagging a class with the EditorTool attribute and no target type registers a global tool. Global tools are valid for any selection, and are accessible through the top left toolbar in the editor.
[EditorTool("Volumetric Cloud Tool")]
class VolumetricCloudTool : EditorTool
{
    // Serialize this value to set a default value in the Inspector.
    [SerializeField]
    Texture2D m_ToolIcon;
    GUIContent m_IconContent;

    private float brushRadius = 1;
    public readonly int kWeatherPropID = Shader.PropertyToID("_WeatherMap");

    private Material material;
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
                var txt = comp.material.GetTexture(kWeatherPropID);
                if (null != txt)
                {
                    weatherMapPath = AssetDatabase.GetAssetPath(txt);
                    activeGO = go;
                    material = comp.material;
                    return true;
                }
            }
        }

        activeGO = null;
        material = null;
        ReleaseControl();
        return false;
    }

    //
    // 摘要:
    //     Invoked after this EditorTool becomes the active tool.
    public override void OnActivated()
    {

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

        DrawGUI(sceneView);

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
        if (HandleMouseEvent(evt))
        {
            evt.Use();
        }
        DrawCursour(hitInfo);
    }
    //
    // 摘要:
    //     Invoked before this EditorTool stops being the active tool.
    public override void OnWillBeDeactivated()
    {
        ReleaseControl();
        //TODO: Save Texture
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
        Handles.DrawLine(hitInfo.point, hitInfo.point + hitInfo.normal * brushRadius);
        Handles.DrawWireDisc(hitInfo.point, hitInfo.normal, brushRadius);
        Handles.color = new Color(0, 1, 1, 0.2f);
        Handles.DrawSolidDisc(hitInfo.point, hitInfo.normal, brushRadius);
    }

    private bool HandleMouseEvent(Event evt)
    {
        if (evt.button == 0)
        {
            switch (evt.type)
            {
                case EventType.MouseDown:
                    return true;
                case EventType.MouseUp:
                    return true;
                case EventType.MouseDrag:
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
                    brushRadius *= 1.1f;
                    break;
                case KeyCode.LeftBracket:
                    brushRadius *= 0.9f;
                    break;
                default:
                    break;
            }
            return true;
        }
        return false;
    }

    private readonly string[] kActions = new string[] { "Density", "Height", "Flow" };
    private int actionIdx = 0;
    private readonly string[] kBrushModes = new string[] { "+", "-" };
    private int modeIdx = 0;
    private void DrawGUI(SceneView sceneView)
    {
        var svSize = new Vector2(sceneView.camera.pixelWidth, sceneView.camera.pixelHeight);
        Handles.BeginGUI();
        const float kUIWidth = 200;
        const float kUIHeight = 90;
        GUILayout.BeginArea(new Rect(svSize.x - kUIWidth - 5, svSize.y - kUIHeight - 5, kUIWidth, kUIHeight));
        actionIdx = GUILayout.Toolbar(actionIdx, kActions);
        modeIdx = GUILayout.Toolbar(modeIdx, kBrushModes);
        brushRadius = EditorGUILayout.FloatField("Brush Radius", brushRadius);
        if (GUILayout.Button("Save Texture"))
        {
            //TODO: 保存纹理
        }
        GUILayout.EndArea();
        Handles.EndGUI();
    }
}