using UnityEditor;
using UnityEngine;

[CustomEditor(typeof(VolumetricRenderer))]
public class VolumetricRendererEditor : Editor
{
    private VolumetricRenderer _volumeRenderer;

    // We need to use and to call an instnace of the default MaterialEditor
    private MaterialEditor _materialEditor;

    void OnEnable()
    {
        _volumeRenderer = (VolumetricRenderer)target;

        if (_volumeRenderer.material != null)
        {
            // Create an instance of the default MaterialEditor
            _materialEditor = (MaterialEditor)CreateEditor(_volumeRenderer.material);
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