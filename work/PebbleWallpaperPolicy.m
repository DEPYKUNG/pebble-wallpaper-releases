#import "PebbleWallpaperPolicy.h"
static NSString *CanonicalPath(NSURL *url) {
    return url.isFileURL ? url.URLByStandardizingPath.URLByResolvingSymlinksInPath.path : nil;
}
BOOL PebbleWallpaperURLIsManaged(NSURL *url, NSArray<NSURL *> *ownedURLs, NSString *lastManagedURL, NSURL *staticDirectory) {
    NSString *path = CanonicalPath(url);
    if (!path) return NO;
    for (NSURL *owned in ownedURLs) if ([path isEqual:CanonicalPath(owned)]) return YES;
    if ([lastManagedURL isKindOfClass:NSString.class] && [path isEqual:CanonicalPath([NSURL URLWithString:lastManagedURL])]) return YES;
    return [url.pathExtension.lowercaseString isEqual:@"png"] &&
        [CanonicalPath(url.URLByDeletingLastPathComponent) isEqual:CanonicalPath(staticDirectory)];
}
PebbleWallpaperAction PebbleWallpaperPlan(NSURL *current, NSURL *desired, BOOL managed, BOOL hasOriginal, BOOL blocked, BOOL explicitChange) {
    if (!current) return PebbleWallpaperNothing;
    if (managed) {
        if (desired) return [CanonicalPath(current) isEqual:CanonicalPath(desired)] ? PebbleWallpaperNothing : PebbleWallpaperInstall;
        return hasOriginal ? PebbleWallpaperRestore : PebbleWallpaperNothing;
    }
    if ((hasOriginal || blocked) && !(explicitChange && desired)) return PebbleWallpaperRespectUser;
    return desired ? PebbleWallpaperCaptureAndInstall : PebbleWallpaperNothing;
}
