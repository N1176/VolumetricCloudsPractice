using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class VolumetricRenderer : MonoBehaviour
{
    public static VolumetricRenderer Instance { get; private set; }
    private void Reset()
    {
        Instance = this;
    }

    void Start()
    {
        Instance = this;
    }

    private void Awake()
    {
        Instance = this;
    }

    private void OnEnable()
    {
        Instance = this;
        SetupMaterial(true);
    }

#if UNITY_EDITOR
    public readonly Vector3[] kGizmosPoints = new Vector3[]{
        new Vector3(-0.5f, -0.5f, -0.5f),
        new Vector3(-0.5f, -0.5f, 0.5f),
        new Vector3(-0.5f, 0.5f, -0.5f),
        new Vector3(-0.5f, 0.5f, 0.5f),
        new Vector3(0.5f, -0.5f, -0.5f),
        new Vector3(0.5f, -0.5f, 0.5f),
        new Vector3(0.5f, 0.5f, -0.5f),
        new Vector3(0.5f, 0.5f, 0.5f),
    };

    public readonly Vector3[] kTransformedGizmosPoints = new Vector3[8];

    private readonly int[] kGizemoLineIndex = new int[] 
    {
        0, 1,
        0, 2,
        0, 4,
        1, 3,
        1, 5,
        2, 3,
        2, 6,
        3, 7,
        4, 5,
        4, 6,
        5, 7,
        6, 7,
    };

    private void OnDrawGizmosSelected()
    {
        Gizmos.color = Color.green;
        var points = kTransformedGizmosPoints;
        for (int i = 0; i < 8; ++i)
        {
            points[i] = transform.TransformPoint(kGizmosPoints[i]);
        }
        for (int i = 0; i < kGizemoLineIndex.Length; i += 2)
        {
            Gizmos.DrawLine(points[kGizemoLineIndex[i]], points[kGizemoLineIndex[i + 1]]);
        }
    }
#endif

    private static class ShaderPropertyID
    {
        public static readonly int BoxW2L = Shader.PropertyToID("_BoxW2L");
        public static readonly int BoxSize = Shader.PropertyToID("_BoxSize");
    }

    public Material material;

    [Range(1, 16)]
    public int downSample = 1;

    public Vector3 BoundingMax
    {
        get
        {
            return transform.position + Size * 0.5f;
        }
    }

    public Vector3 BoundingMin
    {
        get
        {
            return transform.position - Size * 0.5f;
        }
    }

    public Vector3 Size
    {
        get
        {
            var scale = transform.localScale;
            scale.x = Mathf.Abs(scale.x);
            scale.y = Mathf.Abs(scale.y);
            scale.z = Mathf.Abs(scale.z);
            return scale;
        }
    }

    public void SetupMaterial(bool force = false)
    {
        if (null != material)
        {
#if !UNITY_EDITOR
            if (transform.hasChanged || force)
#endif
            { 
                transform.hasChanged = false;
                var size = Size * 0.5f;
                var pos = transform.position;
                var matrix = Matrix4x4.TRS(transform.position, transform.rotation, Vector3.one);
                matrix = matrix.inverse;            
                // material.SetVector(ShaderPropertyID.BoxMax, pos + size);
                // material.SetVector(ShaderPropertyID.BoxMin, pos - size);
                material.SetMatrix(ShaderPropertyID.BoxW2L, matrix);
                material.SetVector(ShaderPropertyID.BoxSize, transform.lossyScale);
            }
        }
    }
}
