"""Test native-wallpaper ownership and transition policy without NSWorkspace writes."""
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
work = Path(__file__).resolve().parent
source = r'''
#import <Foundation/Foundation.h>
#import "PebbleWallpaperPolicy.h"
#define CHECK(x) do { if (!(x)) { NSLog(@"Policy failed at line %d",__LINE__); return 1; } } while(0)
int main(void) { @autoreleasepool {
 NSURL *stable=[NSURL fileURLWithPath:@"/Users/test/Library/Application Support/Pebble Wallpaper/Desktop Backgrounds/desktop-base-nord0.png"];
 NSURL *other=[NSURL fileURLWithPath:@"/Users/test/Pictures/desktop-base-nord0.png"];
 NSURL *original=[NSURL fileURLWithPath:@"/Users/test/Pictures/original.jpg"];
 NSURL *next=[NSURL fileURLWithPath:@"/Users/test/Library/Application Support/Pebble Wallpaper/Desktop Backgrounds/desktop-base-nord3.png"];
 NSURL *staticDir=[NSURL fileURLWithPath:@"/Users/test/Library/Application Support/Pebble Wallpaper/Static Wallpapers" isDirectory:YES];
 CHECK(PebbleWallpaperURLIsManaged(stable,@[stable],nil,staticDir));
 CHECK(!PebbleWallpaperURLIsManaged(other,@[stable],nil,staticDir));
 CHECK(PebbleWallpaperURLIsManaged(other,@[],other.absoluteString,staticDir));
 CHECK(PebbleWallpaperURLIsManaged([staticDir URLByAppendingPathComponent:@"snapshot.png"],@[],nil,staticDir));
 CHECK(!PebbleWallpaperURLIsManaged([staticDir URLByAppendingPathComponent:@"other/snapshot.png"],@[],nil,staticDir));
 CHECK(PebbleWallpaperPlan(original,stable,NO,NO,NO,NO)==PebbleWallpaperCaptureAndInstall);
 CHECK(PebbleWallpaperPlan(stable,stable,YES,YES,NO,NO)==PebbleWallpaperNothing);
 CHECK(PebbleWallpaperPlan(stable,next,YES,YES,NO,NO)==PebbleWallpaperInstall);
 CHECK(PebbleWallpaperPlan(stable,nil,YES,YES,NO,NO)==PebbleWallpaperRestore);
 CHECK(PebbleWallpaperPlan(stable,nil,YES,NO,NO,NO)==PebbleWallpaperNothing);
 CHECK(PebbleWallpaperPlan(other,stable,NO,YES,NO,NO)==PebbleWallpaperRespectUser);
 CHECK(PebbleWallpaperPlan(other,nil,NO,YES,NO,NO)==PebbleWallpaperRespectUser);
 CHECK(PebbleWallpaperPlan(other,stable,NO,NO,YES,NO)==PebbleWallpaperRespectUser);
 CHECK(PebbleWallpaperPlan(other,stable,NO,YES,YES,YES)==PebbleWallpaperCaptureAndInstall);
 CHECK(PebbleWallpaperPlan(nil,stable,NO,YES,NO,NO)==PebbleWallpaperNothing);
 NSLog(@"Stable ownership, same-name external images, restart/restore and external-override policy verified.");
} return 0; }
'''
with TemporaryDirectory(prefix='pebble-wallpaper-policy-') as scratch:
    root=Path(scratch);(root/'tests.m').write_text(source)
    subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-I',str(work),str(work/'PebbleWallpaperPolicy.m'),str(root/'tests.m'),'-o',str(root/'tests')],check=True)
    subprocess.run([str(root/'tests')],check=True)
