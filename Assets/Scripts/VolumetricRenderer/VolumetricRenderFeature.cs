using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

class VolumetricRenderPass : ScriptableRenderPass
{
    public const string kRenderTag = "VolumetricCloud";
    public const string kTemporyRTName = "_TemporyRT";
    public const string kTargetRTName = "_VolumetricTargetRT";

    public static class ShaderPropID
    {
        public static readonly int MainTex = Shader.PropertyToID("_MainTex");
        public static readonly int VolumeTex = Shader.PropertyToID("_VolumeTex");
    }

    private RenderTargetIdentifier sourceRTID;

    private RenderTargetHandle targetRTID;
    private RenderTargetHandle tempRTID;
    private Material upSampleMat;
    private RenderTextureDescriptor rtDesc;

    public VolumetricRenderPass()
    {
        renderPassEvent = RenderPassEvent.AfterRenderingSkybox;

        tempRTID = new RenderTargetHandle();
        tempRTID.Init(kTemporyRTName);
        targetRTID = new RenderTargetHandle();
        targetRTID.Init(kTargetRTName);
    }

    public void Setup(RenderTargetIdentifier rtID)
    {
        this.sourceRTID = rtID;
        upSampleMat = CoreUtils.CreateEngineMaterial("Volumetric/Test/UpSample");
    }

    private bool IsVolumetricRendererAvaiable()
    {
        var inst = VolumetricRenderer.Instance;
        if (null == inst || null == inst.material || !inst.gameObject.activeInHierarchy || !inst.enabled)
        {
            return false;
        }
        return true;
    }



    /// <summary>
    /// This method is called by the renderer before executing the render pass.
    /// Override this method if you need to to configure render targets and their clear state, and to create temporary render target textures.
    /// If a render pass doesn't override this method, this render pass renders to the active Camera's render target.
    /// You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
    /// </summary>
    /// <param name="cmd">CommandBuffer to enqueue rendering commands. This will be executed by the pipeline.</param>
    /// <param name="cameraTextureDescriptor">Render texture descriptor of the camera render target.</param>
    /// <seealso cref="ConfigureTarget"/>
    // /// <seealso cref="ConfigureClear"/>
    // public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    // {
    //     var inst = VolumetricRenderer.Instance;
    //     if (null == inst || null == inst.material || !inst.gameObject.activeInHierarchy || !inst.enabled)
    //     {
    //         return;
    //     }
        
	// 	cmd.GetTemporaryRT(tempRTID.id, rtDesc);

    //     var opaqueDesc = cameraTextureDescriptor;
    //     opaqueDesc.msaaSamples = 1;
    //     opaqueDesc.depthBufferBits = 0;

    //     cmd.GetTemporaryRT(tempRTID.id, opaqueDesc);
    //     cmd.Blit(sourceRTID, tempRTID.Identifier());

    //     opaqueDesc.width >>= inst.downSample;
    //     opaqueDesc.height >>= inst.downSample;

    //     cmd.GetTemporaryRT(targetRTID.id, opaqueDesc);
    // }

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
        opaqueDesc.msaaSamples = 1;
        opaqueDesc.depthBufferBits = 0;
        cmd.GetTemporaryRT(tempRTID.id, opaqueDesc);
        opaqueDesc.width >>= inst.downSample;
        opaqueDesc.height >>= inst.downSample;
        cmd.GetTemporaryRT(targetRTID.id, opaqueDesc);
        inst.SetupMaterial();
        cmd.Blit(sourceRTID, tempRTID.Identifier());
        cmd.Blit(0, targetRTID.Identifier(), inst.material);
        cmd.SetGlobalTexture(ShaderPropID.VolumeTex, targetRTID.Identifier());
        cmd.Blit(tempRTID.Identifier(), sourceRTID, upSampleMat);
        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        CommandBufferPool.Release(cmd);
    }

    // Cleanup any allocated resources that were created during the execution of this render pass.
    public override void OnCameraCleanup(CommandBuffer cmd)
    {

    }

    public override void FrameCleanup(CommandBuffer cmd)
    {
        cmd.ReleaseTemporaryRT(tempRTID.id);
        cmd.ReleaseTemporaryRT(targetRTID.id);
    }
}


public class VolumetricRenderFeature : ScriptableRendererFeature
{


    VolumetricRenderPass m_ScriptablePass;

    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new VolumetricRenderPass();
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        m_ScriptablePass.Setup(renderer.cameraColorTarget);
        renderer.EnqueuePass(m_ScriptablePass);
    }
}


