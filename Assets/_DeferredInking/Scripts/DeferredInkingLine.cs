using UnityEngine.Rendering;
using UnityEngine;
using UnityEditor;

namespace WCGL
{
    [System.Serializable]
    public class DeferredInkingLine
    {
        static Material GBufferMaterial;

        public Renderer mesh;
        public Material material;
        [Range(0, 255)] public int meshID;

        DeferredInkingLineBuffer buffer;

        public void initBuffer()
        {
            var renderer = mesh;
            if(buffer?.renderer == renderer || renderer == null) { return; }

            GraphicsBuffer vertexBuffer;
            var skinnedMeshRenderer = renderer as SkinnedMeshRenderer;
            if (skinnedMeshRenderer == null)
            {
                var sharedMesh = renderer.GetComponent<MeshFilter>().sharedMesh;
                sharedMesh.vertexBufferTarget |= GraphicsBuffer.Target.Raw;
                vertexBuffer = sharedMesh.GetVertexBuffer(0);
            }
            else
            {
                skinnedMeshRenderer.vertexBufferTarget |= GraphicsBuffer.Target.Raw;
                vertexBuffer = skinnedMeshRenderer.GetVertexBuffer();
            }

            if (vertexBuffer == null) { return; }

            buffer?.release();
            buffer = new DeferredInkingLineBuffer(renderer, vertexBuffer);
            vertexBuffer.Dispose();
        }

        Matrix4x4 getLocalToWorldMatrix(Renderer renderer)
        {
            var skinnedMeshRenderer = renderer as SkinnedMeshRenderer;
            if (skinnedMeshRenderer == null)
            {
                return renderer.localToWorldMatrix;
            }
            else
            {
                var rootBone = skinnedMeshRenderer.rootBone;
                if (rootBone == null) { return renderer.localToWorldMatrix; }
                else { return rootBone.localToWorldMatrix; }
            }
        }

        public void renderLine(CommandBuffer commandBuffer, int modelID, DeferredInkingCamera.ShaderMode shaderMode)
        {
            var renderer = mesh;
            if (renderer == null || renderer.isVisible == false || material == null)
            {
                releaseBuffer();
                return;
            }

            if (buffer?.renderer != renderer) { initBuffer(); }

            var id = new Vector2(modelID, meshID);
            commandBuffer.SetGlobalVector("_ID", id);

            var localToWorldMatrix = getLocalToWorldMatrix(renderer);
            buffer.draw(commandBuffer, localToWorldMatrix, material, shaderMode);
        }

        public void renderGBuffer(CommandBuffer commandBuffer, int modelID)
        {
            if (GBufferMaterial == null)
            {
                var shader = Shader.Find("Hidden/DeferredInking/GBuffer");
                GBufferMaterial = new Material(shader);
            }

            var renderer = mesh;
            if (renderer == null || renderer.isVisible == false || material == null) return;

            var id = new Vector2(modelID, meshID);
            commandBuffer.SetGlobalVector("_ID", id);

            commandBuffer.DrawRenderer(renderer, GBufferMaterial);
        }

        public void releaseBuffer()
        {
            buffer?.release();
            buffer = null;
        }
    }
}
