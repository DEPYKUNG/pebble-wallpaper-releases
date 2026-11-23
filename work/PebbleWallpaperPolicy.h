#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, PebbleWallpaperAction) {
    PebbleWallpaperNothing, PebbleWallpaperInstall, PebbleWallpaperCaptureAndInstall,
    PebbleWallpaperRestore, PebbleWallpaperRespectUser
};
BOOL PebbleWallpaperURLIsManaged(NSURL *url, NSArray<NSURL *> *ownedURLs, NSString *lastManagedURL, NSURL *staticDirectory);
PebbleWallpaperAction PebbleWallpaperPlan(NSURL *current, NSURL *desired, BOOL managed, BOOL hasOriginal, BOOL blocked, BOOL explicitChange);
