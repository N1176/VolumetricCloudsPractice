Shader "Volumetric/Test/CloudV2"
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

        // 全局的云层密度系数
        _GlobalCoverage ("Cloud Coverage", Range(0, 1)) = 1
        
        _BlueNoiseScale ("Blue Noise Scale", Range(0.01, 4)) = 1

        // 光线从外界进入到云层的散射系数
        _HGScatterIn ("Scatter In", Range(0, 1)) = 0
        // 光线从云层发射到相机的散射系数
        _HGScatterOut ("Scatter Out", Range(0, 1)) = 0
        // 入/出散射比例
        _ScatterInOutRatio ("Scatter In Out Ratio", Range(0, 1)) = 0.5
        // 太阳周边的菲涅尔效应线性强度
        _SunFresnelIntencity ("Sun Fresnel Indencity", Range(0, 1)) = 1
        // 太阳周边的菲涅尔效应指数强度
        _SunFresnelExponent ("Sun Fresnel exponent", Range(0, 1)) = 1

        // Beer's Law, 计算光线衰减的
        _CloudBeer ("Cloud Beer", Range(0, 1)) = 0.5
        // 防止太暗的地方直接变黑。会给density一个最小值， 并且越靠近太阳的地方，最小值越大，也就是最暗的地方越亮
        _CloudAttuentionClamp ("Cloud Attuention Clamp", Range(0, 1)) = 1
        _CloudOutScatterAmbient ("Out Scatter Ambient", Range(0, 1)) = 0.3
        // 环境光最小值
        _CloudAmbientMin ("Ambient Minimum", float) = 0.1

        [Header(March Parameters)]
        _MarchNoiseWeight ("March Noise Weight", Range(0, 1)) = 1
        _MarchScale ("March Scale", float) = 1
        _MarchOffset ("March Offset", float) = 0

        [Header(Density)]
        _GlobalDensity ("Density Scale", float) = 1
        _DensityUVWScale("Density UVW Scale", Vector) = (1, 1, 1, 0)
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


            float4x4 _BoxW2L;
            float3 _BoxSize;

            float _GlobalCoverage;
            float _CloudAnvilAmount;

            float _HGScatterIn;
            float _HGScatterOut;
            float _ScatterInOutRatio;
            float _SunFresnelIntencity;
            float _SunFresnelExponent;
            float _CloudBeer;
            float _CloudAttuentionClamp;
            float _CloudOutScatterAmbient;
            // 环境光最小值
            float _CloudAmbientMin;


            float _BlueNoiseScale;
            float _GlobalDensity;
            float3 _DensityUVWScale;


            struct appdata
            {
                float3 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 posNDC : SV_POSITION;
                float4 uv : TEXCOORD0;    // xy, 屏幕空间的UV； zw，蓝噪声的的uv（保持长宽比）
                float3 rayDirLS : TEXCOORD1;    // 云盒本地空间下的 ray 方向
                float3 rayOriginLS : TEXCOORD2;    // 云盒本地空间下的 ray 起点（相机位置）
                float3 lightDirLS : TEXCOORD3;    // 云盒本地空间下的 灯光 方向 （主光源）

            };

            // 计算射线和包围盒的碰撞信息
            // rayOrigin:射线起点
            // invRayDir: 1 / 射线方向
            // return: x:射线走了多远才碰到包围盒，y:射线在包围盒内走了多远。
            // 参考资料: https://jcgt.org/published/0007/03/04/
            float2 InterceptRayBox(float3 rayOrigin, float3 invRayDir)
            {
                float3 t0 = (-0.5 * _BoxSize - rayOrigin) * invRayDir;
                float3 t1 = (0.5 * _BoxSize - rayOrigin) * invRayDir;
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
            // g ： 各项异性参数, [-1, 1]
            // return： 光散射系数
            // 参考资料：https://omlc.org/classroom/ece532/class3/hg.html
            float HGScatter(float cosT, float g)
            {
                float g2 = g * g;
                return (1 - g2) / (4 * PI * pow(1 + g2 - 2 * g * cosT, 1.5));
            }

            // 将值v从[oldMin, oldMax]映射到[newMin, newMax]
            float Remap(float v, float oldMin, float oldMax, float newMin, float newMax)
            {
                return newMin + (v - oldMin) * (newMax - newMin) / (oldMax - oldMin);
            }

            float InOutScatter(float cosT)
            {
                float sunFresnel = _SunFresnelIntencity * pow(saturate(cosT), _SunFresnelExponent);
                float hgScatterIn = HGScatter(cosT, _HGScatterIn);
                float hgScatterOut = HGScatter(cosT, _HGScatterOut);
                // max 是为了在太阳周边更亮。
                return lerp(max(hgScatterOut, sunFresnel), hgScatterIn, _ScatterInOutRatio);
            }

            float Attenuation(float densityToSun, float cosT)
            {
                float prim = exp(-_CloudBeer * densityToSun);
                float scnd = exp(-_CloudBeer * _CloudAttuentionClamp);
                scnd = Remap(cosT, 0.0, 1.0, scnd, 0.5 * scnd);
                return max(prim, scnd);

                // float clampDensity = min(densityToSun, _CloudAttuentionClamp * Remap(cosT, 0.0, 1.0, 1.0, 0.5));
                // return exp(-_CloudBeer * clampDensity);
            }

            float OutScatterAmbient(float densityToEye, float percentHeight)
            {
                float depth = _CloudOutScatterAmbient * pow(densityToEye, Remap(percentHeight, 0.3, 0.9, 0.5, 1.0));
                float vertical = pow(saturate(Remap(percentHeight, 0.0, 0.3, 0.8, 1.0)), 0.8);
                float outScatter = 1.0 - saturate(depth * vertical);
                return outScatter;
            }

            float CalculateLight(float densityToEye, float densityToSun, float cosT, float percentHeight, float blueNoise, float marchDistance)
            {
                float ambientOutScatter = OutScatterAmbient(densityToEye, percentHeight);
                float sunHeight = InOutScatter(cosT);
                float attenuation = Attenuation(densityToSun, cosT);
                attenuation *= sunHeight * ambientOutScatter;
                attenuation = max(densityToEye * _CloudAmbientMin * (1 - pow(marchDistance / 4000, 2)), attenuation);
                attenuation += blueNoise * 0.003;
                return attenuation;
            }

            float HeightAlter(float percentHeight, float4 weatherMap)
            {
                float height = saturate(Remap(percentHeight, 0.0, 0.07, 0.0, 1.0));
                float stopHeight = saturate(weatherMap.g + 0.12);
                height *= saturate(Remap(percentHeight, 0.2 * stopHeight, stopHeight, 1.0, 0.0));
                height = pow(height, saturate(Remap(percentHeight, 0.65, 0.95, 1.0, 1.0 - _CloudAnvilAmount * _GlobalCoverage)));
                return height;
            }

            float DensityAlter(float percentHeight, float4 weatherMap)
            {
                float density = percentHeight * saturate(Remap(percentHeight, 0.0, 0.2, 0.1, 1.0));
                density *= weatherMap.a * 2.0;
                density *= lerp(1.0, saturate(Remap(pow(percentHeight, 0.5), 0.4, 0.95, 1.0, 0.2)), _CloudAnvilAmount);
                density *= saturate(Remap(percentHeight, 0.9, 1.0, 1.0, 0.0));
                return density;
            }

            float SampleDensity(float3 position)
            {
                float3 nolPos = position / _BoxSize + 0.5;
                float percentHeight = nolPos.y;

                float4 weatherMap = SAMPLE_TEXTURE2D_LOD(_WeatherMap, sampler_2D, nolPos.xz, 0);
                float coverage = max(weatherMap.r, saturate(_GlobalCoverage - 0.5) * weatherMap.g * 2);
                

                float shapeAlter = saturate(Remap(percentHeight, 0, 0.07, 0, 1)) * saturate(Remap(percentHeight, weatherMap.b * 0.2, weatherMap.b, 1, 0));

                // 铁砧形状，上下粗，中间细的云形状
                // shapeAlter = pow(shapeAlter, saturate(Remap(percentHeight, 0.65, 0.95, 1, 1 - _GlobalCoverage * _CloudAnvilAmount)));

                float densityAlter = 2 * weatherMap.a * percentHeight * _GlobalDensity
                * saturate(Remap(percentHeight, 0, 0.15, 0, 1))
                * saturate(Remap(percentHeight, 0.9, 1.0, 1, 0));

                float3 shapeNoiseUV = nolPos * _DensityUVWScale;
                float4 noise = SAMPLE_TEXTURE3D_LOD(_ShapeNoise, sampler_3D, shapeNoiseUV, 0);
                float shapeNoise = Remap(noise.r, noise.g * 0.625 + noise.b * 0.25 + noise.a * 0.125 - 1, 1, 0, 1);
                return noise.r;
                shapeNoise = saturate(Remap(shapeNoise * shapeAlter, 1 - _GlobalCoverage * coverage, 1, 0, 1));

                float3 detailNoiseUV = nolPos;
                noise = SAMPLE_TEXTURE3D_LOD(_DetailNoise, sampler_3D, detailNoiseUV, 0);
                float detailNoiseFBM = noise.r * 0.625 + noise.g * 0.25 + noise.b * 0.125;
                float detailNoiseMod = lerp(detailNoiseFBM, detailNoiseFBM, saturate(percentHeight * 5.0));
                detailNoiseMod *= 0.35 * exp(-0.75 * _GlobalCoverage);

                float density = saturate(Remap(shapeNoise, detailNoiseMod, 1.0, 0.0, 1.0)) * densityAlter;
            }

            v2f vert(appdata v)
            {
                v2f o;
                o.posNDC = TransformObjectToHClip(v.vertex);
                
                o.uv.xy = v.uv;
                // 蓝噪声的特性跟单位面积有关，采样时最好保持原图的长宽比。
                o.uv.zw = v.uv * float2(1, _ScreenParams.y / _ScreenParams.x) * _BlueNoiseScale;

                float3 lightDir = _MainLightPosition.xyz;
                o.lightDirLS = normalize(mul(_BoxW2L, float4(lightDir, 0)).xyz);

                float3 viewVector = mul(unity_CameraInvProjection, float4(v.uv * 2 - 1, 0, -1)).xyz;
                viewVector = mul(unity_CameraToWorld, float4(viewVector, 0)).xyz;
                o.rayDirLS = mul(_BoxW2L, float4(viewVector, 0)).xyz;

                o.rayOriginLS = mul(_BoxW2L, float4(_WorldSpaceCameraPos.xyz, 1)).xyz;
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                float3 rayDirLS = normalize(i.rayDirLS);
                float cosT = dot(rayDirLS, i.lightDirLS);
                float scatter = InOutScatter(cosT);
                float2 interception = InterceptRayBox(i.rayOriginLS, 1.0 / rayDirLS);
                float blueNoise = SAMPLE_TEXTURE2D_LOD(_BlueNoise, sampler_2D, i.uv.zw, 0).r;
                float depth = LinearEyeDepth(SampleSceneDepth(i.uv.xy), _ZBufferParams);
                float maxMarchDistance = min(interception.x + interception.y, depth);
                
                float distance = interception.x;
                float attenuation = 0;
                float alpha = 0;
                float stepSize = 0.01;
                while(distance < maxMarchDistance)
                {
                    float3 marchPos = i.rayOriginLS + rayDirLS * distance;
                    float density = SampleDensity(marchPos);
                    if (density > 0)
                    {
                        alpha += stepSize * density / (maxMarchDistance - interception.x);
                        attenuation *= exp(-density * stepSize);
                    }
                    distance += stepSize;
                }
                float3 color = _MainLightColor.rgb * (1 - attenuation);
                return half4(color, alpha);
            }
            ENDHLSL
        }
    }
}
