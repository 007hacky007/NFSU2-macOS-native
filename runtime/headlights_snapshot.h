/* Each queued frame owns its immutable light blocks until encoding ends. */
#pragma once
#include <string.h>
#include "headlights.h"
typedef struct { HeadlightsBlock block[64]; unsigned count; } HeadlightSnapshots;
static inline void headlights_snapshot_reset(HeadlightSnapshots *pool) {
    memset(&pool->block[0],0,sizeof pool->block[0]); pool->count=1;
}
static inline unsigned headlights_snapshot_put(HeadlightSnapshots *pool,const HeadlightsBlock *block) {
    if(!pool->count) headlights_snapshot_reset(pool);
    if(!block->n || block->n>HEADLIGHTS_MAX) return 0;
    for(unsigned i=1;i<pool->count;i++) if(!memcmp(&pool->block[i],block,sizeof *block)) return i;
    if(pool->count==64) return 0;
    unsigned i=pool->count++; pool->block[i]=*block; return i;
}
