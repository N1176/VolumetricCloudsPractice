// 将灯光，射线方向，映射到模型的本地空间下计算。
Shader "Volumetric/Test/WeatherMapEditorTest"
{
    Properties
    {
        [NoScaleOffset]_MainTex ("Weather Map", 2D) = "white" { }
        [NoScaleOffset]_TestMap ("Flow Test Map", 2D) = "white" { }
        _Layer ("Weather Map Layer", Int) = 0
        _FlowSpeed("Flow Speed", Float) = 1
        [MaterialToggle]_ShowFlowMap("ShowFlowMap", int) = 1
    }

    SubShader
    {
        Tags{"RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True" "ShaderModel"="4.5"}
        LOD 300

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
            TEXTURE2D(_TestMap);
            
            int _Layer;
            float _FlowSpeed;
            int _ShowFlowMap;

            #define sampler_3D m_linear_repeat_sampler
            #define sampler_2D sampler_trilinear_repeat

            SAMPLER(sampler_2D);
            SAMPLER(sampler_3D);
            
            #define EPSILON 0.0001

            float3 _BoxSize;
            float4x4 _BoxW2L;

            half4 _Color;

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
            
            v2f vert(appdata v)
            {
                v2f o;
                o.posNDC = TransformObjectToHClip(v.vertex);
                
                o.uv.xy = v.uv;
                o.uv.zw = v.uv * float2(1, _ScreenParams.y / _ScreenParams.x) ;

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
                float3 rayDir = normalize(i.rayDirLS);
                half depth = LinearEyeDepth(LoadSceneDepth(i.posNDC.xy), _ZBufferParams);
                float2 intercept = InterceptRayBox(i.rayOriginLS, 1.0 / rayDir);

                if (intercept.y > 0)
                {
                    float3 rayPos = (i.rayOriginLS + (intercept.x) * rayDir + _BoxSize / 2) / _BoxSize;
                    half4 weatherMap = SAMPLE_TEXTURE2D(_MainTex, sampler_2D, rayPos.xz);
                    if (0 == _Layer)
                    {
                        return half4(rayPos.xz, 1.0, 1.0);
                        return half4(weatherMap.rrr, 1.0);
                    }
                    
                    if (1 == _Layer)
                    {
                        return half4(weatherMap.ggg, 1.0);
                    }

                    if (2 == _Layer)
                    {
                        half2 flow = weatherMap.ba * 2.0 - 1.0;
                        float phase0 = frac(_Time.y * _FlowSpeed);
                        float phase1 = frac(_Time.y * _FlowSpeed + 0.5);
                        half4 col0 = SAMPLE_TEXTURE2D(_TestMap, sampler_2D, rayPos.xz * 3 + flow * phase0);
                        half4 col1 = SAMPLE_TEXTURE2D(_TestMap, sampler_2D, rayPos.xz * 3 + flow * phase1);
                        half4 col = lerp(col0, col1, abs(0.5 - phase0) / 0.5);
                        return half4(lerp(col.rgb, half3(weatherMap.ba, 0), step(0.5, _ShowFlowMap)), 1.0);
                    }
                    return weatherMap;
                }
                return half4(0, 0, 0, 0);
            }
            ENDHLSL
        }
    }
}
