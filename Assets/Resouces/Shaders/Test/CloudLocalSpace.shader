// 将灯光，射线方向，映射到模型的本地空间下计算。
Shader "Volumetric/Test/CloudLocalSpace"
{
    Properties
    {
        [Header(Shape Noise)]
        [NoScaleOffset]_ShapeNoise ("Shape Noise", 3D) = "white" { }
        _ShapeWeight ("Shape Weights", Vector) = (1, 1, 1, 1)
        _ShapeOffset ("Shape Offset", Vector) = (1, 1, 1, 1)
        [VectorField(Scale, BaseSpeed, OffsetSpeed)]
        _ShapeUvwParam ("Shape UVW Parameters", Vector) = (1, 1, 1, 1)

        [Header(Detail Noise)]
        [NoScaleOffset]_DetailNoise ("Detail Noise", 3D) = "white" { }
        _DetailWeight ("Detail Weights", Vector) = (1, 1, 1, 1)
        _DetailOffset ("Detail Offset", Vector) = (1, 1, 1, 1)
        [VectorField(Scale, BaseSpeed, OffsetSpeed)]
        _DetailUvwParam ("Detail UVW Parameters", Vector) = (1, 1, 1, 1)

        [NoScaleOffset] _BlueNoise ("Blue Noise", 2D) = "white" { }
        _BlueNoiseScale ("Blue Noise Scale", Range(0.01, 5)) = 1
        _WeatherMap ("Weather Map", 2D) = "white" { }

        [VectorField(Offset, DetailWeight, Scale)]
        _DensityParam ("Density Parameters", Vector) = (0, 0, 0, 0)

        [VectorField(ForwardScattering, BackScattering, BaseBrightness, PhaseFactor)]
        _PhaseParam ("Phase Parameters", Vector) = (1, 1, 1, 1)        

        [VectorField(CloudAbsorption, SunAbsorption, DarknessThreshold)]
        _TransmittiveParam ("Transmittive Parameters", Vector) = (1, 1, 1, 1)

        [VectorField(StepScale, StepCount)]
        _MarchParam ("March Parameters", Vector) = (1, 1, 1, 1)

        _EdgeFadeDistance ("Edge Fade Distance", Vector) = (50, 10, 50, 0)
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
            float4 _ShapeUvwParam;
            float3 _ShapeOffset;

            TEXTURE3D(_DetailNoise);
            float3 _DetailWeight;
            float4 _DetailUvwParam;
            float3 _DetailOffset;
            
            TEXTURE2D(_BlueNoise);
            float _BlueNoiseScale;

            TEXTURE2D(_WeatherMap);
            float4 _WeatherMap_ST;
            
            SAMPLER(sampler_trilinear_repeat);
            
            #define EPSILON 0.0001
            #define sampler_2D sampler_trilinear_repeat
            #define sampler_3D sampler_trilinear_repeat


            float3 _BoxSize;
            float4x4 _BoxW2L;

            float3 _EdgeFadeDistance;

            float4 _DensityParam;
            float4 _PhaseParam;

            float4 _MarchParam;
            float4 _TransmittiveParam;
            float4 _SpeedParam;

            struct appdata
            {
                float3 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 posNDC       : SV_POSITION;
                float4 uv           : TEXCOORD0;    // xy, 屏幕空间的UV； zw，蓝噪声的的uv（保持长宽比）
                float3 rayDirLS     : TEXCOORD1;    // 云盒本地空间下的 ray 方向
                float3 rayOriginLS  : TEXCOORD2;    // 云盒本地空间下的 ray 起点（相机位置）
                float3 lightDirLS   : TEXCOORD3;    // 云盒本地空间下的 灯光 方向 （主光源）
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

            // 将值v从[oldMin, oldMax]映射到[newMin, newMax]
            float Remap(float v, float oldMin, float oldMax, float newMin, float newMax)
            {
                return newMin + (v - oldMin) * (newMax - newMin) / (oldMax - oldMin);
            }

            float SampleDensity(float3 rayPos)
            {
                const int kMipLevel = 0;

                // 包围盒边界的FadeIn，FadeOut
                float3 edgeDst = min(_EdgeFadeDistance, min(rayPos - (-0.5 * _BoxSize), 0.5 *_BoxSize - rayPos)) / _EdgeFadeDistance;
                float edgeWeight = min(edgeDst.x, min(edgeDst.y, edgeDst.z));
                

                float3 uvw = (rayPos + _BoxSize * 0.5) / _BoxSize;
                half4 weather = SAMPLE_TEXTURE2D_LOD(_WeatherMap, sampler_2D, uvw.xz, kMipLevel);
                float minG = Remap(weather.r, 0, 1.0, 0.1, 0.5);
                float maxG = Remap(weather.r, 0, 1.0, minG, 0.9);
                float heightGradient = saturate(Remap(uvw.y, 0, minG, 0, 1)) * saturate(Remap(uvw.y, 1, maxG, 0, 1));
                heightGradient *= edgeWeight;
                
                uvw = (_BoxSize * 0.5 + rayPos) * 0.001;
                float time = _Time.x;

                float3 shapeUVW = uvw * _ShapeUvwParam.x + float3(time, time * 0.1, time * 0.2) * _ShapeUvwParam.y + _ShapeOffset.xyz * _ShapeUvwParam.z;
                float4 shape = SAMPLE_TEXTURE3D_LOD(_ShapeNoise, sampler_3D, shapeUVW, kMipLevel);
                float shapeFBM = dot(shape, _ShapeWeight / dot(_ShapeWeight, 1)) * heightGradient;
                float shapeDensity = shapeFBM + _DensityParam.x * 0.1;
                // return shapeDensity;
                if (shapeDensity > 0)
                {
                    float3 detailUVW = uvw * _DetailUvwParam.x + float3(time * 0.4, -time, time * 0.1) * _DetailUvwParam.y + _DetailOffset.xyz * _DetailUvwParam.z;
                    half3 detail = SAMPLE_TEXTURE3D_LOD(_DetailNoise, sampler_3D, detailUVW, kMipLevel).rgb;
                    // return _DetailWeight / dot(_DetailWeight, 1);
                    float detailFBM = dot(detail, _DetailWeight / dot(_DetailWeight, 1));
                    // return detailFBM;
                    float temp = 1 - shapeFBM;
                    temp = temp * temp * temp;
                    return (shapeDensity - (1 - detailFBM) * temp * _DensityParam.y) * _DensityParam.z;
                }
                return 0;
            }

            float LightMarch(float3 position, float3 lightDir)
            {
                // 这里的不仅方向改成向着光源方向了
                float2 intercept = InterceptRayBox(position, 1.0 / lightDir);
                float marchStep = intercept.y / _MarchParam.y;
                float totalDencity = 0;
                for (int step = 0; step < _MarchParam.y; step++)
                {
                    position += lightDir * marchStep;
                    float density = SampleDensity(position);
                    totalDencity += max(0, density * marchStep);
                }

                // 这里和指数雾的计算公式一致
                float transmittance = exp(-totalDencity * _TransmittiveParam.y);

                // 保证有一个基础透过率，不然有的地方就全黑了。
                return _TransmittiveParam.z + (1 - _TransmittiveParam.z) * transmittance;
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
                half depth = LinearEyeDepth(LoadSceneDepth(i.posNDC.xy), _ZBufferParams);
                
                float3 lightDir = normalize(i.lightDirLS);
                float3 rayOrigin = i.rayOriginLS;
                float3 rayDir = normalize(i.rayDirLS);

                // 相位函数使太阳周围的云在逆光时更亮。
                float cosT = dot(rayDir, lightDir);
                float scatter = lerp(HGScattering(cosT, _PhaseParam.x), HGScattering(cosT, -_PhaseParam.y), 0.5);
                float phase = _PhaseParam.z + scatter * _PhaseParam.w;
                float noise = SAMPLE_TEXTURE2D_LOD(_BlueNoise, sampler_2D, i.uv.zw, 0).r;
                float2 intercept = InterceptRayBox(i.rayOriginLS, 1.0 / rayDir);
                
                // 为了消除步进带来的断层现象，每条Ray的步进的距离是不一样的
                float marchStep = (noise * 0.9 + 0.1) * _MarchParam.x;
                float maxMarchDst = min(intercept.y, depth - intercept.x);
                float lightEnergy = 0;
                float transmittance = step(0.001, intercept.y);
                float alpha = 0;
                for (float distance = marchStep; distance < maxMarchDst; distance += marchStep)
                {
                    float3 rayPos = i.rayOriginLS + (distance + intercept.x) * rayDir;
                    float density = SampleDensity(rayPos);
                    if (density > 0)
                    {
                        alpha += density;
                        float lightTransmittance = LightMarch(rayPos, lightDir);
                        lightEnergy += density * 11 * transmittance * lightTransmittance * phase;
                        transmittance *= exp(-density * 11 * _TransmittiveParam.x);
                        if (transmittance < 0.01)
                        {
                            break;
                        }
                    }
                }
                Light mainLight = GetMainLight();
                half3 cloudColor = lightEnergy * mainLight.color;
                return half4(cloudColor, saturate(alpha));
            }
            ENDHLSL
        }
    }
}
