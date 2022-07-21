Shader "Volumetric/Tools/WeatherMapEditor"
{
    Properties
    {
        [NoScaleOffset] _MainTex ("Main Tex", 2D) = "white" { }
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }

        LOD 100
        Cull Back
        ZWrite Off
        ZTest Always

        HLSLINCLUDE

        #pragma vertex vert
        #pragma fragment frag
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Macros.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

        TEXTURE2D(_MainTex);
        SAMPLER(sampler_trilinear_repeat);
        
        #define EPSILON 0.0001
        #define sampler2D sampler_trilinear_repeat

        float3 _ActStart;
        float3 _ActEnd;
        float _DeltaTime;

        float4 _EditorPamas01;
        #define _BrushRadius _EditorPamas01.x
        #define _BrushSoftEdge _EditorPamas01.y
        #define _BrushIntensity _EditorPamas01.z
        #define _BrushAct _EditorPamas01.w

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

        float DistanceOfUvToDrag(float2 uv, float2 start, float2 end)
        {
            return 0;
        }

        float BrushEdgeSoftness(float distance)
        {
            return saturate((1 - distance) / (1 - _BrushSoftEdge));
        }

        float BrushIntensity(float2 pos)
        {
            // point 到线段之间的距离
            float2 es = _ActEnd.xz - _ActStart.xz;
            float2 ps = pos - _ActStart.xz;
            float k = saturate(dot(ps, es) / dot(es, es));
            float2 distVec = ps - k * es;
            float distance = dot(distVec, distVec) / _BrushRadius;

            // float distance = length(pos - _ActEnd.xz) / _BrushRadius;
            return saturate((1 - distance) / _BrushSoftEdge);
        }
        
        ENDHLSL

        Pass
        {
            Name "Deisity Editor"

            HLSLPROGRAM
            half4 frag(v2f i) : SV_Target
            {
                // float2 es = _ActEnd.xz - _ActStart.xz;
                // float2 ps = i.uv - _ActStart.xz;
                // float dotPsEs = dot(ps, es);
                // float k = saturate(dotPsEs / dot(es, es));
                // float2 distVec = ps - saturate * es;
                // float distance = length(distVec) / _BrushRadius;
                // float brushIntensity = saturate((1 - distance) / (1 - _BrushSoftEdge)) * _BrushIntensity;

                // float dotPeSe = dot(i.uv - _ActEnd.xz, -es);
                // float gChanelIdensity = step(0, dotPsEs * dotPeSe) * brushIntensity;

                // src.r += min(srg.g + brushIntensity, )
                // src.g += min(srg.g + gChanelIdensity, _BrushIntensity);

                half4 src = SAMPLE_TEXTURE2D(_MainTex, sampler2D, i.uv);
                half cur = src.r;
                
                float2 es = _ActEnd.xz - _ActStart.xz;
                float2 ps = i.uv - _ActStart.xz;
                float k = saturate(dot(ps, es) / dot(es, es));
                float distance = length(ps - k * es) / _BrushRadius;
                float brushIntensity = saturate((1 - distance) / _BrushSoftEdge);
                
                //* 所有的像素而言，_BrushAct的值是一样的， 所以这里用if没问题的
                if (_BrushAct < 0)
                {
                    src.r = lerp(cur, 0, brushIntensity);
                    return src;
                }
                else
                {
                    //* 先把逻辑写出来，有问题再改
                    if (cur > 1.0 - EPSILON || brushIntensity < EPSILON)
                    {
                        return src;
                    }
                    
                    if (cur < EPSILON)
                    {
                        src.r = brushIntensity;
                        return src;
                    }

                    float2 uvDDX = ddx(i.uv);
                    float2 uvDDY = ddy(i.uv);
                    float2 delta = float2(
                        SAMPLE_TEXTURE2D(_MainTex, sampler2D, i.uv + uvDDX).r - cur,
                        SAMPLE_TEXTURE2D(_MainTex, sampler2D, i.uv + uvDDY).r - cur
                    );
                    float2 dir = normalize(uvDDX * delta.x + uvDDY * delta.y);
                    float2 oldAnchor = i.uv + (1 - cur * _BrushSoftEdge) * _BrushRadius * dir;
                    float2 newAnchor = _ActStart.xz + k * es;
                    distance = min(distance, length(oldAnchor - i.uv));
                    distance = min(distance, length((oldAnchor + newAnchor) * 0.5 - i.uv));
                    brushIntensity = saturate((1 - distance) / _BrushSoftEdge);
                    src.r = brushIntensity;
                    return src;
                }
            }
            ENDHLSL
        }

        Pass
        {
            Name "Hight Map Editor"
            
            HLSLPROGRAM
            half4 frag(v2f i) : SV_Target
            {
                float brushIntensity = BrushIntensity(i.uv);
                float delta = sign(_BrushAct) * _BrushIntensity * brushIntensity;
                half4 src = SAMPLE_TEXTURE2D(_MainTex, sampler2D, i.uv);
                src.g = saturate(src.g + delta);
                return src;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Flow Editor"

            HLSLPROGRAM
            half4 frag(v2f i) : SV_Target
            {
                half4 src = SAMPLE_TEXTURE2D(_MainTex, sampler2D, i.uv);
                float brushIntensity = BrushIntensity(i.uv);
                float2 dir = (normalize(_ActStart.xz - _ActEnd.xz) + 1) * 0.5;
                dir = lerp(float2(0.5, 0.5), dir, step(0, _BrushAct)) * _BrushIntensity;
                src.ba = lerp(src.ba, dir, brushIntensity);
                return src;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Copy Source"

            HLSLPROGRAM
            half4 frag(v2f i) : SV_Target
            {
                return SAMPLE_TEXTURE2D(_MainTex, sampler2D, i.uv);
            }
            ENDHLSL
        }
    }
}
