Shader "DeferredInking/Line"
{
    Properties
    {
        [Enum(Off, 0, Front, 1, Back, 2)] _Cull("Culling", INT) = 2
        _Color("Color", Color) = (0, 0, 0, 1)

        [Header(Outline Width)]
        _OutlineWidth("Outline Width (x0.1%)", FLOAT) = 2.0
        _WidthTex("Texture", 2D) = "white" {}
        [Toggle] _Width_By_Distance("Width by Distance", Float) = 0
        [Toggle] _Width_By_FoV("Width by FoV", Float) = 0
        _MinWidth("Min Width", FLOAT) = 0.5
        _MaxWidth("Max Width", FLOAT) = 4.0
        [KeywordEnum(FILL_OFF, CIRCLE_CLIPPING, Minimum, intersection)] _FillCorner("Corner", Float) = 0
        [Space]
        _DepthRange("Depth_Range", FLOAT) = 0.2
        [Header(Detection)]
        [Enum(Off, 255, Sufficiency, 0, Necessary, 1, Not, 2)] _Use_Section("Section", INT) = 0
        [Space]
        [Enum(Off, 255, Sufficiency, 0, Necessary, 1, Not, 2)] _Use_Crease("Use Crease", INT) = 255
        _CreaseThresholdDegree("Crease Threshold(degree)", Range(0, 180)) = 120
        [Space]
        [Enum(Off, 255, Sufficiency, 0, Necessary, 1, Not, 2)] _DifferentModelID("Different Model ID", INT) = 0
        [Enum(Off, 255, Sufficiency, 0, Necessary, 1, Not, 2)] _DifferentMeshID("Different Mesh ID", INT) = 0
        [Space]
        [Enum(Off, 255, Sufficiency, 0, Necessary, 1, Not, 2)] _Use_Depth("Use Depth", INT) = 255
        _DepthThreshold("Threshold_Depth", FLOAT) = 2.0
        [Space]
        [Enum(Off, 255, Sufficiency, 0, Necessary, 1, Not, 2)] _Use_Normal("Use Normal", INT) = 255
        _NormalThreshold("Threshold_Normal", Range(-1, 1)) = 0.5
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "LineType" = "DeferredInking"}
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma target 5.0
            #pragma enable_d3d11_debug_symbols

            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag

            #pragma multi_compile _FILLCORNER_FILL_OFF _FILLCORNER_CIRCLE_CLIPPING _FILLCORNER_MINIMUM _FILLCORNER_INTERSECTION
            #include "DeferredInking_Line.hlsl"

            ENDCG
        }
        Pass
        {
            CGPROGRAM
            #pragma target 5.0
            #pragma enable_d3d11_debug_symbols

            #pragma vertex vert
            #pragma hull hull
            #pragma domain domain
            #pragma fragment frag

            #pragma multi_compile _FILLCORNER_FILL_OFF _FILLCORNER_CIRCLE_CLIPPING _FILLCORNER_MINIMUM _FILLCORNER_INTERSECTION
            #include "DeferredInking_Line.hlsl"

            ENDCG
        }
    }

    FallBack "Diffuse"
}
