using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class SyncAnimation : MonoBehaviour
{
    public Animator target;
    public Animator source;
    // Start is called before the first frame update
    void Start()
    {
        SyncAnim();
    }

    private void SyncAnim()
    {
        if (target == null)          
        {
            target = transform.GetComponent<Animator>();
            if (null == target)
            {
                target = transform.GetComponentInChildren<Animator>();
            }
        }
        
        if (null == target)
        { 
            return; 
        }

        if (null == source)
        {
            source = transform.GetComponentInParent<Animator>();
        }
        
        if (null == source)
        {
            return;
        }

        const int kAnimationLayer = 0;
        var si = source.GetCurrentAnimatorStateInfo(kAnimationLayer);
        target.Play(si.shortNameHash, kAnimationLayer, si.normalizedTime);
    }
}
