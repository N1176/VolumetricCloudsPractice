// 将灯光，射线方向，映射到模型的本地空间下计算。
Shader "Volumetric/Test/CloudLocalSpace"
{
    Properties
    {
        [Header(Shape Noise)]
        [NoScaleOffset]_ShapeNoise ("Shape Noise", 3D) = "white" { }
        _ShapeWeight ("Shape Weights", Vector) = (1, 1, 1, 1)
        _ShapeOffset ("Shape UV Offset", Vector) = (1, 1, 1, 1)
        _ShapeScale ("Shape UV Scale", float) = 1
        _ShapeSpeed ("Shape Speed", float) = 1

        [Header(Detail Noise)]
        [NoScaleOffset]_DetailNoise ("Detail Noise", 3D) = "white" { }
        _DetailWeight ("Detail Weights", Vector) = (1, 1, 1, 1)
        _DetailOffset ("Detail Offset", Vector) = (1, 1, 1, 1)
        _DetailScale ("Detail UV Scale", float) = 1
        _DetailSpeed ("Detail Speed", float) = 1
        
        [NoScaleOffset] _BlueNoise ("Blue Noise", 2D) = "white" { }
        _BlueNosieUVScale ("Blue Noise UV Scale", float) = 1
        _BlueNoiseValueScale ("Blue Noise Value Scale", float) = 1
        [NoScaleOffset]_WeatherMap ("Weather Map", 2D) = "white" { }

        [VectorField(ForwardScattering, BackScattering, BaseBrightness, PhaseFactor)]
        _PhaseParam ("Phase Parameters", Vector) = (1, 1, 1, 1)

        _DensitySetp ("March Step", Range(0.1, 100)) = 10
        _LightStepCount ("Light March Step Count", Range(4, 10)) = 4
        
        _DensityOffset ("Density Offset", Range(-1, 1)) = 0
        _DetailDensityWeight ("Detail Density Weight", float) = 1
        _DensityScale ("Density Scale", float) = 1
        
        _LightAbsorptionTowardSun ("Light Absorption Toward Sun", float) = 1
        _LightAbsorptionThroughCloud ("Light Absorption Through Cloud", float) = 1
        _DarknessThreshold ("Darkness Threshold", Range(0, 1)) = 0
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

            TEXTURE3D(_ShapeNoise);
            float4 _ShapeWeight;
            float _ShapeSpeed;
            float _ShapeScale;
            float3 _ShapeOffset;

            TEXTURE3D(_DetailNoise);
            float3 _DetailWeight;
            float3 _DetailOffset;
            float _DetailSpeed;
            float _DetailScale;
            
            TEXTURE2D(_BlueNoise);
            float _BlueNoiseValueScale;
            float _BlueNosieUVScale;

            TEXTURE2D(_WeatherMap);
            
            #define sampler_3D m_linear_repeat_sampler
            #define sampler_2D sampler_trilinear_repeat

            SAMPLER(sampler_2D);
            SAMPLER(sampler_3D);
            
            #define EPSILON 0.0001

            float3 _BoxSize;
            float4x4 _BoxW2L;

            float4 _DensityParam;
            float4 _PhaseParam;

            float4 _MarchParam;

            // float _HeightWeight;

            float _DensityOffset;
            float _DetailDensityWeight;
            float _DensityScale;

            float _DensitySetp;
            int _LightStepCount;

            float _LightAbsorptionTowardSun;
            float _LightAbsorptionThroughCloud;
            float _DarknessThreshold;

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
            // case 1: ray intersects box from outside (0 <= dstA <= dstB)
            // dstA is dst to nearest intersection, dstB dst to far intersection
            // case 2: ray intersects box from inside (dstA < 0 < dstB)
            // dstA is the dst to intersection behind the ray, dstB is dst to forward intersection
            // case 3: ray misses box (dstA > dstB)
            float2 InterceptRayBox(float3 rayOrigin, float3 invRayDir)
            {
                float3 boundsMin = -0.5 * _BoxSize;
                float3 boundsMax = 0.5 * _BoxSize;

                float3 t0 = (boundsMin - rayOrigin) * invRayDir;
                float3 t1 = (boundsMax - rayOrigin) * invRayDir;
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);
                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(min(tmax.x, tmax.y), tmax.z);

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
                return (1 - g2) / (4 * PI * pow(abs(1 + g2 - 2 * g * cosT), 1.5));
            }

            float Phase(float cosT)
            {
                float scatter = lerp(HGScattering(cosT, _PhaseParam.x), HGScattering(cosT, -_PhaseParam.y), 0.5);
                return _PhaseParam.z + scatter * _PhaseParam.w;
            }

            // 将值v从[oldMin, oldMax]映射到[newMin, newMax]
            float Remap(float v, float oldMin, float oldMax, float newMin, float newMax)
            {
                return newMin + (v - oldMin) * (newMax - newMin) / (oldMax - oldMin);
            }

            float SampleDensity(float3 rayPos)
            {
                const int kMipLevel = 0;

                float deltaShape = _Time.y * _ShapeSpeed;
                float deltaDetail = _Time.y * _DetailSpeed;

                // 包围盒边界平滑
                float3 softEdige = min(float3(10, 0, 10), _BoxSize * 0.05);
                float3 edgeDst = min(softEdige, min(rayPos + 0.5 * _BoxSize, 0.5 * _BoxSize - rayPos)) / softEdige;
                float edgeWeight = min(edgeDst.x, edgeDst.z);

                // 相对于box的后左下的位置。
                float3 pos = rayPos + 0.5 * _BoxSize;
                float3 uvw = pos / max(_BoxSize.x, max(_BoxSize.y, _BoxSize.z));
                float2 weatherUV = uvw.xz;
                float4 weatherMap = SAMPLE_TEXTURE2D_LOD(_WeatherMap, sampler_2D, weatherUV, kMipLevel);

                // 从天气图的R通道计算高度
                float gMin = Remap(weatherMap.x, 0.0, 1.0, 0.1, 0.5);
                float gMax = Remap(weatherMap.x, 0.0, 1.0, gMin, 0.9);
                float heightPercent = pos.y / _BoxSize.y;
                float heightGradient = saturate(Remap(heightPercent, 0.0, gMin, 0.0, 1.0)) * saturate(Remap(heightPercent, 1.0, gMax, 0.0, 1.0));

                float3 shapeUVW = uvw * _ShapeScale + _ShapeOffset / 100.0 + float3(1.0, 0.1, 0.2) * _Time.x * _ShapeSpeed;
                float4 shape = SAMPLE_TEXTURE3D_LOD(_ShapeNoise, sampler_3D, pos * shapeUVW, kMipLevel);
                float shapeFBM = dot(shape, _ShapeWeight / dot(_ShapeWeight, 1)) * heightGradient;
                float shapeDensity = shapeFBM + _DensityOffset;
                // return shapeDensity;
                if (shapeDensity > 0)
                {
                    float3 detailUVW = uvw * _ShapeScale * _DetailScale + _DetailOffset / 100.0 + float3(0.4, -1, 0.1) * _Time.x * _DetailSpeed;
                    half3 detail = SAMPLE_TEXTURE3D_LOD(_DetailNoise, sampler_3D, detailUVW, kMipLevel).rgb;
                    float detailFBM = dot(detail, _DetailWeight / dot(_DetailWeight, 1));
                    float temp = 1 - shapeFBM;
                    temp = temp * temp * temp;
                    return (shapeDensity - (1 - detailFBM) * temp * _DetailDensityWeight) * _DensityScale;
                }
                return 0;
            }

            float LightMarch(float3 position, float3 lightDir)
            {
                // 这里的不仅方向改成向着光源方向了
                float2 intercept = InterceptRayBox(position, 1.0 / lightDir);
                float marchStep = intercept.y / _LightStepCount;
                float totalDensity = 0;
                for (int step = 0; step < _LightStepCount; step++)
                {
                    position += lightDir * marchStep;
                    float density = SampleDensity(position);
                    totalDensity += max(0, density);
                }
                float transmittance = exp(-totalDensity * _LightAbsorptionTowardSun);
                return lerp(transmittance, 1, _DarknessThreshold);
            }

            v2f vert(appdata v)
            {
                v2f o;
                o.posNDC = TransformObjectToHClip(v.vertex);
                
                o.uv.xy = v.uv;
                // 蓝噪声的特性跟单位面积有关，采样时最好保持原图的长宽比。
                o.uv.zw = v.uv * float2(1, _ScreenParams.y / _ScreenParams.x) * _BlueNosieUVScale;

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
                half depth = LinearEyeDepth(LoadSceneDepth(i.posNDC.xy), _ZBufferParams);
                
                float3 lightDir = normalize(i.lightDirLS);
                float3 rayDir = normalize(i.rayDirLS);

                // 相位函数使太阳周围的云在逆光时更亮。
                float cosT = dot(rayDir, lightDir);
                float phase = Phase(cosT);
                float noise = SAMPLE_TEXTURE2D_LOD(_BlueNoise, sampler_2D, i.uv.zw, 0).r;
                float2 intercept = InterceptRayBox(i.rayOriginLS, 1.0 / rayDir);
                float maxMarchDst = min(intercept.y, depth - intercept.x);
                float lightEnergy = 0;
                float totalDencity = step(EPSILON, intercept.y);
                float stepSize = _DensitySetp;
                float distance = noise * _BlueNoiseValueScale;
                float alpha = 0;
                while (distance < maxMarchDst)
                {
                    float3 rayPos = i.rayOriginLS + (distance + intercept.x) * rayDir;
                    float density = SampleDensity(rayPos);
                    // return half4(density.xxx, 1);
                    if (density > 0)
                    {
                        density *= stepSize;
                        float lightTransmittance = LightMarch(rayPos, lightDir);
                        lightEnergy += density * totalDencity * lightTransmittance * phase;
                        totalDencity *= exp(-density * _LightAbsorptionThroughCloud);
                        if (totalDencity < 0.01)
                        {
                            break;
                        }
                    }
                    distance += stepSize;
                }
                return half4(totalDencity.xxx, 1);
                half3 cloudColor = lightEnergy * _MainLightColor.rgb;
                return half4(cloudColor, totalDencity);
            }
            ENDHLSL
        }
    }
}
