"""Real native movement/placement tests; does not change production preferences."""
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess

work=Path(__file__).resolve().parent
source=r'''
#import "PebblePetPhysics.h"
#import <math.h>
#define CHECK(x) do {if(!(x)){NSLog(@"Failed line %d: %s",__LINE__,#x);return 1;}}while(0)
int main(){@autoreleasepool{
 NSRect visible=NSMakeRect(-1920,30,1920,1050);NSSize size=NSMakeSize(200,210);
 NSRect bad=NSMakeRect(NAN,INFINITY,200,210),fixed=PebblePetConstrainFrame(bad,visible);
 CHECK(isfinite(fixed.origin.x)&&isfinite(fixed.origin.y));CHECK(NSContainsRect(visible,fixed));
 PebblePetBody body={NSMakePoint(-1000,700),NSMakePoint(900,700),NO};BOOL bounced=NO;
 for(int i=0;i<1200;i++){
   double previous=body.velocity.y;body=PebblePetAdvance(body,visible,size,1.0/30);
   CHECK(NSContainsRect(visible,(NSRect){body.position,size}));
   CHECK(isfinite(body.velocity.x)&&isfinite(body.velocity.y));
   if(previous<0&&body.velocity.y>0)bounced=YES;
 }
 CHECK(bounced&&body.resting);CHECK(body.position.y==30);CHECK(body.velocity.x==0&&body.velocity.y==0);
 body=(PebblePetBody){NSMakePoint(-1920,50),NSMakePoint(-900,-1000),NO};
 body=PebblePetAdvance(body,visible,size,1000);CHECK(body.position.x>=-1920);CHECK(body.velocity.x>=0);
 body.velocity=NSMakePoint(NAN,INFINITY);body=PebblePetAdvance(body,visible,size,NAN);
 CHECK(isfinite(body.velocity.x)&&isfinite(body.position.y));
 for(int i=0;i<10000;i++){
   body=(PebblePetBody){NSMakePoint((int)arc4random_uniform(6000)-4000,(int)arc4random_uniform(3000)-1000),NSMakePoint((int)arc4random_uniform(8000)-4000,(int)arc4random_uniform(8000)-4000),NO};
   body=PebblePetAdvance(body,visible,size,.033);CHECK(NSContainsRect(visible,(NSRect){body.position,size}));
 }
 for(id corrupt in @[[NSNull null],@[],@"bad",@{@"x":@"wrong"},@{@"x":@(NAN)},@{@"display":@"missing",@"x":@100}]){
   NSRect frame=PebblePetRestoreFrame(corrupt,NSScreen.screens,size);CHECK(isfinite(frame.origin.x)&&isfinite(frame.origin.y));
   if(NSScreen.screens.count){BOOL contained=NO;for(NSScreen *screen in NSScreen.screens)if(NSContainsRect(screen.visibleFrame,frame))contained=YES;CHECK(contained);}
 }
 for(NSScreen *screen in NSScreen.screens){NSRect a=PebblePetConstrainFrame(NSMakeRect(NSMinX(screen.visibleFrame)+55,NSMinY(screen.visibleFrame),200,210),screen.visibleFrame);
   NSDictionary *saved=PebblePetPlacement(a,screen);NSRect b=PebblePetRestoreFrame(saved,NSScreen.screens,size);CHECK(fabs(a.origin.x-b.origin.x)<.01);CHECK(a.origin.y==b.origin.y);}
 CHECK(NSEqualSizes(PebblePetRestoreFrame(nil,@[],size).size,size));
 NSLog(@"Pet gravity, bounded throws, rebound/settle, negative display coordinates, malformed placement, restore and 10000 random bounds verified.");
}return 0;}
'''
with TemporaryDirectory(prefix='pebble-pet-test-') as tmp:
    root=Path(tmp);(root/'test.m').write_text(source)
    subprocess.run(['clang','-fobjc-arc','-framework','AppKit','-I',str(work),str(work/'PebblePetPhysics.m'),str(root/'test.m'),'-o',str(root/'test')],check=True)
    subprocess.run([str(root/'test')],check=True)
