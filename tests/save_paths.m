/* save_paths.m -- where the game's saves go (runtime/bundle.m app_save_dir):
 * ~/Library/Application Support/NFSU2 Saves, outside the game and the app;
 * saves of the old "NFSU2 Kayitlar" folder are moved there once (never over
 * an existing NFSU2 Saves); NFSU2_SAVEDIR overrides the place and then
 * nothing is moved.  HOME is a private temp folder. */
#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

const char *app_save_dir(void);

int main(void) { @autoreleasepool {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:@"nfsu2-save-path-XXXXXX"];
    char home[1024]; snprintf(home, sizeof home, "%s", base.fileSystemRepresentation);
    assert(mkdtemp(home));
    setenv("HOME", home, 1);
    unsetenv("NFSU2_SAVEDIR");
    char expected[1200];
    snprintf(expected, sizeof expected, "%s/Library/Application Support/NFSU2 Saves", home);
    NSString *old = [@(home) stringByAppendingPathComponent:@"Library/Application Support/NFSU2 Kayitlar"];
    NSString *now = @(expected);

    /* nothing there yet: the path, nothing made or moved */
    assert(!strcmp(app_save_dir(), expected));

    /* the old folder alone: moved over with its files */
    [fm createDirectoryAtPath:old withIntermediateDirectories:YES attributes:nil error:nil];
    [@"saved profile" writeToFile:[old stringByAppendingPathComponent:@"profile"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    assert(!strcmp(app_save_dir(), expected));
    assert(access(expected, F_OK) == 0);
    assert(![fm fileExistsAtPath:old]);
    assert([fm fileExistsAtPath:[now stringByAppendingPathComponent:@"profile"]]);

    /* both there: the new one is kept as it is, the old one left alone */
    [fm createDirectoryAtPath:old withIntermediateDirectories:YES attributes:nil error:nil];
    [@"older profile" writeToFile:[old stringByAppendingPathComponent:@"profile"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    assert(!strcmp(app_save_dir(), expected));
    assert([fm fileExistsAtPath:old]);
    assert([[NSString stringWithContentsOfFile:[now stringByAppendingPathComponent:@"profile"] encoding:NSUTF8StringEncoding error:nil]
            isEqualToString:@"saved profile"]);

    /* NFSU2_SAVEDIR: that folder, and no move */
    [fm removeItemAtPath:now error:nil];
    setenv("NFSU2_SAVEDIR", "/tmp/nfsu2-explicit-overlay", 1);
    assert(!strcmp(app_save_dir(), "/tmp/nfsu2-explicit-overlay"));
    assert([fm fileExistsAtPath:old] && ![fm fileExistsAtPath:now]);
    /* an empty NFSU2_SAVEDIR counts as unset */
    setenv("NFSU2_SAVEDIR", "", 1);
    assert(!strcmp(app_save_dir(), expected));
    assert(![fm fileExistsAtPath:old] && [fm fileExistsAtPath:now]);

    [fm removeItemAtPath:@(home) error:nil];
    puts("save_paths: NFSU2 Saves outside the game, the old NFSU2 Kayitlar moved once (never over saves), NFSU2_SAVEDIR override");
    return 0;
} }
