#!/usr/bin/env python3
"""Evidence-based local estimator consensus, with explicitly inferred short gaps.

Reuses saved native fits without inspecting reference annotations. An inferred
point is never relabeled as directly supported. This is a research experiment.
"""
import argparse,json
from pathlib import Path
import numpy as np
from scipy.interpolate import PchipInterpolator


def reconcile(record,reference_line=None,reference_band=16):
    rows=[];normal=np.array(record['normal'])
    for row in record['rows']:
        g=row['gradientTrials'];s=row['trials']
        gp=np.array([v['center'] for v in g]);sp=np.array([v['center'] for v in s])
        gv=np.ptp(gp)<=4 and all(v['peak']>=2.5 and not v['boundaryHit'] for v in g)
        sv=np.ptp(sp)<=4 and all(v['converged'] and not v['atBound'] and v['relativeRMS']<=.15 for v in s)
        rejected=[]
        if reference_line is not None:
            line=np.array(reference_line)
            for name,values in [('gradient',gp),('step',sp)]:
                point=np.array(row['base'])+np.median(values)*normal
                if abs(line[:2]@point-line[2])>reference_band:
                    rejected.append(name)
                    if name=='gradient':gv=False
                    else:sv=False
        conflict=gv and sv and abs(np.median(gp)-np.median(sp))>4
        state='conflict' if conflict else 'both' if gv and sv else 'gradient' if gv else 'step' if sv else 'unsupported'
        centers=np.r_[gp,sp] if state=='both' else gp if state=='gradient' else sp
        supported=state not in ['conflict','unsupported']
        point=(np.array(row['base'])+np.median(centers)*normal).tolist() if supported else None
        rows.append(dict(state=state,directlySupported=supported,point=point,
                         referenceRejected=rejected,
                         estimatorDisagreement=float(abs(np.median(gp)-np.median(sp)))))
    good=np.array([i for i,r in enumerate(rows) if r['directlySupported']])
    if len(good)<30 or good[0]!=0 or good[-1]!=len(rows)-1:
        raise ValueError('insufficient support or unsupported endpoint; no extrapolation')
    maxgap=int(np.max(np.diff(good))-1)
    if maxgap>6:raise ValueError('gap exceeds 10% of the 61-position span')
    points=np.array([rows[i]['point'] for i in good])
    path=PchipInterpolator(good,points,axis=0)(np.arange(len(rows)))
    for i,r in enumerate(rows):
        r['point']=path[i].tolist();r['inferred']=not r['directlySupported']
    # Alternate directly-supported anchors, retaining both endpoints. Compare
    # withheld native points, not merely the smoothness of the inferred path.
    train=np.unique(np.r_[np.arange(0,len(good),2),len(good)-1]);held=np.setdiff1d(np.arange(len(good)),train)
    predicted=PchipInterpolator(good[train],points[train],axis=0)(good[held])
    errors=np.linalg.norm(predicted-points[held],axis=1)
    return dict(side=record['side'],rows=rows,directCount=len(good),maxGap=maxgap,
        heldOutCount=len(held),heldOutRMS=float(np.sqrt(np.mean(errors**2))),heldOutWorst=float(max(errors)),
        status='short-gap inference; physical accuracy and uncertainty not calibrated')


def compare(paths):
    axis=0 if paths['identity']['side'] in ['top','bottom'] else 1
    reference=np.array([r['point'] for r in paths['identity']['rows']]);reference=reference[np.argsort(reference[:,axis])]
    result={}
    for name,r in paths.items():
        points=np.array([row['point'] for row in r['rows']]);points=points[np.argsort(points[:,axis])]
        grid=np.linspace(max(reference[0,axis],points[0,axis]),min(reference[-1,axis],points[-1,axis]),101)
        err=PchipInterpolator(points[:,axis],points[:,1-axis])(grid)-PchipInterpolator(reference[:,axis],reference[:,1-axis])(grid)
        worst=float(max(abs(err)))
        result[name]=dict(directCount=r['directCount'],maxGap=r['maxGap'],heldOutWorst=r['heldOutWorst'],
            seedDisplacement=worst,passesPositionChecks=bool(worst<=4 and r['heldOutWorst']<=4))
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('input',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--prefix',default='');p.add_argument('--suffix',default='.json')
    args=p.parse_args();paths={};failures={}
    for name in ['identity','translate_plus8','translate_minus8','opposing_tilt','opposing_tilt_inverse']:
        try:paths[name]=reconcile(json.loads((args.input/(args.prefix+name+args.suffix)).read_text()))
        except ValueError as e:failures[name]=str(e)
    result=dict(paths=paths,failures=failures,comparison=compare(paths) if 'identity' in paths else {})
    args.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(dict(failures=failures,comparison=result['comparison'])))
