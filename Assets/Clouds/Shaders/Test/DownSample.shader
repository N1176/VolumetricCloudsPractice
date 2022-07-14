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

            float3 _BoxSize;
            float4x4 _BoxW2L;
            
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
                float4 uv : TEXCOORD0;          // xy, 屏幕空间的UV； zw，蓝噪声的的uv（保持长宽比）
                float3 rayDirLS : TEXCOORD1;    // 云盒本地空间下的 ray 方向
                float3 rayOriginLS : TEXCOORD2; // 云盒本地空间下的 ray 起点（相机位置）
                float3 lightDirLS : TEXCOORD3;  // 云盒本地空间下的 灯光 方向 （主光源）
            };

            // 计算射线和包围盒的碰撞信息
            // rayOrigin:射线起点
            // invRayDir: 1 / 射线方向
            // return: x:射线走了多远才碰到包围盒，y:射线在包围盒内走了多远。
            // 参考资料: https://jcgt.org/published/0007/03/04/
            float2 InterceptRayBox( float3 rayOrigin, float3 invRayDir)
            {
                float3 boundsMin = -0.5 * _BoxSize;
                float3 boundsMax = 0.5 * _BoxSize;

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
                // 蓝噪声的特性跟单位面积有关，采样时最好保持原图的长宽比。
                o.uv.zw = v.uv * float2(1, _ScreenParams.y / _ScreenParams.x) * _BlueNoiseScale; 

                Light mainLight = GetMainLight();
                float3 lightDir = mainLight.direction;
                o.lightDirLS = mul(_BoxW2L, float4(lightDir, 0)).xyz;
                float3 viewVector = mul(unity_CameraInvProjection, float4(v.uv * 2 - 1, 0, -1)).xyz;
                viewVector = mul(unity_CameraToWorld, float4(viewVector, 0)).xyz;
                o.rayDirLS = mul(_BoxW2L, float4(viewVector, 0)).xyz;
                o.rayOriginLS = mul(_BoxW2L, float4(_WorldSpaceCameraPos.xyz, 1)).xyz;
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                float3 rayDirLS = normalize(i.rayDirLS);
                float2 interception = InterceptRayBox(i.rayOriginLS, 1.0 / rayDirLS);
                float blueNoise = SAMPLE_TEXTURE2D_LOD(_BlueNoise, sampler_2D, i.uv.zw, 0).r;
                return half4(blueNoise.xxxx) * step(EPSILON, interception.y);
            }
            ENDHLSL
        }
    }
}