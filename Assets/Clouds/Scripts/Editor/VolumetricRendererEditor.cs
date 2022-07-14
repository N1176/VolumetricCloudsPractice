using UnityEditor;
using UnityEditorInternal;
using UnityEngine;

[CustomEditor(typeof(VolumetricRenderer))]
public class VolumetricRendererEditor : Editor
{
    private VolumetricRenderer _volumeRenderer;
    private MaterialEditor _materialEditor;

    private void OnEnable()
    {
        _volumeRenderer = (VolumetricRenderer)target;

        if (_volumeRenderer.material != null)
        {
            // Create an instance of the default MaterialEditor
            _materialEditor = (MaterialEditor)CreateEditor(_volumeRenderer.material);
        }
    }

    private bool isMouseDown = false;
    private void OnSceneGUI()
    {
        if (!Selection.Contains(_volumeRenderer.gameObject))
        {
            return;
        }

        var transform = _volumeRenderer.transform;
        Handles.color = Color.red;


        var camera = SceneView.lastActiveSceneView.camera;
        Event evt = Event.current;
        Vector3 mousePos = evt.mousePosition;
        mousePos.y = camera.pixelHeight - mousePos.y;
        mousePos.z = camera.nearClipPlane;
        var ray = camera.ScreenPointToRay(mousePos);

        if (!Physics.Raycast(ray, out var hitInfo))
        {
            return;
        }

        // if (Mathf.Abs(Mathf.Abs(hitInfo.point.y) - 0.5f) > float.Epsilon)
        // {
        //     return;
        // 
        HandleUtility.AddDefaultControl(-1);
        Handles.color = new Color(0, 1, 0, 1f);
        Handles.DrawLine(hitInfo.point, hitInfo.point + hitInfo.normal * _volumeRenderer._brushRadius);
        Handles.DrawWireDisc(hitInfo.point, hitInfo.normal, _volumeRenderer._brushRadius);
        Handles.color = new Color(0, 1, 1, 0.2f);
        Handles.DrawSolidDisc(hitInfo.point, hitInfo.normal, _volumeRenderer._brushRadius);

        if (evt.button == 0 && evt.alt)
        {
            int controlID = GUIUtility.GetControlID(FocusType.Passive);
            switch (evt.type)
            {
                case EventType.MouseDown:
                    GUIUtility.hotControl = controlID;
                    evt.Use();
                    isMouseDown = true;
                    break;
                case EventType.MouseUp:
                    GUIUtility.hotControl = 0;
                    evt.Use();
                    isMouseDown = false;
                    break;
                case EventType.MouseDrag:
                    GUIUtility.hotControl = controlID;
                    evt.Use();
                    break;
                default:
                    break;
            }
        }
    }

    public bool HasFrameBounds()
    {
        return true;
    }

    public Bounds OnGetFrameBounds()
    {
        var points = _volumeRenderer.kTransformedGizmosPoints;
        Vector3 min = new Vector3(float.MaxValue, float.MaxValue, float.MaxValue);
        Vector3 max = new Vector3(float.MinValue, float.MinValue, float.MinValue);
        for (int i = 0; i < points.Length; ++i)
        {
            var point = points[i];
            max = Vector3.Max(point, max);
            min = Vector3.Min(point, min);
        }
        return new Bounds((min + max) / 2, max - min);
    }


    private int lastMatInstanceID = 0;

    public override void OnInspectorGUI()
    {
        _volumeRenderer._brushRadius = EditorGUILayout.FloatField("Brush Radius", _volumeRenderer._brushRadius);

        EditorGUI.BeginChangeCheck();
        EditorGUILayout.PropertyField(serializedObject.FindProperty("material"));
        EditorGUILayout.PropertyField(serializedObject.FindProperty("downSample"));
        if (EditorGUI.EndChangeCheck())
        {
            serializedObject.ApplyModifiedProperties();

            int curInstID = 0;
            if (_volumeRenderer.material != null)
            {
                curInstID = _volumeRenderer.material.GetInstanceID();
            }

            if (_materialEditor != null && curInstID != lastMatInstanceID)
            {
                // Free the memory used by the previous MaterialEditor
                DestroyImmediate(_materialEditor);
                _materialEditor = null;
                lastMatInstanceID = 0;
            }

            if (_volumeRenderer.material != null && null == _materialEditor)
            {
                // Create a new instance of the default MaterialEditor
                _materialEditor = (MaterialEditor)CreateEditor(_volumeRenderer.material);
                lastMatInstanceID = curInstID;
            }
        }


        if (_materialEditor != null)
        {
            // Draw the material's foldout and the material shader field
            // Required to call _materialEditor.OnInspectorGUI ();
            _materialEditor.DrawHeader();

            //  We need to prevent the user to edit Unity default materials
            bool isDefaultMaterial = !AssetDatabase.GetAssetPath(_volumeRenderer.material).StartsWith("Assets");
            using (new EditorGUI.DisabledGroupScope(isDefaultMaterial))
            {
                // Draw the material properties
                // Works only if the foldout of _materialEditor.DrawHeader () is open
                _materialEditor.OnInspectorGUI();
            }
        }
    }

    void OnDisable()
    {
        if (_materialEditor != null)
        {
            // Free the memory used by default MaterialEditor
            DestroyImmediate(_materialEditor);
            _materialEditor = null;
            lastMatInstanceID = 0;
        }
    }
}