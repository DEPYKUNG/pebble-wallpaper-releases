"""Exercise the actual native state normalizer without touching user defaults."""
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
work = Path(__file__).resolve().parent
source = r'''
#import <Foundation/Foundation.h>
#import "PebbleState.h"
#import <math.h>
#define CHECK(x) do { if (!(x)) { NSLog(@"Failed line %d", __LINE__); return 1; } } while(0)
int main(void) { @autoreleasepool {
 NSArray *textures = @[@"rings", @"stripes"];
 NSDictionary *legacy = @{@"seed":@42, @"texture":@"rings", @"colors":@[@"#123456",@"#abcdef",@"#ABCDEF"], @"faces":@"on"};
 NSDictionary *migrated = PebbleNormalizeStone(legacy,textures);
 CHECK([migrated[@"schemaVersion"] isEqual:@1]); CHECK([migrated[@"yaw"] isEqual:@0]);
 CHECK([PebbleNormalizeStone(migrated,textures) isEqual:migrated]);
 for (id bad in @[@"bad",NSNull.null,@42,@[]]) CHECK(!PebbleNormalizeStone(bad,textures));
 for (NSDictionary *patch in @[@{@"seed":@YES},@{@"seed":@1.5},@{@"seed":@1000000},@{@"texture":@"missing"},@{@"colors":@"bad"},@{@"colors":@[@"#bad",@"#123456",@"#123456"]},@{@"faces":@YES},@{@"schemaVersion":@2},@{@"yaw":@(NAN)},@{@"pitch":@99}]) {
  NSMutableDictionary *bad=[legacy mutableCopy]; [bad addEntriesFromDictionary:patch]; CHECK(!PebbleNormalizeStone(bad,textures));
 }
 NSMutableDictionary *pose=[migrated mutableCopy]; pose[@"yaw"]=@1.2; pose[@"pitch"]=@.3;
 CHECK([PebbleNormalizeStone(pose,textures) isEqual:pose]);
 CHECK(PebbleNormalizeFavorites(@[legacy,@"bad",migrated,pose],textures).count==1);
 NSDictionary *histories=PebbleNormalizeHistories(@{@"7":@{@"current":legacy,@"previous":@"bad"},@"bad":legacy,@"8":@"bad"},textures);
 CHECK(histories.count==1); CHECK([histories[@"7"][@"current"] isEqual:migrated]);
 CHECK(PebbleNormalizeHistories(@[],textures).count==0); CHECK(PebbleNormalizeFavorites(@{},textures).count==0);
 CHECK([PebbleTargetDisplays(@[@1,@2],@2,YES) isEqual:@[@2]]);
 CHECK(PebbleTargetDisplays(@[@1,@2],@3,YES).count==0);
 CHECK([PebbleTargetDisplays(@[@1,@2],nil,YES) isEqual:(@[@1,@2])]);
 CHECK([PebbleTargetDisplays(@[@1,@2],nil,NO) isEqual:@[@1]]);
 CHECK(PebbleTargetDisplays(@[],nil,NO).count==0);
 NSLog(@"State migration, pose, invalid/future records and mixed persistence fixtures verified.");
} return 0; }
'''
with TemporaryDirectory(prefix='pebble-state-tests-') as scratch:
    root = Path(scratch)
    (root/'tests.m').write_text(source)
    subprocess.run(['clang','-fobjc-arc','-fblocks','-framework','Foundation','-I',str(work),str(work/'PebbleState.m'),str(root/'tests.m'),'-o',str(root/'tests')],check=True)
    subprocess.run([str(root/'tests')],check=True)
