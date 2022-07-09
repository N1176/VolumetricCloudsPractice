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
    private Mesh triangleMesh;
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
        var renderer = VolumetricRenderer.Instance;
        if (null == renderer || null == renderer.material || !renderer.gameObject.activeInHierarchy || !renderer.enabled)
        {
            return false;
        }
        return true;
    }

    // Here you can implement the rendering logic.
    // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
    // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
    // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var renderer = VolumetricRenderer.Instance;
        
        if (null == renderer || null == renderer.material || !renderer.gameObject.activeInHierarchy || !renderer.enabled)
        {
            return;
        }

        var cmd = CommandBufferPool.Get(kRenderTag);
        ref var cameraData = ref renderingData.cameraData;
        var opaqueDesc = cameraData.cameraTargetDescriptor;
        // opaqueDesc.msaaSamples = 1;
        opaqueDesc.depthBufferBits = 0;
        cmd.GetTemporaryRT(tempRTID.id, opaqueDesc);
        // 先把屏幕上的内容考出来(不能同时读写一张RT)
        cmd.Blit(sourceRTID, tempRTID.Identifier());

        // 将盒子画到三角形上。
        opaqueDesc.width /= renderer.downSample;
        opaqueDesc.height /= renderer.downSample;
        opaqueDesc.colorFormat = RenderTextureFormat.ARGB32;
        cmd.GetTemporaryRT(targetRTID.id, opaqueDesc);
        renderer.SetupMaterial();
        cmd.Blit(0, targetRTID.Identifier(), renderer.material);

        // 混合盒子和原图。
        cmd.SetGlobalTexture(ShaderPropID.VolumeTex, targetRTID.Identifier());
        cmd.Blit(tempRTID.Identifier(), sourceRTID, upSampleMat);
        // cmd.Blit(targetRTID.Identifier(), sourceRTID);
        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        CommandBufferPool.Release(cmd);
    }

    public override void FrameCleanup(CommandBuffer cmd)
    {
        cmd.ReleaseTemporaryRT(tempRTID.id);
        cmd.ReleaseTemporaryRT(targetRTID.id);
    }
}