#!/usr/bin/env python3
"""Coarse reference-identity veto over existing photo-derived candidates.

Reference geometry never supplies output points. Fixed ±4 px reference controls
test whether uncertainty in registration changes candidate acceptance.
"""
import argparse,json,hashlib
from pathlib import Path
import numpy as np
from register_print_reference import project
from reconcile_edge_estimators import reconcile,compare
from gt_tool import fit_line


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['registration','candidates','output']:p.add_argument(name,type=Path)
    p.add_argument('--reference-top',type=float,required=True)
    p.add_argument('--width',type=float,required=True)
    args=p.parse_args();r=json.loads(args.registration.read_text())
    if not r['accepted']:raise ValueError('reference was not recognized')
    manifest=json.loads((args.candidates/'transfer.json').read_text())
    if manifest['inputSHA256']!=r['inputSHA256']:raise ValueError('candidate capture mismatch')
    # The 16 px band reuses the existing candidate position-prior scale; this
    # is a fixed exploratory veto, not a calibrated registration interval.
    points=project(np.array([[.1*args.width,args.reference_top],[.9*args.width,args.reference_top]]),np.array(r['homography']))
    line=np.array(fit_line(points.tolist()));result={}
    for shift in [-4,0,4]:
        shifted=line.copy();shifted[2]+=shift
        paths={};failures={}
        for name in ['identity','translate_plus8','translate_minus8','opposing_tilt','opposing_tilt_inverse']:
            try:
                record=json.loads((args.candidates/(name+'.json')).read_text())
                paths[name]=reconcile(record,shifted,16)
            except ValueError as e:failures[name]=str(e)
        result[str(shift)]=dict(paths=paths,failures=failures,comparison=compare(paths) if 'identity' in paths else {})
    receipt=dict(registrationSHA256=hashlib.sha256(args.registration.read_bytes()).hexdigest(),
        inputSHA256=r['inputSHA256'],referenceSHA256=r['referenceSHA256'],referenceLine=line.tolist(),
        bandNativePixels=16,referenceShiftsNativePixels=[-4,0,4],results=result,
        status='diagnostic veto, not precision evidence or automatic routing')
    args.output.write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({k:{'failures':v['failures'],'comparison':v['comparison']} for k,v in result.items()}))
