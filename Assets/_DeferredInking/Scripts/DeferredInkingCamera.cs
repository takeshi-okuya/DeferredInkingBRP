using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace WCGL
{
    [ExecuteInEditMode]
    public class DeferredInkingCamera : MonoBehaviour
    {
        public enum ShaderMode { GeometryShader = 0, Tesselation = 1 };

        static Material DrawMaterial;

        Camera cam;
        CommandBuffer commandBuffer;
        RenderTexture gBuffer, gBufferDepth, lineBuffer;

        [SerializeField] public ShaderMode shaderMode = ShaderMode.GeometryShader;

        [Range(0.0f, 3.0f)]
        public float sigma = 1.0f;
        Vector4[] filter = new Vector4[3];

        public enum ResolutionMode { Same, X2, X3, Custom }
        public ResolutionMode gBufferResolutionMode = ResolutionMode.Same;
        public Vector2Int customGBufferResolution = new Vector2Int(1920, 1080);

        void resizeRenderTexture()
        {
            var camSize = new Vector2Int(cam.pixelWidth, cam.pixelHeight);
            Vector2Int gbSize;

            if (gBufferResolutionMode == ResolutionMode.Same) { gbSize = camSize; }
            else if (gBufferResolutionMode == ResolutionMode.X2) { gbSize = camSize * 2; }
            else if (gBufferResolutionMode == ResolutionMode.X2) { gbSize = camSize * 3; }
            else { gbSize = customGBufferResolution; }

            if (gBuffer == null || gBuffer.width != gbSize.x || gBuffer.height != gbSize.y)
            {
                if (gBuffer != null) gBuffer.Release();
                gBuffer = new RenderTexture(gbSize.x, gbSize.y, 0, RenderTextureFormat.ARGB32);
                gBuffer.name = "DeferredInking_G-Buffer_Normal_ID";
                gBuffer.wrapMode = TextureWrapMode.Clamp;
                gBuffer.filterMode = FilterMode.Point;
            }

            if (gBufferResolutionMode != ResolutionMode.Same &&
                (gBufferDepth == null || gBufferDepth.width != gbSize.x || gBufferDepth.height != gbSize.y))
            {
                if (gBufferDepth != null) gBufferDepth.Release();
                gBufferDepth = new RenderTexture(gbSize.x, gbSize.y, 24, RenderTextureFormat.Depth);
                gBufferDepth.name = "DeferredInking_G-Buffer_Depth";
                gBufferDepth.wrapMode = TextureWrapMode.Clamp;
                gBufferDepth.filterMode = FilterMode.Point;
            }

            if (lineBuffer == null || lineBuffer.width != cam.pixelWidth || lineBuffer.height != cam.pixelHeight)
            {
                if (lineBuffer != null) lineBuffer.Release();
                lineBuffer = new RenderTexture(cam.pixelWidth, cam.pixelHeight, 16, RenderTextureFormat.ARGBHalf);
                lineBuffer.name = "DeferredInking_line";
                lineBuffer.antiAliasing = 4;
                lineBuffer.wrapMode = TextureWrapMode.Clamp;
                lineBuffer.filterMode = FilterMode.Point;
            }
        }

        void init()
        {
            cam = GetComponent<Camera>();
            if (cam == null)
            {
                Debug.LogError(name + " does not have camera.");
                return;
            }

            commandBuffer = new CommandBuffer();
            commandBuffer.name = "DeferredInking";

            resizeRenderTexture();

            if (DrawMaterial == null)
            {
                var shader = Shader.Find("Hidden/DeferredInking/Draw");
                DrawMaterial = new Material(shader);
            }
        }

        void OnEnable()
        {
            if (commandBuffer == null) { init(); }
            cam.AddCommandBuffer(CameraEvent.AfterSkybox, commandBuffer);
        }

        void OnDisable()
        {
            cam.RemoveCommandBuffer(CameraEvent.AfterSkybox, commandBuffer);
        }

        RenderTargetIdentifier renderGBuffer()
        {
            RenderTargetIdentifier depthBuffer;
            if (gBufferResolutionMode == ResolutionMode.Same)
            {
                depthBuffer = (RenderTargetIdentifier)BuiltinRenderTextureType.Depth;
            }
            else
            {
                depthBuffer = gBufferDepth.depthBuffer;
                renderGBufferDepth();
            }

            commandBuffer.SetRenderTarget(gBuffer.colorBuffer, depthBuffer);
            commandBuffer.ClearRenderTarget(false, true, Color.clear);
            DeferredInkingModel.RenderActiveInstances_GBuffer(commandBuffer);

            return depthBuffer;
        }

        void _renderLines(RenderTargetIdentifier gBufferDepth, bool clearColor)
        {
            commandBuffer.ClearRenderTarget(true, clearColor, Color.clear);
            commandBuffer.SetGlobalTexture("_GBuffer", gBuffer.colorBuffer);
            commandBuffer.SetGlobalTexture("_GBufferDepth", gBufferDepth);

            DeferredInkingModel.RenderActiveInstances_Line(commandBuffer, shaderMode);
        }

        void renderLines(RenderTexture targetColorBuffer, RenderTargetIdentifier gBufferDepth, bool clearColor)
        {
            commandBuffer.SetRenderTarget(targetColorBuffer, lineBuffer.depth);
            _renderLines(gBufferDepth, clearColor);
        }

        void renderLines(BuiltinRenderTextureType targetColorBuffer, RenderTargetIdentifier gBufferDepth, bool clearColor)
        {
            commandBuffer.SetRenderTarget(targetColorBuffer, lineBuffer.depth);
            _renderLines(gBufferDepth, clearColor);
        }

        void renewFilter()
        {
            float sum = 0;
            for (int y = -1; y <= 1; y++)
            {
                for (int x = -1; x <= 1; x++)
                {
                    float entry = Mathf.Exp(-(x * x + y * y) / (2 * sigma * sigma));
                    sum += entry;
                    filter[y + 1][x + 1] = entry;
                }
            }

            for (int i = 0; i < 3; i++)
            {
                filter[i] /= sum;
            }
        }

        void blitToFrameBuffer()
        {
            renewFilter();
            commandBuffer.SetGlobalVectorArray("Filter", filter);
            commandBuffer.Blit(lineBuffer, BuiltinRenderTextureType.CameraTarget, DrawMaterial);
        }

        private void OnPreRender()
        {
            resizeRenderTexture();
            var _gBufferDeoth = renderGBuffer();
            if (sigma == 0)
            {
                renderLines(BuiltinRenderTextureType.CameraTarget, _gBufferDeoth, false);
            }
            else
            {
                renderLines(lineBuffer, _gBufferDeoth, true);
                blitToFrameBuffer();
            }
        }

        static List<GameObject> _RootGameObjects = new List<GameObject>();
        static List<Renderer> _Renderers = new List<Renderer>();
        static List<Material> _SharedMaterials = new List<Material>();
        private void renderGBufferDepth()
        {
            commandBuffer.SetRenderTarget(gBufferDepth);
            commandBuffer.ClearRenderTarget(true, false, Color.clear);
            commandBuffer.SetGlobalVector("unity_LightShadowBias", Vector4.zero);

            gameObject.scene.GetRootGameObjects(_RootGameObjects);
            foreach (var root in _RootGameObjects)
            {
                root.GetComponentsInChildren<Renderer>(_Renderers);
                foreach (var r in _Renderers)
                {
                    if (r.isVisible == false) continue;

                    r.GetSharedMaterials(_SharedMaterials);
                    for (int i = 0; i < _SharedMaterials.Count; i++)
                    {
                        var mat = _SharedMaterials[i];
                        if (mat == null) { continue; }

                        int passIndex = mat.FindPass("ShadowCaster");
                        if (passIndex >= 0) { commandBuffer.DrawRenderer(r, mat, i, passIndex); }
                    }
                }
            }
        }

        private void OnPostRender()
        {
            commandBuffer.Clear();
        }
    }
}