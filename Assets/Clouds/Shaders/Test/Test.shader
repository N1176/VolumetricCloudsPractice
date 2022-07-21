Shader "Volumetric/Test/Test"
{
    Properties
    {
        [NoScaleOffset]_MainTex ("Main Texture", 2D) = "white"{}
        _ScaleX ("ScaleX", Float) = 10
        _ScaleY ("ScaleY", Float) = 10
        // [NoScaleOffset]_VolumeTex("Volume Texture", 2D) = "white"{}
    }
    SubShader
    {
        Tags{"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True" "ShaderModel"="4.5"}
        LOD 300

        Pass
        {
            Name "UpSample"
            Tags{"LightMode" = "UniversalForward"}

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Macros.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            
            #define EPSILON 0.0001
            #define sampler2d sampler_trilinear_mirror
            SAMPLER(sampler2d);

            float _ScaleX;
            float _ScaleY;
            
            TEXTURE2D(_MainTex);
            TEXTURE2D(_VolumeTex);

            struct appdata
            {
                float3 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 posNDC : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.posNDC = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                half4 mainColor = SAMPLE_TEXTURE2D(_MainTex, sampler2d, i.uv + ddy(i.uv) * _ScaleY + ddx(i.uv) * _ScaleX);
                // half4 mainColor = SAMPLE_TEXTURE2D(_MainTex, sampler2d, float2(0.125, 0.625));
                return mainColor;
                // return half4(ddx(i.uv) * _Scale, ddy(i.uv) * _Scale);
            }
            ENDHLSL
        }
    }
}
