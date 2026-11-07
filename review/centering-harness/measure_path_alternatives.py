#!/usr/bin/env python3
"""Propagate every saved local estimator trial into paired-margin sensitivity.

Includes unsupported fits. Bounds cover the saved candidate set only, not all
physical explanations; they are not calibrated confidence or accuracy intervals.
"""
import argparse,copy,hashlib,json
from pathlib import Path
import numpy as np
from selective_path_measurement import measure


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['measurement','candidates','output']:p.add_argument(name,type=Path)
    p.add_argument('--frame',choices=['inner','outer'],required=True)
    p.add_argument('--side',choices=['left','top','right','bottom'],required=True)
    args=p.parse_args();m=json.loads(args.measurement.read_text())
    manifest=json.loads((args.candidates/'transfer.json').read_text())
    if m['inputSHA256']!=manifest['inputSHA256']:raise ValueError('capture mismatch')
    h=np.array(m['rectificationMatrix']);results={}
    for name in ['identity','translate_plus8','translate_minus8','opposing_tilt','opposing_tilt_inverse']:
        r=json.loads((args.candidates/(name+'.json')).read_text());n=np.array(r['normal']);extremes=[]
        for extreme in [min,max]:
            f=copy.deepcopy(m['predictionNativePaths'])
            f[args.frame][args.side]=[(np.array(row['base'])+extreme(
                trial['center'] for trial in row['gradientTrials']+row['trials'])*n).tolist() for row in r['rows']]
            measured=measure(f,h)
            extremes.append({k:measured[k] for k in ['leftShare','topShare']})
        results[name]={k:sorted(v[k] for v in extremes) for k in ['leftShare','topShare']}
    envelope={k:[min(v[k][0] for v in results.values()),max(v[k][1] for v in results.values())] for k in ['leftShare','topShare']}
    receipt=dict(inputSHA256=m['inputSHA256'],measurementSHA256=hashlib.sha256(args.measurement.read_bytes()).hexdigest(),
        frame=args.frame,side=args.side,results=results,envelope=envelope,
        includesUnsupportedFits=True,
        limitations='Only saved estimator alternatives; other edges and rectification fixed; not calibrated physical uncertainty or accuracy')
    args.output.write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(envelope))
