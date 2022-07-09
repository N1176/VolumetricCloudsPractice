Shader "Volumetric/Test/UpSample"
{
    Properties
    {
        _BoxMin ("Box Min", Vector) = (0, 0, 0, 1)
        _BoxMax ("Box Max", Vector) = (1, 1, 1, 1)

        [NoScaleOffset]_MainTex ("Main Texture", 2D) = "white"{}
        // [NoScaleOffset]_VolumeTex("Volume Texture", 2D) = "white"{}
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }

        LOD 100
        Cull Off
        ZWrite Off
        ZTest Always

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Macros.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            SAMPLER(sampler_trilinear_clamp);
            
            #define EPSILON 0.0001
            #define sampler2d sampler_trilinear_clamp

            float3 _BoxMin;
            float3 _BoxMax;
            
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
                o.uv.xy = v.uv;
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                half4 mainColor = SAMPLE_TEXTURE2D_LOD(_MainTex, sampler2d, i.uv, 0);
                half4 volumeColor = SAMPLE_TEXTURE2D_LOD(_VolumeTex, sampler2d, i.uv, 0);
                return half4(volumeColor.xxx, 1.0);
                return half4(lerp(mainColor.rgb, volumeColor.rgb, volumeColor.a), 1.0);
            }
            ENDHLSL
        }
    }
}
