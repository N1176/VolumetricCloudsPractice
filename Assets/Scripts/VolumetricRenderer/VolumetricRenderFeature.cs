using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumetricRenderFeature : ScriptableRendererFeature
{
    class VolumetricRenderPass : ScriptableRenderPass
    {
        public const string kRenderTag = "Cloud";
        
        

        private RenderTargetIdentifier rednerTargetId;
        private RenderTargetHandle temporaryColorTexture;

        public VolumetricRenderPass()
        {
            temporaryColorTexture.Init("_TemporaryColorTexture");
        }

        public void Setup(RenderTargetIdentifier rti)
        {
            this.rednerTargetId = rti;
        }

        // This method is called before executing the render pass.
        // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
        // When empty this render pass will render to the active camera render target.
        // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
        // The render pipeline will ensure target setup and clearing happens in a performant manner.
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {

        }

        // Here you can implement the rendering logic.
        // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
        // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
        // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var inst = VolumetricRenderer.Instance;
            if (null == inst || null == inst.material || !inst.gameObject.activeInHierarchy || !inst.enabled || !renderingData.cameraData.postProcessEnabled)
            {
                return;
            }

            var cmd = CommandBufferPool.Get(kRenderTag);
            ref var cameraData = ref renderingData.cameraData;
            var opaqueDesc = cameraData.cameraTargetDescriptor;
            opaqueDesc.depthBufferBits = 0;
            opaqueDesc.width /= inst.downSample;
            opaqueDesc.height /= inst.downSample;
            cmd.GetTemporaryRT(temporaryColorTexture.id, opaqueDesc);
            inst.SetupMaterial();
            cmd.Blit(this.rednerTargetId, temporaryColorTexture.Identifier(), inst.material);
            cmd.Blit(temporaryColorTexture.Identifier(), this.rednerTargetId);
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
            cmd.ReleaseTemporaryRT(temporaryColorTexture.id);
        }

        private void Render(CommandBuffer cmd, ref RenderingData renderingData)
        {
            
        }

        // Cleanup any allocated resources that were created during the execution of this render pass.
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            
        }
    }

    VolumetricRenderPass m_ScriptablePass;

    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new VolumetricRenderPass();
        
        // Configures where the render pass should be injected.
        m_ScriptablePass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        m_ScriptablePass.Setup(renderer.cameraColorTarget);
        renderer.EnqueuePass(m_ScriptablePass);
    }
}


