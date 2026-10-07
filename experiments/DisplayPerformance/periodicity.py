#!/usr/bin/env python3
"""Analyze local request timestamps, without attributing their source or timer objects."""
import argparse, bisect, datetime, json, pathlib, statistics


def timestamps(text):
    values=[]
    for line in text.splitlines():
        try:
            record=json.loads(line)
            if not isinstance(record,dict):continue
            if 'received XPC_DISPLAY_INFO_REQUEST' in record.get('eventMessage',''):
                values.append(datetime.datetime.fromisoformat(record['timestamp']).timestamp())
        except (ValueError,KeyError,TypeError):continue
    return sorted(values)


def analyze(values):
    values=sorted(values)
    if len(values)<4 or values[-1]-values[0]<15:
        raise ValueError('At least four requests over fifteen seconds required')
    if len(values)>10000:raise ValueError('Use a bounded log segment')
    def errors(shift):
        result=[]
        for value in values:
            if value+shift>values[-1]:continue
            target=value+shift;index=bisect.bisect_left(values,target)
            result.append(min(abs(values[j]-target) for j in (index-1,index) if 0<=j<len(values)))
        return result
    candidates=[4.8+index*.001 for index in range(501)]
    period=min(candidates,key=lambda shift:statistics.median(errors(shift)))
    residuals=errors(period);groups=[]
    for phase in sorted((value-values[0])%period for value in values):
        if not groups or phase-groups[-1][-1]>.02:groups.append([phase])
        else:groups[-1].append(phase)
    if len(groups)>1 and groups[0][0]+period-groups[-1][-1]<=.02:
        groups[0]=[phase-period for phase in groups.pop()]+groups[0]
    return {'requests':len(values),'span_seconds':values[-1]-values[0],
            'searched_period_seconds':[4.8,5.3],'step_seconds':.001,
            'best_period_seconds':period,'median_pair_error_seconds':statistics.median(residuals),
            'aligned_pairs':sum(error<.01 for error in residuals),'eligible_pairs':len(residuals),
            'phase_tolerance_seconds':.02,'phase_cohorts':len(groups),
            'cohort_request_counts':[len(group) for group in groups],
            'limitation':'Timing cohorts do not identify client PID or prove one timer object per cohort'}


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('log_file');args=p.parse_args()
    print(json.dumps(analyze(timestamps(pathlib.Path(args.log_file).read_text())),indent=2))
