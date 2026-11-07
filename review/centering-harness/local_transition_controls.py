#!/usr/bin/env python3
"""Known-signal controls and explicitly unrectified local margin sensitivity."""
import argparse
import json
from pathlib import Path

import numpy as np
from scipy.special import erf
from local_transition_probe import fit
from track_card_paths import gradient_refinement


def sharp_controls():
    rng=np.random.default_rng(348);xs=np.arange(-28,29);rows=[]
    for width in [.6,1,2]:
        for contrast in [30,60,120]:
            for center in [-.4,.15,.45]:
                profile=70+.03*xs+contrast*.5*(1+erf((xs-center)/width/np.sqrt(2)))+rng.normal(0,1,len(xs))
                trials=[gradient_refinement(profile,xs,0,s) for s in [1,2]]
                value=float(np.median([r['center'] for r in trials]))
                rows.append(dict(width=width,contrast=contrast,expected=center,actual=value,
                                 error=abs(value-center),trials=trials))
    return dict(seed=348,count=len(rows),worst=max(r['error'] for r in rows),rows=rows,
                limitation='Ideal sharp transitions only; not real-photo truth')


def controls():
    rng=np.random.default_rng(348)
    ys=np.arange(3780,3850)
    rows=[]
    for center in [3808,3820,3833]:
        for amplitude in [30,60,120]:
            for blur in [3,6,9]:
                profile=70+.05*(ys-3815)+amplitude*.5*(1+erf(
                    (ys-center)/blur/np.sqrt(2)))+rng.normal(0,1,len(ys))
                for family in ['erf','logistic']:
                    result=fit(profile,ys,family)
                    rows.append(dict(expectedCenter=center,expectedAmplitude=amplitude,
                        expectedBlur=blur,family=family,error=abs(result['center']-center),**result))
    return dict(seed=348,count=len(rows),worst=max(r['error'] for r in rows),rows=rows,
                limitation='Single ideal step family with noise, not sleeve or real-photo accuracy')


def margin(probe,review):
    y=lambda line,x:(line[2]-line[0]*x)/line[1]
    top=[];bottom=[];low=[];high=[]
    for row in probe['rows']:
        x=row['x']
        t=y(review['frames']['print']['edges']['top']['line'],x)-y(
            review['frames']['cut']['edges']['top']['line'],x)
        b=y(review['frames']['print']['edges']['bottom']['line'],x)
        top.append(t);bottom.append(row['center']-b)
        low.append(row['sensitivityRange'][0]-b);high.append(row['sensitivityRange'][1]-b)
    share=lambda b:float(100*np.mean(top)/(np.mean(top)+np.mean(b)))
    return dict(status='unrectified vertical profile diagnostic, not final centering',
        topMean=float(np.mean(top)),bottomMean=float(np.mean(bottom)),share=share(bottom),
        fitSensitivityShareRange=[share(high),share(low)],includesUnstableRows=True,
        limitations='Model sensitivity only, not physical accuracy or a confidence interval; reviewed other edges')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('probe',type=Path);p.add_argument('review',type=Path)
    p.add_argument('output',type=Path);p.add_argument('--photo',default='0348')
    args=p.parse_args()
    result=dict(synthetic=controls(),sharp=sharp_controls(),margin=margin(json.loads(args.probe.read_text()),
                                            json.loads(args.review.read_text())[args.photo]))
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(dict(syntheticCount=result['synthetic']['count'],
                         syntheticWorst=result['synthetic']['worst'],sharpWorst=result['sharp']['worst'],margin=result['margin'])))
