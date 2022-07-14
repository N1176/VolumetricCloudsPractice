Shader "Volumetric/Test/FlowMap"
{
    Properties
    {
        [NoScaleOffset] _MainTex("Main Tex", 2D) = "white"{}
        [NoScaleOffset] _FlowTex("Flow Tex", 2D) = "white"{}
        _TimeSpeed("Time Speed", float) = 1
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }

        LOD 100
        Cull Back
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
            
            #define EPSILON 0.0001
            #define sampler2d sampler_trilinear_clamp
            SAMPLER(sampler2d);

            sampler2D _MainTex;
            sampler2D _FlowTex;

            float _TimeSpeed;

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
                // float2 vec = i.uv - 0.5;
                // float radis = length(vec);
                // float r = frac((radis - _Bias) / (_Gap + _Thick)) * (_Thick + _Gap) / _Thick;
                // float ratio = step(r, 1) * (1 - abs(0.5 - r));
                // float cosT = dot(uv / radis, float(1, 0)); 

                float2 dir = tex2D(_FlowTex, i.uv).xy * 2.0 - 1.0;
                float phase0 = frac(_Time.x * _TimeSpeed);
                float phase1 = frac(_Time.x * _TimeSpeed + 0.5);

                half3 color0 = tex2D(_MainTex, i.uv - dir * phase0);
                half3 color1 = tex2D(_MainTex, i.uv - dir * phase1);
                float flowLerp = abs(0.5 - phase0) / 0.5;
                return half4(lerp(color0, color1, flowLerp), 1);
            }
            ENDHLSL
        }
    }
}
