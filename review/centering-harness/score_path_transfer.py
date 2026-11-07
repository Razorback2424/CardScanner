#!/usr/bin/env python3
"""Compose and perturb one selectively repaired boundary, preserving other paths."""
import argparse,copy,hashlib,json
from pathlib import Path
import numpy as np
from PIL import Image,ImageOps
import pillow_heif
from scipy.interpolate import PchipInterpolator
from track_card_paths import boundary,image_signal
from selective_path_measurement import measure,CORNERS


def run(image,baseline,measurement,proposal,output,frame,side):
    base=json.loads(measurement.read_text());candidate=json.loads(proposal.read_text())
    sha=hashlib.sha256(image.read_bytes()).hexdigest()
    if sha!=base['inputSHA256'] or sha!=candidate['inputSHA256']:raise ValueError('capture mismatch')
    sides=['left','top','right','bottom'] if side=='all' else [side]
    frames=copy.deepcopy(base['predictionNativePaths'])
    for selected_side in sides:
        source=candidate['frames'][frame][selected_side]
        frames[frame][selected_side]=[r['point'] for r in source['rows']]
    h=np.array(base['rectificationMatrix']);prediction=measure(frames,h)
    record=next(r for r in json.loads(baseline.read_text()) if r['fixture']==base['fixture'])
    quad=np.array([[record['actualOuter' if frame=='outer' else 'actualInner'][p]['x'],
                    record['actualOuter' if frame=='outer' else 'actualInner'][p]['y']] for p in CORNERS])
    variants={'identity':np.zeros((4,2)),'translate_plus8':np.full((4,2),8),
        'translate_minus8':np.full((4,2),-8),'opposing_tilt':np.array([[8,-8],[-8,8],[8,-8],[-8,8]]),
        'opposing_tilt_inverse':np.array([[-8,8],[8,-8],[-8,8],[8,-8]])}
    signal=candidate.get('signal','rgb_mean')
    pillow_heif.register_heif_opener();pixels=image_signal(ImageOps.exif_transpose(Image.open(image)).convert('RGB'),signal)
    rows=[];output.mkdir(parents=True,exist_ok=True)
    for name,delta in variants.items():
        results={s:boundary(pixels,(quad+delta).tolist(),s,position_sigma=16,adaptive_sharp=True) for s in sides}
        (output/(name+'.json')).write_text(json.dumps(results if side=='all' else results[side]))
        modified=copy.deepcopy(frames)
        for s,result in results.items():modified[frame][s]=[r['point'] for r in result['rows']]
        actual=measure(modified,h)
        edge_changes={}
        for s in sides:
            axis=0 if s in ['top','bottom'] else 1
            before=np.array(frames[frame][s]);after=np.array(modified[frame][s])
            before=before[np.argsort(before[:,axis])];after=after[np.argsort(after[:,axis])]
            grid=np.linspace(max(before[0,axis],after[0,axis]),min(before[-1,axis],after[-1,axis]),101)
            error=PchipInterpolator(after[:,axis],after[:,1-axis])(grid)-PchipInterpolator(before[:,axis],before[:,1-axis])(grid)
            edge_changes[s]=float(max(abs(error)))
        worst=max(edge_changes.values());diff={k:actual[k]-prediction[k] for k in ['leftShare','topShare']}
        counts={s:r['stableCount'] for s,r in results.items()}
        row=dict(name=name,stableCount=counts if side=='all' else counts[side],worstPositionChange=worst,shareDifferencePP=diff,
                 edgePositionChanges=edge_changes,
                 passesFixedLimits=bool(worst<=4 and max(abs(v) for v in diff.values())<=2))
        rows.append(row);print(json.dumps(row),flush=True)
    receipt=dict(fixture=base['fixture'],inputSHA256=sha,frame=frame,side=side,signal=signal,
        prediction=prediction,predictionNativePaths=frames,rectificationMatrix=h.tolist(),controls=rows,
        parentMeasurementSHA256=hashlib.sha256(measurement.read_bytes()).hexdigest(),
        proposalSHA256=hashlib.sha256(proposal.read_bytes()).hexdigest(),
        status='selected-side transfer and stability evidence, not independent physical accuracy')
    (output/'transfer.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({k:prediction[k] for k in ['leftShare','topShare']}))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['image','baseline','measurement','proposal','output']:p.add_argument(name,type=Path)
    p.add_argument('--frame',choices=['outer','inner'],required=True)
    p.add_argument('--side',choices=['left','top','right','bottom','all'],required=True)
    a=p.parse_args();run(a.image,a.baseline,a.measurement,a.proposal,a.output,a.frame,a.side)
