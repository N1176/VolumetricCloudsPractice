using UnityEngine;

public class VfxConfig : MonoBehaviour
{
    public enum MountPoint
    {
        World = 0,  // 挂在世界里, 不跟随角色跑动
        Root = 1,   // 挂在脚底上, 跟随角色跑动, 但是不跟随角色动作
        Bone = 2,   // 挂在骨骼上, 会跟随角色动作
    }

    [Tooltip("延迟生效时间, 单位秒(大于0才有效)")]
    public float delayTime = 0;

    [Tooltip("生命周期, 单位秒, 包含延迟时间")]
    public float duration = -1f;

    [Tooltip("生命周期结束后销毁特效(生命周期大于0才有效)")]
    public bool destroyAfterDuration = false;

    [Tooltip("位置: 填骨骼路径\n 尽可能使用如下预定义!\n\t1. 头顶:hud\n\t2. 胸口:chest\n\t3. 脚底:root\n")]
    public string bonePath;

    [Tooltip("挂点")]
    public MountPoint mountPoint;

    [Tooltip("是否保持预制朝向\n\t保持:不随挂点一起旋转, 和放到世界一致\n\t不保持:不做特殊处理, 跟随挂点旋转")]
    public bool keepRotation;

    [Tooltip("保持缩放\n\t保持:不随挂点缩放, 和放到世界的大小保持一致\n\t不保持:不做特殊处理, 跟随挂点缩放")]
    public bool keepScale;

    [Tooltip("同步动画\n\t尝试播放和父GameObject上的动画控制器上正在播放的动画，并保持同步")]
    public bool syncAnimation;

    // 特效出现的时间.
    public float ShowTime
    {
        get
        {
            return Mathf.Max(-1f, duration - delayTime);
        }
    }

    private const float kTimePercision = 0.0001f;

    private bool isEnabling = false;

    private void OnEnable()
    {
        if (!isEnabling && delayTime > kTimePercision)
        {
            gameObject.SetActive(false);
            Invoke("OnDelayTimer", delayTime);
            isEnabling = true;
        }

        if (duration > kTimePercision && destroyAfterDuration)
        {
            GameObject.Destroy(this.gameObject, duration);
        }
        else if (!isEnabling && delayTime <= kTimePercision)
        {
            if (syncAnimation)
            {
                SyncAnim();
            }
        }
    }

    private void OnDelayTimer()
    {
        gameObject.SetActive(true);
        if (isEnabling)
        {
            CancelInvoke("OnDelayTimer");
            isEnabling = false;
        }
    }

    public void SetParent(Transform parent)
    {
       /* var localRotation = transform.localRotation;
        var localScale = transform.localScale;

        if (parent != null)
        {
            var root = parent;
            var bone = parent;
            var modelConfig = parent.GetComponent<ModelConfig>();
            var isBonePathValid = !string.IsNullOrEmpty(bonePath);
            if (null == modelConfig || null == modelConfig.boneRoot)
            {
                if (isBonePathValid)
                {
                    var newParent = parent.Find(bonePath);
                    if (null != newParent)
                    {
                        bone = newParent;
                    }
                }
            }
            else
            {
                root = modelConfig.boneRoot;
                bonePath = isBonePathValid ? bonePath : "root";
                switch (bonePath)
                {
                    case "hud":
                        bone = modelConfig.boneHUD;
                        break;
                    case "chest":
                        bone = modelConfig.boneChest;
                        break;
                    case "root":
                        bone = modelConfig.boneRoot;
                        break;
                    default:
                        bone = modelConfig.boneRoot.Find(bonePath);
                        break;
                }
                bone = null == bone ? root : bone;
            }

            switch (mountPoint)
            {
                case MountPoint.World:
                    {
                        var pos = bone.transform.TransformPoint(transform.localPosition);
                        transform.position = pos;
                    }
                    break;
                case MountPoint.Root:
                    {
                        var pos = bone.transform.TransformPoint(transform.localPosition);
                        transform.SetParent(bone, false);
                        transform.position = pos;
                    }
                    break;
                case MountPoint.Bone:
                    transform.SetParent(bone, false);
                    break;
            }

            if (keepRotation)
            {
                transform.rotation = localRotation;
            }

            if (keepScale && null != transform.parent)
            { 
                var parentScale = transform.parent.lossyScale;
                localScale.x /= parentScale.x;
                localScale.y /= parentScale.y;
                localScale.z /= parentScale.z;
                transform.localScale = localScale;
            }
        }
        */

        if (syncAnimation)
        {
            SyncAnim();
        }
    }

    private void SyncAnim()
    {
        Animator target = transform.GetComponent<Animator>();
        Animator source = transform.GetComponentInParent<Animator>();
        if (target == null)
        {
            target = transform.GetComponentInChildren<Animator>();
        }

        if (null == target || null == source)
        {
            return;
        }

        const int kAnimationLayer = 0;
        var si = source.GetCurrentAnimatorStateInfo(kAnimationLayer);
        target.Play(si.shortNameHash, kAnimationLayer, si.normalizedTime);
    }
}