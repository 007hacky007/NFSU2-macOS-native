#include <assert.h>
#include <stdio.h>
#include "headlights_snapshot.h"
int main(void) {
    HeadlightSnapshots frames[2]={0}; HeadlightsBlock light={.n=1,.s=1};
    headlights_snapshot_reset(&frames[0]); headlights_snapshot_reset(&frames[1]);
    unsigned first=headlights_snapshot_put(&frames[0],&light); assert(first==1);
    assert(headlights_snapshot_put(&frames[0],&light)==first);
    light.l[0].col[0]=0.75f;
    unsigned next=headlights_snapshot_put(&frames[0],&light); assert(next==2);
    assert(frames[0].block[first].l[0].col[0]==0 && frames[0].block[next].l[0].col[0]==0.75f);
    assert(frames[1].count==1 && !frames[1].block[0].n);
    for(unsigned i=3;i<64;i++) { light.s=(float)i; assert(headlights_snapshot_put(&frames[0],&light)==i); }
    light.s=100; assert(headlights_snapshot_put(&frames[0],&light)==0); assert(!frames[0].block[0].n);
    assert(headlights_snapshot_put(&frames[0],&frames[0].block[first])==first);
    light.n=0; assert(!headlights_snapshot_put(&frames[0],&light));
    headlights_snapshot_reset(&frames[0]); assert(frames[0].count==1 && !frames[0].block[0].n);
    puts("headlight per-frame snapshots, reuse, immutable draws, overflow and reset passed");
}
