#include "UnityCG.cginc"

struct appdata
{
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
    uint vid : SV_VertexID;
};

struct v2g
{
    float4 positionVS_width : TEXCOORD0; //xyz: positionVS, w: width
    float3 normalVS : NORMAL0;
};

struct InPoint
{
    float4 positionCS;
    float3 positionVS;
    float width;
    float2 positionNS;
    float2 positionTS;
    float3 normalVS;
};

struct g2f
{
    float4 positionCS : SV_POSITION;
    float4 normalVS_positionVSCenterZ : TEXCOORD0; //xyz: normalVS, w: positionVS_center.z
    noperspective float4 positionTSCenter_isSection_isCrease : TEXCOORD1; //xy: positionTS_center, z: isSection, w: isCrease

#ifdef _FILLCORNER_CIRCLE_CLIPPING
    float2 corner : TEXCOORD2; //x:radius, y:isCorner(1 or 0).
#endif
};

struct OutputLinePositionCS
{
    float4 p0L, p0R, p1L, p1R;
};

struct OutputAdditionalPositionCS
{
    float4 pAL, pAR, pBL, pBR;
};

struct OutputPoints
{
    OutputLinePositionCS linePoints;
    
#if defined(_FILLCORNER_CIRCLE_CLIPPING) || defined(_FILLCORNER_MINIMUM)
    OutputAdditionalPositionCS additionalPoints;
#endif
};

fixed4 _Color;

float _OutlineWidth;
sampler2D _WidthTex;
float4 _WidthTex_ST;
float _Width_By_Distance;
float _Width_By_FoV;
float _MinWidth;
float _MaxWidth;

int _Cull;

int _Use_Section;

int _Use_Crease;
float _CreaseThresholdDegree;

int _DifferentModelID;
int _DifferentMeshID;

int _Use_Depth;
float _DepthThreshold;

int _Use_Normal;
float _NormalThreshold;
float _DepthRange;

Texture2D _GBuffer;
float4 _GBuffer_TexelSize;
Texture2D _GBufferDepth;
SamplerState my_point_clamp_sampler;

float2 _ID; // (ModelID, MeshID)

#define CULL_OFF 0
#define CULL_FRONT 1
#define CULL_BACK 2

#define USE_OFF 255
#define USE_SUFFICIENCY 0
#define USE_NECESSARY 1
#define USE_NOT 2

#define ADJACENCY_TYPE_LEFT_ONLY 1
#define ADJACENCY_TYPE_RIGHT_ONLY 2
#define ADJACENCY_TYPE_BOTH 3


ByteAddressBuffer _VertexBuffer;
uint _VertexBufferStride;


struct LineVertex
{
    int vid_L, vid_R, vid_A_, vid_B_;
};

StructuredBuffer<LineVertex> _LineVertices;

float3 loadPositionOS(uint vid)
{
    return asfloat(_VertexBuffer.Load3(vid * _VertexBufferStride));
}

float compWidth(float distance, appdata v)
{
    float width = _OutlineWidth * lerp(0.5, 1, tex2Dlod(_WidthTex, float4(v.uv, 0, 0)).g);
    width = lerp(width, width / distance, _Width_By_Distance);
    width = lerp(width, width * unity_CameraProjection[1][1] / 4.167f, _Width_By_FoV); //4.167: cot(27deg/2). 27deg: 50mm

    if (_Width_By_Distance == 1.f || _Width_By_FoV == 1.f)
    {
        width = clamp(width, _MinWidth, _MaxWidth);
    }

    return width * 0.001f;
}

v2g vert(appdata v)
{
    float3 positionOS = loadPositionOS(v.vid);

    float3 positionVS = UnityObjectToViewPos(positionOS);
    float width = compWidth(-positionVS.z, v);

    v2g o;
    o.positionVS_width = float4(positionVS, width);
    o.normalVS = COMPUTE_VIEW_NORMAL;

    return o;
}

float2 positionCSToNS(float4 positioCS)
{
    return positioCS.xy / positioCS.w;
}

bool isFrontFace(float2 positionNS_0, float2 positionNS_1, float2 positionNS_2)
{
    float3 vecNS_01 = float3(positionNS_1 - positionNS_0, 0);
    float3 vecNS_02 = float3(positionNS_2 - positionNS_0, 0);
    float3 normal_012 = cross(vecNS_01, vecNS_02);

#ifdef UNITY_REVERSED_Z
    return normal_012.z > 0;
#else
    return normal_012.z < 0;
#endif
}

float compCreaseDegree(InPoint p0, InPoint p1, LineVertex lineVertex)
{
    float3 positionOS_L = loadPositionOS(lineVertex.vid_L);
    float3 positionOS_R = loadPositionOS(lineVertex.vid_R);
    float3 positionVS_L = UnityObjectToViewPos(positionOS_L);
    float3 positionVS_R = UnityObjectToViewPos(positionOS_R);

    float3 vecVS_01 = p1.positionVS - p0.positionVS;
    float3 vecVS_0L = positionVS_L - p0.positionVS;
    float3 vecVS_0R = positionVS_R - p0.positionVS;

    float3 normalVS_01L = normalize(cross(vecVS_01, vecVS_0L));
    float3 normalVS_01R = normalize(cross(vecVS_0R, vecVS_01));
    
    float _cos = dot(normalVS_01L, normalVS_01R);
    float rad = acos(_cos);
    float degree = rad * 180 / 3.1415926535897932384626433832795f;

    return 180 - degree;
}

int compAdjacencyType(LineVertex lineVertex)
{
    if (lineVertex.vid_L != -1 && lineVertex.vid_R != -1)
    {
        return ADJACENCY_TYPE_BOTH;
    }
    else if (lineVertex.vid_L == -1)
    {
        return ADJACENCY_TYPE_RIGHT_ONLY;
    }
    else
    {
        return ADJACENCY_TYPE_LEFT_ONLY;
    }
}

bool culling(InPoint p0, InPoint p1, LineVertex lineVertex)
{
    if (_Cull == CULL_OFF) { return false; }

    float3 positionOS_L = loadPositionOS(lineVertex.vid_L);
    float3 positionOS_R = loadPositionOS(lineVertex.vid_R);
    float4 positionCS_L = UnityObjectToClipPos(positionOS_L);
    float4 positionCS_R = UnityObjectToClipPos(positionOS_R);
    float2 positionNS_L = positionCSToNS(positionCS_L);
    float2 positionNS_R = positionCSToNS(positionCS_R);
    
    bool isFrontFace_L = isFrontFace(p0.positionNS, p1.positionNS, positionNS_L);
    bool isFrontFace_R = isFrontFace(p0.positionNS, positionNS_R, p1.positionNS);

    bool isCull_L, isCull_R;

    if (_Cull == CULL_FRONT)
    {
        isCull_L = isFrontFace_L;
        isCull_R = isFrontFace_R;
    }
    else // _CULL == CULL_BACK
    {
        isCull_L = !isFrontFace_L;
        isCull_R = !isFrontFace_R;
    }
    
    int adjacencyType = compAdjacencyType(lineVertex);

    if (adjacencyType == ADJACENCY_TYPE_LEFT_ONLY)
    {
        return isCull_L;
    }
    else if (adjacencyType == ADJACENCY_TYPE_RIGHT_ONLY)
    {
        return isCull_R;
    }
    else // adjacencyType == ADJACENCY_TYPE_BOTH)
    {
        return isCull_L && isCull_R;
    }
}

bool isSamePlane(InPoint p0, InPoint p1, LineVertex lineVertex)
{
    return compCreaseDegree(p0, p1, lineVertex) > 179.0f;
}

bool isSection(InPoint p0, InPoint p1, LineVertex lineVertex)
{
    if (compAdjacencyType(lineVertex) != ADJACENCY_TYPE_BOTH)
    {
        return true;
    }

    float3 positionOS_L = loadPositionOS(lineVertex.vid_L);
    float3 positionOS_R = loadPositionOS(lineVertex.vid_R);
    float4 positionCS_L = UnityObjectToClipPos(positionOS_L);
    float4 positionCS_R = UnityObjectToClipPos(positionOS_R);
    float2 positionNS_L = positionCSToNS(positionCS_L);
    float2 positionNS_R = positionCSToNS(positionCS_R);
    
    bool isFrontFace_L = isFrontFace(p0.positionNS, p1.positionNS, positionNS_L);
    bool isFrontFace_R = isFrontFace(p0.positionNS, positionNS_R, p1.positionNS);

    return isFrontFace_L != isFrontFace_R;
}

bool isCrease(InPoint p0, InPoint p1, LineVertex lineVertex)
{
    if (compAdjacencyType(lineVertex) != ADJACENCY_TYPE_BOTH)
    {
        return false;
    }

    return compCreaseDegree(p0, p1, lineVertex) < _CreaseThresholdDegree;
}

struct IsRender
{
    bool isSection;
    bool isCrease;
};

bool isRender(InPoint p0, InPoint p1, LineVertex lineVertex, out IsRender dst)
{
    dst.isSection = dst.isCrease = false;

    if (culling(p0, p1, lineVertex) == true) { return false; }
    if (isSamePlane(p0, p1, lineVertex) == true) { return false; }

    dst.isSection = isSection(p0, p1, lineVertex);
    if (_Use_Section == USE_NOT && dst.isSection == true) { return false; }

    dst.isCrease = isCrease(p0, p1, lineVertex);
    if (_Use_Crease == USE_NOT && dst.isCrease == true) { return false; }

    return true;
}

struct Direction
{
    float2 vecNS;
    float2 rightNS;
};;

Direction compDirectionNS(float2 positionNS_0, float2 positionNS_1, float aspect)
{
    Direction dst;
    dst.vecNS = positionNS_1 - positionNS_0;
    dst.vecNS.x *= aspect;
    dst.vecNS = normalize(dst.vecNS);

    dst.rightNS = float2(-dst.vecNS.y, dst.vecNS.x);

    dst.vecNS.x /= aspect;
    dst.rightNS.x /= aspect;

    return dst;
}

float4 compPointPositionCS(float4 positionCS, float width, float2 directionNS)
{
    float4 translate = float4(width * directionNS * positionCS.w, 0, 0);
    return positionCS + translate;
}

float4 compInterplatedPosition(float4 posCS_1c, float4 posCS_1s, float4 posCS_2c, float4 posCS_2s)
{
    float2 posNS_1c = positionCSToNS(posCS_1c);
    float2 posNS_1s = positionCSToNS(posCS_1s);
    float2 posNS_2c = positionCSToNS(posCS_2c);
    float2 posNS_2s = positionCSToNS(posCS_2s);

    float2 v1 = posNS_1c - posNS_1s;
    float2 v2 = posNS_2c - posNS_2s;

    float d = -v1.x * v2.y + v2.x * v1.y;
    if (abs(d) < 0.0001)
    {
        return posCS_1c;
    }

    float2 pc = posNS_2c - posNS_1c;
    float s = (-v2.y * pc.x + v2.x * pc.y) / d;
    float2 p = posNS_1c + s * v1;

    float4 dst = float4(p * posCS_1c.w, posCS_1c.zw);
    return dst;
}

float2 lineToQuad(float4 positionCS1, float4 positionCS2, float width1, float width2, float aspect, out float4 dst_positionCS[4])
{
    float2 positionNS1 = positionCSToNS(positionCS1);
    float2 positionNS2 = positionCSToNS(positionCS2);
    float2 rightNS = compDirectionNS(positionNS1, positionNS2, aspect).rightNS;

    dst_positionCS[0] = compPointPositionCS(positionCS1, width1, rightNS);
    dst_positionCS[1] = compPointPositionCS(positionCS1, width1, -rightNS);
    dst_positionCS[2] = compPointPositionCS(positionCS2, width2, rightNS);
    dst_positionCS[3] = compPointPositionCS(positionCS2, width2, -rightNS);

    return rightNS;
}

void compQuadPositionCSs(InPoint p0, InPoint p1, float4 positionCS_A_, float4 positionCS_B_, float aspect, out float4 dst[4])
{
    float4 positionCS_AB[4];
    float2 rightAB = lineToQuad(p0.positionCS, p1.positionCS, p0.width, p1.width, aspect, positionCS_AB);

    dst = positionCS_AB;


                //float4 positionCS_AA_[4];
                //float2 rightAA_ = compDirection_(p1.projXY, positionCS_A_.xy / positionCS_A_.w, aspect);
                //positionCS_AA_[0] = compPointPosition(p1.positionCS, p1.viewPos_width.w, rightAA_);
                //positionCS_AA_[1] = compPointPosition(p1.positionCS, p1.viewPos_width.w, -rightAA_);
                //positionCS_AA_[2] = compPointPosition(positionCS_A_, p1.viewPos_width.w, rightAA_);
                //positionCS_AA_[3] = compPointPosition(positionCS_A_, p1.viewPos_width.w, -rightAA_);

                //float4 positionCS_BB_[4];
                //float2 rightBB_ = compDirection_(p2.projXY, positionCS_B_.xy / positionCS_B_.w, aspect);
                //positionCS_BB_[0] = compPointPosition(p2.positionCS, p2.viewPos_width.w, rightBB_);
                //positionCS_BB_[1] = compPointPosition(p2.positionCS, p2.viewPos_width.w, -rightBB_);
                //positionCS_BB_[2] = compPointPosition(positionCS_B_, p2.viewPos_width.w, rightBB_);
                //positionCS_BB_[3] = compPointPosition(positionCS_B_, p2.viewPos_width.w, -rightBB_);

 /*           #ifdef _FILLCORNER_MINIMUM
                dst[0] = compInterplatedPosition(positionCS_AB[0], positionCS_AB[2], positionCS_AA_[2], positionCS_AA_[0]);
                dst[1] = compInterplatedPosition(positionCS_AB[1], positionCS_AB[3], positionCS_AA_[3], positionCS_AA_[1]);
                dst[2] = compInterplatedPosition(positionCS_AB[2], positionCS_AB[0], positionCS_BB_[0], positionCS_BB_[2]);
                dst[3] = compInterplatedPosition(positionCS_AB[3], positionCS_AB[1], positionCS_BB_[1], positionCS_BB_[3]);
            #endif*/

#ifdef _FILLCORNER_INTERSECTION
    {
        float4 positionCS_AA_[4];
        float2 rightAA_ = lineToQuad(positionCS_A_, p0.positionCS, p0.width, p0.width, aspect, positionCS_AA_);

        float4 positionCS_BB_[4];
        float2 rightBB_ = lineToQuad(p1.positionCS, positionCS_B_, p1.width, p1.width, aspect, positionCS_BB_);

        dst[0] = compInterplatedPosition(positionCS_AB[0], positionCS_AB[2], positionCS_AA_[2], positionCS_AA_[0]);
        dst[1] = compInterplatedPosition(positionCS_AB[1], positionCS_AB[3], positionCS_AA_[3], positionCS_AA_[1]);
        dst[2] = compInterplatedPosition(positionCS_AB[2], positionCS_AB[0], positionCS_BB_[0], positionCS_BB_[2]);
        dst[3] = compInterplatedPosition(positionCS_AB[3], positionCS_AB[1], positionCS_BB_[1], positionCS_BB_[3]);

        //if (dot(rightAB, rightBB_) >=0)
        //{
        //    dst[2] = (positionCS_AB[2] + positionCS_BB_[0]) * 0.5f;
        //    dst[3] = (positionCS_AB[3] + positionCS_BB_[1]) * 0.5f;
        //}
        //else
        //{
        //    dst[2] = (positionCS_AB[2] + positionCS_BB_[1]) * 0.5f;
        //    dst[3] = (positionCS_AB[3] + positionCS_BB_[0]) * 0.5f;
        //}
    }
#endif
}

g2f generate_g2f(IsRender ir, InPoint inPoint, float4 positionCS, float isCorner /*0 or 1*/)
{
    g2f o;
    o.positionCS = positionCS;
    o.normalVS_positionVSCenterZ = float4(inPoint.normalVS, -inPoint.positionVS.z);
    o.positionTSCenter_isSection_isCrease.xy = inPoint.positionTS;
    o.positionTSCenter_isSection_isCrease.z = ir.isSection ? 1.0f : 0.0f;
    o.positionTSCenter_isSection_isCrease.w = ir.isCrease ? 1.0f : 0.0f;

#ifdef _FILLCORNER_CIRCLE_CLIPPING
    o.corner = float2(inPoint.width * 0.5f, isCorner);
#endif

    return o;
}

float4 duplicateForCirclePoint(float4 src, float2 vecNS_SrcToDst, float width)
{
    float4 dst = src;
    dst.xy += vecNS_SrcToDst * width * src.w;
    return dst;
}

OutputAdditionalPositionCS generateAddtional_Circle(OutputLinePositionCS src, InPoint p0, InPoint p1, float aspect)
{
    OutputAdditionalPositionCS dst;

    float2 vecNS_01 = compDirectionNS(p0.positionNS, p1.positionNS, aspect).vecNS;

    dst.pAR = duplicateForCirclePoint(src.p0R, -vecNS_01, p0.width);
    dst.pAL = duplicateForCirclePoint(src.p0L, -vecNS_01, p0.width);
    dst.pBR = duplicateForCirclePoint(src.p1R, vecNS_01, p1.width);
    dst.pBL = duplicateForCirclePoint(src.p1L, vecNS_01, p1.width);

    return dst;
}

OutputAdditionalPositionCS generateAddtional_Minimum(OutputLinePositionCS src, InPoint p0, InPoint p1, float aspect, float4 positionCS_A, float4 positionCS_B)
{
    OutputAdditionalPositionCS dst;
    
    float4 positionCS_AA_[4];
    lineToQuad(positionCS_A, p0.positionCS, p0.width, p0.width, aspect, positionCS_AA_);
    dst.pAR = positionCS_AA_[2];
    dst.pAL = positionCS_AA_[3];
    
    float4 positionCS_BB_[4];
    lineToQuad(p1.positionCS, positionCS_B, p1.width, p1.width, aspect, positionCS_BB_);
    dst.pBR = positionCS_BB_[0];
    dst.pBL = positionCS_BB_[1];
    
    return dst;
}

OutputLinePositionCS generateLinePoints(InPoint p0, InPoint p1, float4 positionCS_A_, float4 positionCS_B_, float aspect)
{
    float4 positionCSs[4];
    compQuadPositionCSs(p0, p1, positionCS_A_, positionCS_B_, aspect, positionCSs);

    OutputLinePositionCS dst;
    dst.p0R = positionCSs[0];
    dst.p0L = positionCSs[1];
    dst.p1R = positionCSs[2];
    dst.p1L = positionCSs[3];

    return dst;
}

OutputPoints generateLine(InPoint p0, InPoint p1, LineVertex lineVertex)
{
    float aspect = (-UNITY_MATRIX_P[1][1]) / UNITY_MATRIX_P[0][0];
    float3 positionOS_A_ = loadPositionOS(lineVertex.vid_A_);
    float3 positionOS_B_ = loadPositionOS(lineVertex.vid_B_);
    float4 positionCS_A_ = UnityObjectToClipPos(positionOS_A_);
    float4 positionCS_B_ = UnityObjectToClipPos(positionOS_B_);

    OutputPoints dst;
    dst.linePoints = generateLinePoints(p0, p1, positionCS_A_, positionCS_B_, aspect);

#ifdef _FILLCORNER_CIRCLE_CLIPPING
    dst.additionalPoints = generateAddtional_Circle(dst.linePoints, p0, p1, aspect);
#elif _FILLCORNER_MINIMUM
    dst.additionalPoints = generateAddtional_Minimum(dst.linePoints, p0, p1, aspect, positionCS_A_, positionCS_B_);
#endif
    
    return dst;
}

InPoint v2gToInPoint(v2g src)
{
    InPoint dst;
    float3 positionVS = src.positionVS_width.xyz;

    dst.positionCS = UnityViewToClipPos(positionVS);
    dst.positionVS = positionVS;
    dst.width = src.positionVS_width.w;
    dst.positionNS = positionCSToNS(dst.positionCS);

    dst.positionTS = (dst.positionNS + 1.0f) * 0.5f;
#if UNITY_UV_STARTS_AT_TOP == 1
    dst.positionTS.y = 1 - dst.positionTS.y;
#endif

    dst.normalVS = src.normalVS;

    return dst;
}

void appendTS(inout TriangleStream<g2f> ts, IsRender ir, InPoint p, float4 positionCS, float isCorner /*0 or 1*/)
{
    g2f output = generate_g2f(ir, p, positionCS, isCorner);
    ts.Append(output);
}

#ifdef _FILLCORNER_CIRCLE_CLIPPING
#define POINT_COUNT 8
#elif  _FILLCORNER_MINIMUM
#define POINT_COUNT 8
#else
#define POINT_COUNT 4
#endif
[maxvertexcount(POINT_COUNT)]
void geom(line v2g input[2], inout TriangleStream<g2f> ts, uint pid : SV_PrimitiveID)
{
    InPoint p0 = v2gToInPoint(input[0]);
    InPoint p1 = v2gToInPoint(input[1]);
    LineVertex lineVertex = _LineVertices[pid];

    IsRender ir;
    if (isRender(p0, p1, lineVertex, ir) == false) { return; }

    OutputPoints dst = generateLine(p0, p1, lineVertex);

#if defined(_FILLCORNER_CIRCLE_CLIPPING) || defined(_FILLCORNER_MINIMUM)
    appendTS(ts, ir, p0, dst.additionalPoints.pAR, 1);
    appendTS(ts, ir, p0, dst.additionalPoints.pAL, 1);
#endif

    appendTS(ts, ir, p0, dst.linePoints.p0R, 0);
    appendTS(ts, ir, p0, dst.linePoints.p0L, 0);
    appendTS(ts, ir, p1, dst.linePoints.p1R, 0);
    appendTS(ts, ir, p1, dst.linePoints.p1L, 0);

#if defined(_FILLCORNER_CIRCLE_CLIPPING) || defined(_FILLCORNER_MINIMUM)
    appendTS(ts, ir, p1, dst.additionalPoints.pBR, 1);
    appendTS(ts, ir, p1, dst.additionalPoints.pBL, 1);
#endif
}

[domain("quad")]
[partitioning("integer")]
[outputtopology("triangle_cw")]
[outputcontrolpoints(4)]
[patchconstantfunc("PatchConstantFunc")]
v2g hull(InputPatch<v2g, 2> inputs, uint id : SV_OutputControlPointID)
{
    v2g output = inputs[id];
    return output;
}

struct HS_CONSTANT_DATA_OUTPUT
{
    float TessFactor[4] : SV_TessFactor;
    float InsideTessFactor[2] : SV_InsideTessFactor;
    uint PrimitiveID: PrimitiveID;

    OutputPoints outputPoints : OutputPoints;
    IsRender isRender : IsRender;
};

#ifdef _FILLCORNER_CIRCLE_CLIPPING
#define FACTOR_Y 3
#elif  _FILLCORNER_MINIMUM
#define FACTOR_Y 3
#else
#define FACTOR_Y 1
#endif
HS_CONSTANT_DATA_OUTPUT PatchConstantFunc(InputPatch<v2g, 2> ip, uint PrimitiveID : SV_PrimitiveID)
{
    HS_CONSTANT_DATA_OUTPUT Output;

    InPoint p0 = v2gToInPoint(ip[0]);
    InPoint p1 = v2gToInPoint(ip[1]);
    IsRender ir;
    bool render = isRender(p0, p1, _LineVertices[PrimitiveID], ir);

    if (render)
    {
        Output.TessFactor[0] = Output.TessFactor[2] = FACTOR_Y;
        Output.TessFactor[1] = Output.TessFactor[3] = 1;
        Output.InsideTessFactor[0] = 0;
        Output.InsideTessFactor[1] = FACTOR_Y;

        Output.outputPoints = generateLine(p0, p1, _LineVertices[PrimitiveID]);
        Output.isRender = ir;
    }
    else
    {
        Output.TessFactor[0] = Output.TessFactor[1] = Output.TessFactor[2] = Output.TessFactor[3] = 0;
        Output.InsideTessFactor[0] = Output.InsideTessFactor[1] = 0;
    }

    Output.PrimitiveID = PrimitiveID;

    return Output;
}

[domain("quad")] 
g2f domain(HS_CONSTANT_DATA_OUTPUT hsConst, const OutputPatch<v2g, 2> op, float2 bary : SV_DomainLocation)
{
    InPoint p0 = v2gToInPoint(op[0]);
    InPoint p1 = v2gToInPoint(op[1]);
    OutputPoints dst = hsConst.outputPoints;
    IsRender  ir = hsConst.isRender;

#if defined(_FILLCORNER_CIRCLE_CLIPPING) || defined(_FILLCORNER_MINIMUM)
    if (bary.x == 0 && bary.y == 0) { return generate_g2f(ir, p0, dst.additionalPoints.pAR, 1); }
    else if (bary.x != 0 && bary.y == 0) { return generate_g2f(ir, p0, dst.additionalPoints.pAL, 1); }
    else if (bary.x == 0 && 0 < bary.y && bary.y < 0.5) { return generate_g2f(ir, p0, dst.linePoints.p0R, 0); }
    else if (bary.x != 0 && 0 < bary.y && bary.y < 0.5) { return generate_g2f(ir, p0, dst.linePoints.p0L, 0); }
    else if (bary.x == 0 && 0.5 < bary.y && bary.y < 1) { return generate_g2f(ir, p1, dst.linePoints.p1R, 0);}
    else if (bary.x != 0 && 0.5 < bary.y && bary.y < 1) { return generate_g2f(ir, p1, dst.linePoints.p1L, 0); }
    else if(bary.x == 0 && bary.y == 1) { return generate_g2f(ir, p1, dst.additionalPoints.pBR, 1); }
    else { return generate_g2f(ir, p1, dst.additionalPoints.pBL, 1); }
#else
    if (bary.x == 0 && bary.y == 0) { return generate_g2f(ir, p0, dst.linePoints.p0R, 0); }
    else if (bary.x == 1 && bary.y == 0) { return generate_g2f(ir, p0, dst.linePoints.p0L, 0); }
    else if (bary.x == 0 && bary.y == 1) { return generate_g2f(ir, p1, dst.linePoints.p1R, 0); }
    else { return generate_g2f(ir, p1, dst.linePoints.p1L, 0); }
#endif
}


void clipCorner(float4 positionCS, float2 positionTS_center, float2 corner)
{
    float radius = corner.x;

    float2 positionTS = (positionCS.xy + 0.5f) / _ScreenParams.xy;
    float2 vecTS_current_center = positionTS_center - positionTS;
    float aspect = (-UNITY_MATRIX_P[1][1]) / UNITY_MATRIX_P[0][0];
    vecTS_current_center.x *= aspect;

    clip((corner.y == 0 || dot(vecTS_current_center, vecTS_current_center) < radius * radius) - 0.1);
}

float decodeGBufferDepth(float2 uv)
{
    float gbDepth = _GBufferDepth.Sample(my_point_clamp_sampler, uv).x;

    if (unity_OrthoParams.w == 1.0f)
    { //ORTHO
#if !defined(UNITY_REVERSED_Z)
        gbDepth = 2 * gbDepth - 1;
#endif
        return -(gbDepth - UNITY_MATRIX_P[2][3]) / UNITY_MATRIX_P[2][2];
    }
    else
    {
        return DECODE_EYEDEPTH(gbDepth);
    }
}

bool isSameID(float2 id)
{
    float2 sub = abs(id * 255.0f - _ID);
    return sub.x + sub.y < 0.1f;
}

void sampleGBuffers(float2 uv, out bool3x3 isSameModelIDs, out bool3x3 isSameMaterialIDs, out float2 normals[3][3])
{
    [unroll]
    for (int y = -1; y <= 1; y++)
    {
        [unroll]
        for (int x = -1; x <= 1; x++)
        {
            float2 _uv = uv + float2(x, y) * _GBuffer_TexelSize.xy;
            float4 g = _GBuffer.Sample(my_point_clamp_sampler, _uv);

            float2 sub = abs(g.zw * 255.0f - _ID);
            isSameModelIDs[y + 1][x + 1] = sub.x <= 0.1f;
            isSameMaterialIDs[y + 1][x + 1] = sub.y <= 0.1f;

            normals[y + 1][x + 1] = g.xy;
        }
    }
}

float3x3 sampleDepths(float2 uv)
{
    float3x3 dst;

    [unroll]
    for (int y = -1; y <= 1; y++)
    {
        [unroll]
        for (int x = -1; x <= 1; x++)
        {
            float2 _uv = uv + float2(x, y) * _GBuffer_TexelSize.xy;
            dst[y + 1][x + 1] = decodeGBufferDepth(_uv);
        }
    }

    return dst;
}

bool detectNormal(float3 centerNormal, float centerDepth, float2 normals[3][3], float3x3 depths)
{
    bool isDraw = false;
    float d = centerDepth - _DepthRange;

    for (int y = 0; y < 3; y++)
    {
        for (int x = 0; x < 3; x++)
        {
            float3 n = DecodeViewNormalStereo(float4(normals[y][x], 0, 0));
            isDraw = isDraw || ((dot(centerNormal, n) < _NormalThreshold) && (d < depths[y][x]));
        }
    }

    return isDraw;
}

void clipDepthID(float4 positionCS, float lineCenterDepth, bool3x3 centerIsSameIDs, float3x3 gbufferCenterDepths)
{
    float2 positionTS = (positionCS.xy + 0.5) / _ScreenParams.xy;
    float2 id = _GBuffer.Sample(my_point_clamp_sampler, positionTS).zw;

    if (any(centerIsSameIDs))
    {
        clip(any(gbufferCenterDepths - lineCenterDepth - _DepthRange > 0) - 0.1f);
    
        if (isSameID(id) == false)
        {
            float gbufferDepth = decodeGBufferDepth(positionTS);
            float currentDepth = positionCS.w;
            clip(gbufferDepth - currentDepth);
        }
    }
    else
    {
        if (isSameID(id))
        {
        }
        else
        {
            float gbufferDepth = decodeGBufferDepth(positionTS);
            float currentDepth = positionCS.w;
            clip(gbufferDepth - currentDepth - _DepthRange);
        }
    }
}

void addConditions(int useType, bool isFill, inout int3 isDrawTimes, inout int3 isDrawTrues)
{
    if (useType == USE_SUFFICIENCY)
    {
        isDrawTimes[0] += 1;
        isDrawTrues[0] += isFill;
    }
    else if (useType == USE_NECESSARY)
    {
        isDrawTimes[1] += 1;
        isDrawTrues[1] += isFill;
    }
    else
    {
        isDrawTimes[2] += 1;
        isDrawTrues[2] += isFill;
    }
}

fixed4 frag(g2f i) : SV_Target
{
#ifdef _FILLCORNER_CIRCLE_CLIPPING
    clipCorner(i.positionCS, i.positionTSCenter_isSection_isCrease, i.corner);
#endif

    float3 normalVS = i.normalVS_positionVSCenterZ.xyz;
    float positionVS_center_z = i.normalVS_positionVSCenterZ.w;

    float2 positionTS_center = i.positionTSCenter_isSection_isCrease.xy;
    bool isSection = i.positionTSCenter_isSection_isCrease.z > 0;
    bool isCrease = i.positionTSCenter_isSection_isCrease.w > 0;

    bool3x3 isSameModelIDs, isSameMeshIDs;
    float2 normals[3][3];
    sampleGBuffers(positionTS_center, isSameModelIDs, isSameMeshIDs, normals);

    bool3x3 isSameIDs = isSameModelIDs && isSameMeshIDs;
    float3x3 gbufferCenterDepths = sampleDepths(positionTS_center);
    clipDepthID(i.positionCS, positionVS_center_z, isSameIDs, gbufferCenterDepths);

    int3 isDrawTimes = int3(0, 0, 0);
    int3 isDrawTrues = int3(0, 0, 0);

    bool3x3 isDeeps = gbufferCenterDepths > positionVS_center_z;
    if (_DifferentModelID != USE_OFF)
    {
        bool isFill = any(!isSameModelIDs && isDeeps);
        addConditions(_DifferentModelID, isFill, isDrawTimes, isDrawTrues);
    }

    if (_DifferentMeshID != USE_OFF)
    {
        bool isFill = any(!isSameMeshIDs && isDeeps);
        addConditions(_DifferentMeshID, isFill, isDrawTimes, isDrawTrues);
    }

    if (_Use_Depth != USE_OFF)
    {
        bool isFill = any(gbufferCenterDepths - positionVS_center_z > _DepthThreshold);
        addConditions(_Use_Depth, isFill, isDrawTimes, isDrawTrues);
    }

    if (_Use_Normal != USE_OFF)
    {
        bool isFill = detectNormal(normalVS, positionVS_center_z, normals, gbufferCenterDepths);
        addConditions(_Use_Normal, isFill, isDrawTimes, isDrawTrues);
    }

    if (_Use_Section != USE_OFF)
    {
        addConditions(_Use_Section, isSection, isDrawTimes, isDrawTrues);
    }

    if (_Use_Crease != USE_OFF)
    {
        addConditions(_Use_Crease, isCrease, isDrawTimes, isDrawTrues);
    }

    if (isDrawTrues.x + isDrawTrues.y == 0 || isDrawTimes.y != isDrawTrues.y || isDrawTrues.z > 0)
    {
        clip(-1);
    }
    return _Color;
}
