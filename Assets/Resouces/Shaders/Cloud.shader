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

        _Coverage ("Cloud Coverage", Range(0, 1)) = 1
        _BlueNoiseScale("Blue Noise Scale", Range(0.01, 4)) = 1

        [Header(March Parameters)]
        _MarchNoiseWeight("March Noise Weight", Range(0, 1))
        _MarchScale("March Scale", float) = 1
        _MarchOffset("March Offset", float) = 0

        [Header(Density)]
        _DensityScale("Density Scale", float) = 1;
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

            float _Coverage;
            float _BlueNoiseScale;
            float _Anvil;


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

            float SampleDensity(float3 position)
            {
                float3 nolPos = (position - _BoxMin)/(_BoxMax - _BoxMin);
                float4 weather = SAMPLE_TEXTURE2D_LOD(_WeatherMap, sampler_2D, nolPos.xz, 0);
                float coverage = max(weather.r, saturate(_Coverage - 0.5) * weather.g * 2);
                
                float shapeAlter = saturate(Remap(nolPos.y, 0, 0.07, 0, 1))
                    * saturate(Remap(nolPos.y, weather.b * 0.2, weather.b, 1, 0));

                // 铁砧形状，上下粗，中间细的云形状
                shapeAlter = pow(shapeAlter, saturate(Remap(nolPos.y, 0.65, 0.95, 1, 1 - _Coverage * _Anvil)));
                
                float densityAlter = 2 * weather.a * nolPos.y * _DensityScale
                    * saturate(Remap(nolPos.y, 0, 0.15, 0, 1))
                    * saturate(Remap(0.9, 1.0, 1, 0));

                float3 shapNoiseUV = nolPos;
                float4 noise = SAMPLE_TEXTURE3D_LOD(_ShapeNoise, sampler_3D, shapNoiseUV, 0);
                float shapNoise = Remap(noise.r, noise.g * 0.625 + noise.b * 0.25 + noise.a * 0.125 - 1, 1, 0, 1);
                shapNoise = saturate(Remap(density * shapeAlter, 1 - _Coverage * coverage, 1, 0, 1));

                float3 detailNoiseUV = nolPos;
                noise = SAMPLE_TEXTURE3D_LOD(_DetailNoise, sampler_3D, detailNoiseUV, 0);
                float detailNoiseFBM = noise.r * 0.625 + noise.g * 0.25 + noise.b * 0.125;
                float detailNoiseMod = 0.35 * exp(-0.75 * _Coverage) * lerp(detailNoiseFBM, detailNoiseFBM, saturate(1 - nolPos.y * 5.0));
                float density = saturate(Remap(shapNoise, detailNoiseMod, 1, 0, 1)) * densityAlter;
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
                float blueNoise = SAMPLE_TEXTURE2D_LOD(_BlueNoise, sampler_2D, i.uv.zw, 0);
                float maxMarchDistance =min(interception.y, LinearEyeDepth(SampleSceneDepth(i.uv.xy), _ZBufferParams));
                float currentDistance = 0;
                float3 marchPostionWS = rayPosWS + rayDirWS * interception.x;
                return half4(blueNoise.xxx, 1);
                
                

                
                return half4(1, 1, 1, 1);
            }
            ENDHLSL
        }
    }
}
