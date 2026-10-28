/* Local audio is decoded on one worker; only bounded PCM rings cross into the guest mixer. */
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include "radio_native.h"
#include <pthread.h>
#include <sys/stat.h>
#include <time.h>

#define CHUNK 8192u
#define MAX_FILES 10000u
#define MAX_VISITS 40000u
#define MAX_FILE_BYTES (160u * 1024u * 1024u)

static HostStatusRadio status;
static pthread_mutex_t mutex;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static pthread_once_t once = PTHREAD_ONCE_INIT;
static pthread_t worker;
static int running, initialized, exit_registered, quitting, wanted, paused, shuffled, tracks_count;
static uint64_t epoch;
static uint32_t cut_seq, playing_seq;
static float *rings;
static uint32_t ring_frames;
static char playing_tags[3][RADIO_TAG];
static NSString *folder;

static void make_mutex(void) {
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&mutex, &attr);
    pthread_mutexattr_destroy(&attr);
    status.radio_magic = RADIO_MAGIC;
    status.radio_version = RADIO_VERSION;
}
void radio_native_lock(void) { pthread_once(&once, make_mutex); pthread_mutex_lock(&mutex); }
void radio_native_unlock(void) { pthread_cond_signal(&changed); pthread_mutex_unlock(&mutex); }
HostStatusRadio *host_status_radio(void) {
    if (!__atomic_load_n(&initialized, __ATOMIC_ACQUIRE)) radio_native_init();
    return &status;
}
void radio_native_bind_ring(float *ring, uint32_t frames) { rings = ring; ring_frames = frames; }
int radio_native_paused(void) { radio_native_lock(); int value = paused; radio_native_unlock(); return value; }
void radio_native_track_tags(uint32_t seq, char tags[3][RADIO_TAG]) {
    if (seq == playing_seq) memcpy(tags, playing_tags, sizeof playing_tags);
}
static void off_locked(void) {
    if (status.on & 1u) __atomic_add_fetch(&status.on, 1u, __ATOMIC_RELEASE);
}
void radio_native_set_enabled(int value) {
    radio_native_lock();
    value = value != 0;
    if (wanted != value) { wanted = value; epoch++; if (!wanted) off_locked(); }
    radio_native_unlock();
}
void radio_native_set_paused(int value) { radio_native_lock(); paused = value != 0; radio_native_unlock(); }
void radio_native_set_shuffle(int value) {
    radio_native_lock();
    value = value != 0;
    shuffled = value;
    radio_native_unlock();
}
void radio_native_next(void) {
    radio_native_lock();
    if (status.on & 1u) {
        cut_seq = status.request.req_seq;
        __atomic_store_n(&status.reply.written, status.rings.read, __ATOMIC_RELEASE);
        __atomic_store_n(&status.reply.total, status.rings.read, __ATOMIC_RELEASE);
    }
    radio_native_unlock();
}
void radio_native_frame(void) { radio_native_init(); }
void radio_native_snapshot(RadioNativeSnapshot *out) {
    if (!out) return;
    radio_native_lock();
    *out = (RadioNativeSnapshot){ .enabled = (int)(status.on & 1u), .paused = paused,
        .shuffle = shuffled, .tracks = tracks_count };
    memcpy(out->artist, playing_tags[0], RADIO_TAG);
    memcpy(out->title, playing_tags[1], RADIO_TAG);
    radio_native_unlock();
}

static void text_line(NSString *input, char out[RADIO_TAG]) {
    NSMutableString *text = [input ?: @"" mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)text, NULL, kCFStringTransformToLatin, false);
    CFStringTransform((__bridge CFMutableStringRef)text, NULL, kCFStringTransformStripCombiningMarks, false);
    NSMutableString *clean = [NSMutableString string];
    BOOL space = YES;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]) { if (!space) [clean appendString:@" "]; space = YES; }
        else { [clean appendFormat:@"%c", c >= 32 && c < 127 ? (char)c : '?']; space = NO; }
    }
    NSString *line = [clean stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (line.length > 40) line = [[line substringToIndex:37] stringByAppendingString:@"..."];
    memset(out, 0, RADIO_TAG);
    [line getCString:out maxLength:RADIO_TAG encoding:NSASCIIStringEncoding];
}
static NSData *tags_for(NSURL *url) {
    NSString *stem = url.lastPathComponent.stringByDeletingPathExtension, *artist = @"", *title = stem, *album = @"My music";
    NSRange split = [stem rangeOfString:@" - "];
    if (split.location != NSNotFound && split.location > 0) {
        artist = [stem substringToIndex:split.location]; title = [stem substringFromIndex:NSMaxRange(split)];
    }
    AudioFileID audio;
    if (AudioFileOpenURL((__bridge CFURLRef)url, kAudioFileReadPermission, 0, &audio) == noErr) {
        CFDictionaryRef info = NULL; UInt32 size = sizeof info;
        if (AudioFileGetProperty(audio, kAudioFilePropertyInfoDictionary, &size, &info) == noErr && info) {
            NSDictionary *values = CFBridgingRelease(info);
            if ([values[@kAFInfoDictionary_Artist] isKindOfClass:NSString.class] && [values[@kAFInfoDictionary_Artist] length]) artist = values[@kAFInfoDictionary_Artist];
            if ([values[@kAFInfoDictionary_Title] isKindOfClass:NSString.class] && [values[@kAFInfoDictionary_Title] length]) title = values[@kAFInfoDictionary_Title];
            if ([values[@kAFInfoDictionary_Album] isKindOfClass:NSString.class] && [values[@kAFInfoDictionary_Album] length]) album = values[@kAFInfoDictionary_Album];
        }
        AudioFileClose(audio);
    }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{
        AVURLAssetPreferPreciseDurationAndTimingKey: @NO,
        AVURLAssetReferenceRestrictionsKey: @(AVAssetReferenceRestrictionForbidAll) }];
    for (AVMetadataItem *item in asset.commonMetadata) {
        NSString *value = item.stringValue;
        if (!value.length) continue;
        if ([item.commonKey isEqualToString:AVMetadataCommonKeyArtist]) artist = value;
        else if ([item.commonKey isEqualToString:AVMetadataCommonKeyTitle]) title = value;
        else if ([item.commonKey isEqualToString:AVMetadataCommonKeyAlbumName]) album = value;
    }
    NSString *prefix = [artist stringByAppendingString:@" - "];
    if (artist.length && [title.lowercaseString hasPrefix:prefix.lowercaseString]) title = [title substringFromIndex:prefix.length];
    char tags[3][RADIO_TAG];
    text_line(artist.length ? artist : @"Unknown artist", tags[0]); text_line(title, tags[1]); text_line(album, tags[2]);
    return [NSData dataWithBytes:tags length:sizeof tags];
}
static NSArray<NSURL *> *files_in(NSString *path) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [NSURL fileURLWithPath:path isDirectory:YES];
    NSArray *keys = @[NSURLIsDirectoryKey, NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey, NSURLFileSizeKey];
    NSDirectoryEnumerator *walk = [fm enumeratorAtURL:root includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants errorHandler:^BOOL(NSURL *url, NSError *error) { (void)url; (void)error; return YES; }];
    NSSet *extensions = [NSSet setWithArray:@[@"wav", @"mp3", @"m4a", @"aac", @"aiff", @"aif", @"caf", @"flac", @"ogg", @"oga", @"opus"]];
    NSMutableArray<NSURL *> *files = [NSMutableArray array];
    unsigned visits = 0, dirs = 0;
    for (NSURL *url in walk) {
        if (++visits > MAX_VISITS || files.count >= MAX_FILES) break;
        NSDictionary *v = [url resourceValuesForKeys:keys error:nil];
        if ([v[NSURLIsSymbolicLinkKey] boolValue]) { [walk skipDescendants]; continue; }
        if ([v[NSURLIsDirectoryKey] boolValue]) {
            if (walk.level >= 8 || ++dirs > 2000) [walk skipDescendants];
        } else if ([v[NSURLIsRegularFileKey] boolValue] && [v[NSURLFileSizeKey] unsignedLongLongValue] <= MAX_FILE_BYTES && [extensions containsObject:url.pathExtension.lowercaseString]) [files addObject:url];
    }
    return [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSString *ad = a.URLByDeletingLastPathComponent.path, *bd = b.URLByDeletingLastPathComponent.path;
        if (![ad isEqualToString:bd]) {
            if ([ad isEqualToString:root.path]) return NSOrderedAscending;
            if ([bd isEqualToString:root.path]) return NSOrderedDescending;
            NSComparisonResult c = [ad compare:bd options:NSNumericSearch | NSCaseInsensitiveSearch];
            if (c != NSOrderedSame) return c;
        }
        return [a.path compare:b.path options:NSNumericSearch | NSCaseInsensitiveSearch];
    }];
}
static ExtAudioFileRef open_audio(NSURL *url) {
    /* File URLs only; a removed/replaced entry is treated as an unreadable track. */
    struct stat st;
    if (lstat(url.fileSystemRepresentation, &st) || !S_ISREG(st.st_mode) || st.st_size > MAX_FILE_BYTES) return NULL;
    ExtAudioFileRef file = NULL;
    if (ExtAudioFileOpenURL((__bridge CFURLRef)url, &file) != noErr) return NULL;
    AudioStreamBasicDescription output = { .mSampleRate = RADIO_RATE, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4, .mChannelsPerFrame = 2, .mBitsPerChannel = 32 };
    if (ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof output, &output) != noErr) { ExtAudioFileDispose(file); return NULL; }
    return file;
}
static OSStatus decode(ExtAudioFileRef file, float *left, float *right, UInt32 *frames) {
    struct { UInt32 count; AudioBuffer buffers[2]; } buffers = { 2, {{1, *frames * 4, left}, {1, *frames * 4, right}} };
    return ExtAudioFileRead(file, frames, (AudioBufferList *)&buffers);
}
static NSUInteger choose(NSArray<NSURL *> *files, NSMutableIndexSet *bad, NSUInteger next, NSUInteger last, int shuffle, NSMutableDictionary<NSNumber *, NSData *> *tags) {
    NSUInteger n = files.count;
    if (!n) return NSNotFound;
    NSUInteger start = shuffle && n > 1 ? arc4random_uniform((uint32_t)n - 1) : next % n;
    if (shuffle && n > 1 && start >= last && last < n) start++;
    for (NSUInteger j = 0; j < n; j++) {
        NSUInteger i = (start + j) % n;
        if ([bad containsIndex:i]) continue;
        if (!tags[@(i)]) {
            ExtAudioFileRef file = open_audio(files[i]);
            float left[1], right[1]; UInt32 count = 1;
            OSStatus error = file ? decode(file, left, right, &count) : -1;
            if (file) ExtAudioFileDispose(file);
            if (error || !count) { [bad addIndex:i]; continue; }
            tags[@(i)] = tags_for(files[i]);
        }
        return i;
    }
    return NSNotFound;
}
static void publish_offer(NSUInteger offered[2], NSMutableDictionary<NSNumber *, NSData *> *tags) {
    uint32_t mask = 0;
    __atomic_add_fetch(&status.offer.tag_seq, 1u, __ATOMIC_RELEASE);
    for (unsigned p = 0; p < 2; p++) {
        NSData *value = offered[p] == NSNotFound ? nil : tags[@(offered[p])];
        if (value) { memcpy(status.offer_text[p], value.bytes, sizeof status.offer_text[p]); mask |= 1u << p; }
        else memset(status.offer_text[p], 0, sizeof status.offer_text[p]);
    }
    __atomic_store_n(&status.offer.places, mask, __ATOMIC_RELEASE);
    __atomic_add_fetch(&status.offer.tag_seq, 1u, __ATOMIC_RELEASE);
}
static void *decode_worker(void *unused) { (void)unused; @autoreleasepool {
    NSArray<NSURL *> *files = nil;
    NSMutableIndexSet *bad = [NSMutableIndexSet indexSet];
    NSMutableDictionary<NSNumber *, NSData *> *tags = [NSMutableDictionary dictionary];
    NSUInteger next[2] = {0, 0}, last[2] = {NSNotFound, NSNotFound}, offered[2] = {NSNotFound, NSNotFound};
    NSUInteger current_index = NSNotFound;
    ExtAudioFileRef current = NULL;
    uint32_t seq = 0, written = 0;
    uint64_t seen = UINT64_MAX;
    int need_offer = 1, first = 0, previous_shuffle = 0;
    float left[CHUNK], right[CHUNK];
    for (;;) { @autoreleasepool {
        radio_native_lock();
        int stop = quitting, on = wanted, shuffle = shuffled;
        uint64_t generation = epoch;
        uint32_t request = status.request.req_seq, place = status.request.req_index;
        float *ring = rings; uint32_t frames = ring_frames, read = status.rings.read;
        int cut = request && cut_seq == request;
        radio_native_unlock();
        if (stop) break;
        if (shuffle != previous_shuffle) { previous_shuffle = shuffle; need_offer = 1; }
        if (!on || seen != generation) {
            if (current) { ExtAudioFileDispose(current); current = NULL; }
            if (seen != generation) { seen = generation; need_offer = 1; }
            if (!on) goto wait;
        }
        if (!files) {
            files = files_in(folder);
            radio_native_lock(); tracks_count = (int)files.count; radio_native_unlock();
        }
        if (need_offer && (!current || written - read >= frames - CHUNK)) {
            for (unsigned p = 0; p < 2; p++) offered[p] = choose(files, bad, next[p], last[p], shuffle, tags);
            radio_native_lock();
            if (wanted && epoch == generation) {
                publish_offer(offered, tags);
                tracks_count = (int)(files.count - bad.count);
                if (status.offer.places && !(status.on & 1u)) __atomic_add_fetch(&status.on, 1u, __ATOMIC_RELEASE);
                if (!status.offer.places) { wanted = 0; off_locked(); }
            }
            radio_native_unlock();
            need_offer = 0;
        }
        if (request && request != seq && ring && frames >= CHUNK && !(frames & (frames - 1u)) && place < 2) {
            if (current) { ExtAudioFileDispose(current); current = NULL; }
            seq = request; written = 0; first = 1;
            NSUInteger index = offered[place];
            current_index = index;
            if (index != NSNotFound) current = open_audio(files[index]);
            if (!current && index != NSNotFound) { [bad addIndex:index]; [tags removeObjectForKey:@(index)]; }
            radio_native_lock();
            if (epoch == generation && status.request.req_seq == seq) {
                playing_seq = seq;
                if (index != NSNotFound) memcpy(playing_tags, [tags[@(index)] bytes], sizeof playing_tags);
                if (!current) __atomic_store_n(&status.reply.failed_seq, seq, __ATOMIC_RELEASE);
            }
            radio_native_unlock();
            if (index != NSNotFound) { last[place] = index; next[place] = index + 1; }
            need_offer = 1;
        }
        if (current && !cut && written - read <= frames && frames - (written - read) >= CHUNK) {
            UInt32 count = CHUNK;
            OSStatus error = decode(current, left, right, &count);
            if (error && current_index != NSNotFound) { [bad addIndex:current_index]; [tags removeObjectForKey:@(current_index)]; need_offer = 1; }
            radio_native_lock();
            if (wanted && epoch == generation && status.request.req_seq == seq && cut_seq != seq && rings == ring) {
                if (first) { status.reply.written = 0; status.reply.total = UINT32_MAX; }
                for (UInt32 i = 0; i < count && !error; i++) {
                    ring[(written + i) & (frames - 1u)] = left[i];
                    ring[frames + ((written + i) & (frames - 1u))] = right[i];
                }
                if (!error) written += count;
                __atomic_store_n(&status.reply.written, written, __ATOMIC_RELEASE);
                if (first && (error || !count)) __atomic_store_n(&status.reply.failed_seq, seq, __ATOMIC_RELEASE);
                else __atomic_store_n(&status.reply.ready_seq, seq, __ATOMIC_RELEASE);
                if (error || !count || written > UINT32_MAX - CHUNK) __atomic_store_n(&status.reply.total, written, __ATOMIC_RELEASE);
                first = 0;
            }
            radio_native_unlock();
            if (error || !count || written > UINT32_MAX - CHUNK) { ExtAudioFileDispose(current); current = NULL; }
            continue;
        }
        if (cut && current) { ExtAudioFileDispose(current); current = NULL; }
wait:
        radio_native_lock();
        if (!quitting) {
            struct timespec deadline; clock_gettime(CLOCK_REALTIME, &deadline);
            deadline.tv_nsec += 20000000;
            if (deadline.tv_nsec >= 1000000000) { deadline.tv_sec++; deadline.tv_nsec -= 1000000000; }
            pthread_cond_timedwait(&changed, &mutex, &deadline);
        }
        radio_native_unlock();
    } }
    if (current) ExtAudioFileDispose(current);
    return NULL;
} }
void radio_native_init(void) {
    radio_native_lock();
    if (!initialized) {
        const char *path = getenv("NFSU2_MUSIC_FOLDER"), *enabled = getenv("NFSU2_RADIO");
        folder = path && path[0] == '/' ? [NSString stringWithUTF8String:path] : nil;
        quitting = 0; wanted = enabled && !strcmp(enabled, "1") && folder.length;
        paused = 0; shuffled = 0; epoch++;
        if (!exit_registered) { atexit(radio_native_shutdown); exit_registered = 1; }
        if (folder.length) { running = pthread_create(&worker, NULL, decode_worker, NULL) == 0; if (!running) wanted = 0; }
        __atomic_store_n(&initialized, 1, __ATOMIC_RELEASE);
    }
    radio_native_unlock();
}
void radio_native_shutdown(void) {
    radio_native_lock();
    int join = running;
    wanted = 0; quitting = 1; epoch++; off_locked();
    radio_native_unlock();
    if (join) pthread_join(worker, NULL);
    radio_native_lock();
    running = 0; rings = NULL; ring_frames = 0; tracks_count = 0;
    __atomic_store_n(&initialized, 0, __ATOMIC_RELEASE);
    memset(&status, 0, sizeof status); status.radio_magic = RADIO_MAGIC; status.radio_version = RADIO_VERSION;
    memset(playing_tags, 0, sizeof playing_tags); playing_seq = 0; cut_seq = 0;
    folder = nil;
    radio_native_unlock();
}
