Shader "Volumetric/Test/DownSample"
{
    Properties
    {
        _BoxMin ("Box Min", Vector) = (0, 0, 0, 1)
        _BoxMax ("Box Max", Vector) = (1, 1, 1, 1)

        
        [NoScaleOffset]_BlueNoise ("Blue Noise", 2D) = "white" { }
        _BlueNoiseScale("Blue Noise Scale", Range(0.01, 4)) = 1
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


            SAMPLER(sampler_trilinear_repeat);
            
            #define EPSILON 0.0001
            #define sampler_2D sampler_trilinear_repeat
            #define sampler_3D sampler_trilinear_repeat

            float3 _BoxMin;
            float3 _BoxMax;
            
            TEXTURE2D(_BlueNoise);
            float _BlueNoiseScale;

            struct appdata
            {
                float3 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 posNDC : SV_POSITION;
                float4 uv : TEXCOORD0;
                float3 rayDirWS : TEXCOORD1;
            };

            // 计算射线和包围盒的碰撞信息
            // rayOrigin:射线起点
            // invRayDir: 1 / 射线方向
            // return: x:射线走了多远才碰到包围盒，y:射线在包围盒内走了多远。
            // 参考资料: https://jcgt.org/published/0007/03/04/
            float2 InterceptRayBox(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 invRayDir)
            {
                float3 t0 = (boundsMin - rayOrigin) * invRayDir;
                float3 t1 = (boundsMax - rayOrigin) * invRayDir;
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);
                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(min(tmax.x, tmax.y), tmax.z);
                // case 1: ray intersects box from outside (0 <= dstA <= dstB)
                // dstA is dst to nearest intersection, dstB dst to far intersection
                // case 2: ray intersects box from inside (dstA < 0 < dstB)
                // dstA is the dst to intersection behind the ray, dstB is dst to forward intersection
                // case 3: ray misses box (dstA > dstB)
                float dstToBox = max(0, dstA);
                float dstInBox = max(0, dstB - dstToBox);
                return float2(dstToBox, dstInBox);
            }

            v2f vert(appdata v)
            {
                v2f o;
                o.posNDC = TransformObjectToHClip(v.vertex);
                o.uv.xy = v.uv;
                o.uv.zw = v.uv * float2(1, _ScreenParams.y / _ScreenParams.x) * _BlueNoiseScale;
                float4 rayDir = mul(unity_CameraInvProjection, float4(v.uv * 2 - 1, 0, -1));
                rayDir.w = 0;
                o.rayDirWS = mul(unity_CameraToWorld, rayDir).xyz;
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                float3 rayDirWS = normalize(i.rayDirWS);
                float3 rayPosWS = _WorldSpaceCameraPos;
                float2 interception = InterceptRayBox(_BoxMin, _BoxMax, rayPosWS, 1.0 / rayDirWS);
                float blueNoise = SAMPLE_TEXTURE2D_LOD(_BlueNoise, sampler_2D, i.uv.zw, 0).r;
                return half4(blueNoise.xxxx) * step(EPSILON, interception.y);
            }
            ENDHLSL
        }
    }
}
