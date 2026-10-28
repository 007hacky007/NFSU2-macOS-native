#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

const char *app_save_dir(void);

int main(void) { @autoreleasepool {
    char home[] = "/tmp/nfsu2-save-path-XXXXXX";
    assert(mkdtemp(home));
    setenv("HOME", home, 1);
    unsetenv("NFSU2_SAVEDIR");
    char expected[1200];
    snprintf(expected, sizeof expected, "%s/Library/Application Support/NFSU2 Saves", home);
    NSString *old = [@(home) stringByAppendingPathComponent:@"Library/Application Support/NFSU2 Kayitlar"];
    [[NSFileManager defaultManager] createDirectoryAtPath:old withIntermediateDirectories:YES attributes:nil error:nil];
    [@"saved profile" writeToFile:[old stringByAppendingPathComponent:@"profile"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    const char *path = app_save_dir();
    assert(path && !strcmp(path, expected));
    assert(access(expected, F_OK) == 0);
    assert(![[NSFileManager defaultManager] fileExistsAtPath:old]);
    assert([[NSFileManager defaultManager] fileExistsAtPath:[@(expected) stringByAppendingPathComponent:@"profile"]]);
    [[NSFileManager defaultManager] removeItemAtPath:@(expected) error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:old withIntermediateDirectories:YES attributes:nil error:nil];
    setenv("NFSU2_SAVEDIR", expected, 1);
    assert(!strcmp(app_save_dir(), expected));
    assert(![[NSFileManager defaultManager] fileExistsAtPath:old]);
    [[NSFileManager defaultManager] createDirectoryAtPath:old withIntermediateDirectories:YES attributes:nil error:nil];
    assert(!strcmp(app_save_dir(), expected));
    assert([[NSFileManager defaultManager] fileExistsAtPath:old]);
    setenv("NFSU2_SAVEDIR", "/tmp/nfsu2-explicit-overlay", 1);
    assert(!strcmp(app_save_dir(), "/tmp/nfsu2-explicit-overlay"));
    [[NSFileManager defaultManager] removeItemAtPath:@(home) error:nil];
    puts("PASS legacy save path outside bundles and explicit override");
} }
