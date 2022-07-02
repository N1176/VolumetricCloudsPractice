Shader "Volumetric/Cloud"
{
    Properties
    {
        [MainTexture][NoScaleOffset] _MainTex ("MainTex", 2D) = "white" { }
        _BoxMin ("Box Min", Vector) = (0, 0, 0, 1)
        _BoxMax ("Box Max", Vector) = (1, 1, 1, 1)

        [NoScaleOffset]_ShapeNoise ("Shape Noise", 3D) = "white" { }
        _ShapeScale ("Worley Scale", Vector) = (1, 1, 1)
        [NoScaleOffset]_DetailNoise ("Worley Noise", 3D) = "white" { }
        _DetailScale ("Worley Scale", Vector) = (1, 1, 1)
        [NoScaleOffset]_BlueNoise ("Blue Noise", 2D) = "white" { }
        [NoScaleOffset]_WeatherMap ("Weather Map", 2D) = "white" { }
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

            TEXTURE2D(_MainTex);

            half4 _MainColor;
            
            TEXTURE3D(_ShapeNoise);
            float4 _ShapeScale;

            TEXTURE3D(_DetailNoise);
            float4 _DetailScale;
            
            TEXTURE2D(_BlueNoise);
            TEXTURE2D(_WeatherMap);

            SAMPLER(sampler_trilinear_repeat);
            
            #define EPSILON 0.0001
            #define sampler_2D sampler_trilinear_repeat
            #define sampler_3D sampler_trilinear_repeat


            float3 _BoxMin;
            float3 _BoxMax;


            struct appdata
            {
                float3 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 posNDC : SV_POSITION;
                float3 rayDirWS : TEXCOORD0;
                float2 uv : TEXCOORD1;
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
            
            // Henyey-Greenstein scattering function
            // cosT ： 光线和视线夹角T的余弦值
            // g ： 各项异性参数
            // return： 光散射系数
            // 参考资料：https://omlc.org/classroom/ece532/class3/hg.html
            float HGScattering(float cosT, float g)
            {
                float g2 = g * g;
                return (1 - g2) / (4 * PI * pow(1 + g2 - 2 * g * cosT, 1.5));
            }

            // 将值v从[oldMin, oldMax]映射到[newMin, newMax]
            float Remap(float v, float oldMin, float oldMax, float newMin, float newMax)
            {
                return newMin + (v - oldMin) * (newMax - newMin) / (oldMax - oldMin);
            }

            // Beer-Lambert Law
            // 根据粒子密度和距离计算光的透过率的公式, （其实就是指数雾的计算公式）
            float Transmittance(float density, float distance)
            {
                return exp(-density * distance);
            }

            float SampleDensity()
            {
                float3 uvw = float3(0, 0, 0);
            }

            v2f vert(appdata v)
            {
                v2f o;
                o.posNDC = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                float4 rayDir = mul(unity_CameraInvProjection, float4(v.uv * 2 - 1, 0, -1));
                rayDir.w = 0;
                o.rayDirWS = mul(unity_CameraToWorld, rayDir).xyz;
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                float3 rayDirWS = normalize(i.rayDirWS);
                float3 rayPosWS = _WorldSpaceCameraPos;
                float2 intercept = InterceptRayBox(_BoxMin, _BoxMax, rayPosWS, 1.0 / rayDirWS);
                half4 color = half4(0, 0, 0, 0);
                if (intercept.y > 0)
                {
                    float2 depthUV = i.uv;
                    float2 depth = SampleSceneDepth(i.uv);
                    return half4(depth.xxx, 1);
                }
                return color;
            }
            ENDHLSL
        }
    }
}
