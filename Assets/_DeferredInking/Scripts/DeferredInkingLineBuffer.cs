using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;

namespace WCGL
{
    using AdjacencyDict = Dictionary<(int vid_A, int vid_B), (int vid_L, int vid_R)>;

    public class DeferredInkingLineBuffer
    {
        public Renderer renderer { get; }

        Mesh mesh;
        GraphicsBuffer[] _LineVertices;
        MaterialPropertyBlock[] materialPropertyBlocks;

        struct LineVertex
        {
            public int vid_L;
            public int vid_R;
            public int vid_A_;
            public int vid_B_;
        }

        static int[] compSameVertexIndices(Mesh mesh)
        {
            var dst = new int[mesh.vertexCount];
            var posIdx = new Dictionary<Vector3, int>();
            var vertices = mesh.vertices;

            for (int i = 0; i < vertices.Length; i++)
            {
                var pos = vertices[i];
                if (posIdx.ContainsKey(pos))
                {
                    dst[i] = posIdx[pos];
                }
                else
                {
                    dst[i] = i;
                    posIdx[pos] = i;
                }
            }

            return dst;
        }

        static void addIndices(int i0, int i1, int i2, int[] sameVertexIndices, AdjacencyDict dst)
        {
            (int, int) i01;
            int _i0 = sameVertexIndices[i0];
            int _i1 = sameVertexIndices[i1];

            if (_i0 < _i1) { i01 = (_i0, _i1); }
            else { i01 = (_i1, _i0); }

            if (dst.ContainsKey(i01))
            {
                var v = dst[i01];
                if (_i0 < _i1) { v.vid_L = i2; }
                else { v.vid_R = i2; }
                dst[i01] = v;
            }
            else
            {
                if (_i0 < _i1) { dst[i01] = (i2, -1); }
                else { dst[i01] = (-1, i2); }
            }
        }

        static int findAdjacencyIndex(in Vector3 posA, in Vector3 posB, HashSet<int> adjacency, Vector3[] vertices)
        {
            var dirAB = (posB - posA).normalized;

            float minDot = float.MaxValue;
            int dstIdxA = -1;

            foreach (int idx in adjacency)
            {
                var posA_ = vertices[idx];
                var dirAA_ = (posA_ - posA).normalized;
                float dot = Vector3.Dot(dirAB, dirAA_);
                if (dot < minDot)
                {
                    minDot = dot;
                    dstIdxA = idx;
                }
            }

            return dstIdxA;
        }

        static (int[] lineIndices, LineVertex[] lineVertices) compIndices(Mesh mesh, int[] sameVertexIndices, HashSet<int>[] adjacency, int submesh)
        {
            var srcSubMeshIndices = mesh.GetIndices(submesh);
            var adjacencyDict = new AdjacencyDict();

            for (int i = 0; i < srcSubMeshIndices.Length; i += 3)
            {
                int i0 = srcSubMeshIndices[i];
                int i1 = srcSubMeshIndices[i + 1];
                int i2 = srcSubMeshIndices[i + 2];

                addIndices(i0, i1, i2, sameVertexIndices, adjacencyDict);
                addIndices(i1, i2, i0, sameVertexIndices, adjacencyDict);
                addIndices(i2, i0, i1, sameVertexIndices, adjacencyDict);
            }

            var dstSubMeshIndices = new List<int>();
            var dstLineVertices = new List<LineVertex>();
            var vertices = mesh.vertices;

            foreach (var item in adjacencyDict)
            {
                dstSubMeshIndices.Add(item.Key.vid_A);
                dstSubMeshIndices.Add(item.Key.vid_B);

                LineVertex lv = new LineVertex();
                lv.vid_L = item.Value.vid_L;
                lv.vid_R = item.Value.vid_R;

                var posA = vertices[item.Key.vid_A];
                var posB = vertices[item.Key.vid_B];
                lv.vid_A_ = findAdjacencyIndex(posA, posB, adjacency[item.Key.vid_A], vertices);
                lv.vid_B_ = findAdjacencyIndex(posB, posA, adjacency[item.Key.vid_B], vertices);

                dstLineVertices.Add(lv);
            }

            return (dstSubMeshIndices.ToArray(), dstLineVertices.ToArray());
        }

        static HashSet<int>[] collectAdjacency(Mesh mesh, int[] sameVertexIndices)
        {
            var allIndices = new List<int>();
            for (int i = 0; i < mesh.subMeshCount; i++)
            {
                allIndices.AddRange(mesh.GetIndices(i));
            }

            var dst = Enumerable.Range(0, mesh.vertexCount).Select(i => i == sameVertexIndices[i] ? new HashSet<int>() : null).ToArray();

            for (int i = 0; i < allIndices.Count; i += 3)
            {
                int i0 = sameVertexIndices[allIndices[i + 0]];
                int i1 = sameVertexIndices[allIndices[i + 1]];
                int i2 = sameVertexIndices[allIndices[i + 2]];

                dst[i0].Add(i1);
                dst[i0].Add(i2);
                dst[i1].Add(i0);
                dst[i1].Add(i2);
                dst[i2].Add(i0);
                dst[i2].Add(i1);
            }

            return dst;
        }

        public DeferredInkingLineBuffer(Renderer renderer, GraphicsBuffer vertexBuffer)
        {
            this.renderer = renderer;
            var smr = renderer as SkinnedMeshRenderer;
            if (smr != null)
            {
                mesh = new Mesh();
                smr.BakeMesh(mesh);
            }
            else
            {
                var mf = renderer.GetComponent<MeshFilter>();
                mesh = GameObject.Instantiate(mf.sharedMesh);
            }

            var sameVertexIndices = compSameVertexIndices(mesh);
            var adjacencies = collectAdjacency(mesh, sameVertexIndices);

            _LineVertices = new GraphicsBuffer[mesh.subMeshCount];
            materialPropertyBlocks = new MaterialPropertyBlock[mesh.subMeshCount];

            for (int i = 0; i < mesh.subMeshCount; i++)
            {
                (int[] lineIndices, var lineVertices) = compIndices(mesh, sameVertexIndices, adjacencies, i);

                mesh.SetIndices(lineIndices, MeshTopology.Lines, i);

                _LineVertices[i] = new GraphicsBuffer(GraphicsBuffer.Target.Structured, lineVertices.Length, 4 * 4);
                _LineVertices[i].SetData(lineVertices);

                materialPropertyBlocks[i] = new MaterialPropertyBlock();
                materialPropertyBlocks[i].SetBuffer("_LineVertices", _LineVertices[i]);
                materialPropertyBlocks[i].SetBuffer("_VertexBuffer", vertexBuffer);
                materialPropertyBlocks[i].SetInt("_VertexBufferStride", vertexBuffer.stride);
            }

            mesh.UploadMeshData(true);
        }

        public void draw(CommandBuffer command, in Matrix4x4 matrix, Material lineMaterial, DeferredInkingCamera.ShaderMode shaderMode)
        {
            int pass = Math.Min(lineMaterial.passCount - 1, (int)shaderMode);
            for (int i = 0; i < mesh.subMeshCount; i++)
            {
                command.DrawMesh(mesh, matrix, lineMaterial, i, pass, materialPropertyBlocks[i]);
            }
        }

        public void release()
        {
            foreach (var graphicsBuffer in _LineVertices)
            {
                graphicsBuffer.Release();
            }

            _LineVertices = null;
        }
    }
}