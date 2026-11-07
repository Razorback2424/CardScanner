#!/usr/bin/env python3
"""Measure supported reference-selected photo paths with unchanged physical quad.

Rejects the whole replacement when any side lacks bounded measurement-span
support. A supported result is a research candidate, not calibrated accuracy.
"""
import argparse,hashlib,json
from pathlib import Path
import cv2
import numpy as np
from selective_path_measurement import CORNERS,paths,measure,supported_path

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['baseline','candidate','output']:p.add_argument(name,type=Path)
    p.add_argument('--fallback-candidate',type=Path,
        help='Separately observed photo paths to consider only when primary support fails')
    a=p.parse_args();candidate=json.loads(a.candidate.read_text())
    row=next(r for r in json.loads(a.baseline.read_text()) if r['fixture']==candidate['fixture'])
    if row['inputSHA256']!=candidate['inputSHA256']:raise ValueError('capture mismatch')
    quad=lambda key:[[row[key][p][axis] for axis in ['x','y']] for p in CORNERS]
    outer=quad('actualOuter');h=cv2.getPerspectiveTransform(np.float32(outer),np.float32([[0,0],[1,0],[1,1],[0,1]]))
    fallback=json.loads(a.fallback_candidate.read_text()) if a.fallback_candidate else None
    if fallback and (fallback['inputSHA256']!=candidate['inputSHA256'] or fallback['fixture']!=candidate['fixture']):
        raise ValueError('fallback capture mismatch')
    frames=dict(outer=paths(outer),inner={});support={};failures={};primary_failures={}
    for side,record in candidate['frames']['inner'].items():
        try:frames['inner'][side],support[side]=supported_path(record,h)
        except (ValueError,KeyError) as e:
            primary_failures[side]=str(e)
            alternative=fallback.get('frames',{}).get('inner',{}).get(side) if fallback else None
            if alternative is None:
                failures[side]=str(e);continue
            try:
                pts,evidence=supported_path(alternative,h)
                # Retain design identity: the alternative must remain within the
                # primary tracker's existing +/-80 native-pixel search band.
                start=np.array(record['rows'][0]['base']);end=np.array(record['rows'][-1]['base'])
                vector=end-start;normal=np.array([-vector[1],vector[0]])/np.linalg.norm(vector)
                distance=float(max(abs((np.asarray(pts)-start)@normal)))
                if distance>80:raise ValueError('alternative leaves the reference search band')
                evidence.update(source='supported alternate photo seed',maximumReferenceLineDistanceNativePixels=distance)
                frames['inner'][side]=pts;support[side]=evidence
            except (ValueError,KeyError) as fallback_error:failures[side]=str(fallback_error)
    if set(frames['inner'])!={'left','top','right','bottom'} and not failures:failures['frame']='missing side'
    result=dict(fixture=row['fixture'],inputSHA256=row['inputSHA256'],support=support,failures=failures,
        primarySupportFailures=primary_failures,
        fallbackCandidateSHA256=hashlib.sha256(a.fallback_candidate.read_bytes()).hexdigest() if a.fallback_candidate else None,
        candidateSHA256=hashlib.sha256(a.candidate.read_bytes()).hexdigest(),
        baselineSHA256=hashlib.sha256(a.baseline.read_bytes()).hexdigest(),acceptedForResearchMeasurement=not failures,
        limitation='Reference-guided photo paths; unchanged physical geometry; support is not independent physical accuracy or calibrated confidence')
    if not failures:
        try:
            result.update(prediction=measure(frames,h),predictionNativePaths=frames,rectificationMatrix=h.tolist())
        except ValueError as e:
            failures['geometry']=str(e)
            result['acceptedForResearchMeasurement']=False
        if row.get('actualInner'):
            try:result['baseline']=measure(dict(outer=paths(outer),inner=paths(quad('actualInner'))),h)
            except ValueError as e:result['baselineMeasurementFailure']=str(e)
    a.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ['predictionNativePaths','rectificationMatrix','baseline','prediction']}))
    for key in ['baseline','prediction']:
        if key in result:print(key,{k:result[key][k] for k in ['leftShare','topShare']})
