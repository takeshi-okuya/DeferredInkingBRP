using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace WCGL
{
    [ExecuteInEditMode]
    public class DeferredInkingModel : MonoBehaviour
    {
        static List<DeferredInkingModel> ActiveInstances = new List<DeferredInkingModel>();

        [Range(1, 255)] public int modelID = 255;
        public List<DeferredInkingLine> meshes = new List<DeferredInkingLine>();

        void OnEnable()
        {
            meshes.ForEach(mesh => mesh?.initBuffer());
            ActiveInstances.Add(this);
        }

        void OnDisable()
        {
            meshes.ForEach(mesh => mesh?.releaseBuffer());
            ActiveInstances.Remove(this);
        }

        public static void RenderActiveInstances_Line(CommandBuffer commandBuffer, DeferredInkingCamera.ShaderMode shaderMode)
        {
            foreach (var model in ActiveInstances)
            {
                foreach (var mesh in model.meshes)
                {
                    mesh.renderLine(commandBuffer, model.modelID, shaderMode);
                }
            }
        }

        public static void RenderActiveInstances_GBuffer(CommandBuffer commandBuffer)
        {
            foreach (var model in ActiveInstances)
            {
                foreach (var mesh in model.meshes)
                {
                    mesh.renderGBuffer(commandBuffer, model.modelID);
                }
            }
        }
    }
}
