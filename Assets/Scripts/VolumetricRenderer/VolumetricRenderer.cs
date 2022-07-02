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
    }

    public bool showOutline = true;
    public Color outlineColor = Color.green;
    void OnDrawGizmosSelected()
    {
        if (showOutline)
        {
            Gizmos.color = outlineColor;
            Gizmos.DrawWireCube(transform.position, Size);
        }
    }

    private static class ShaderPropertyID
    {
        public static readonly int BoxMin = Shader.PropertyToID("_BoxMin");
        public static readonly int BoxMax = Shader.PropertyToID("_BoxMax");
    }

    public Material material;

    [Range(1, 10)]
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

    public void SetupMaterial()
    {
        if (null != material)
        {
            var size = Size * 0.5f;
            var pos = transform.position;
            material.SetVector(ShaderPropertyID.BoxMax, pos + size);
            material.SetVector(ShaderPropertyID.BoxMin, pos - size);
        }
    }
}
