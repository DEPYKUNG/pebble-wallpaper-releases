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

 CHECK(PebblePetShouldSkip(NSMakePoint(600,100)));CHECK(PebblePetShouldSkip(NSMakePoint(-600,-100)));
 CHECK(!PebblePetShouldSkip(NSMakePoint(200,0)));CHECK(!PebblePetShouldSkip(NSMakePoint(600,500)));
 CHECK(!PebblePetShouldSkip(NSMakePoint(NAN,0)));
 NSRect water=NSMakeRect(-3200,30,6400,1600);
 for(NSNumber *limit in @[@3,@5,@7]){
   PebblePetSkip skip=PebblePetBeginSkip((PebblePetBody){NSMakePoint(-2600,330),NSMakePoint(900,0),NO},water,size,limit.unsignedIntegerValue);
   NSUInteger last=0;double firstX=skip.body.position.x;
   for(int i=0;i<1000 && skip.active;i++){
     skip=PebblePetAdvanceSkip(skip,water,size,1.0/60);
     CHECK(NSContainsRect(water,(NSRect){skip.body.position,size}));
     CHECK(skip.bounces>=last&&skip.bounces<=limit.unsignedIntegerValue);last=skip.bounces;
     CHECK(skip.body.position.y>=skip.waterline-.01);
     if(skip.sliding)CHECK(skip.body.position.y==skip.waterline && skip.body.velocity.y==0);
   }
   CHECK(!skip.active && skip.bounces==limit.unsignedIntegerValue);CHECK(skip.body.position.x-firstX>200);
   CHECK(skip.sliding && skip.body.resting && skip.body.position.y==NSMinY(water));
   body=skip.body;for(int i=0;i<1000;i++)body=PebblePetAdvance(body,water,size,.033);
   CHECK(body.resting&&body.position.y==NSMinY(water));
 }
 PebblePetSkip high=PebblePetBeginSkip((PebblePetBody){NSMakePoint(-1700,330),NSMakePoint(500,-110),NO},water,size,3);
 CHECK(high.body.velocity.y==-110 && high.waterline==NSMinY(water));
 for(int i=0;i<500 && high.bounces==0;i++)high=PebblePetAdvanceSkip(high,water,size,.016);
 CHECK(high.bounces==1 && high.impactPosition.y==NSMinY(water) && high.impactPosition.x>-1550);
 PebblePetSkip edge=PebblePetBeginSkip((PebblePetBody){NSMakePoint(NSMaxX(visible)-size.width,100),NSMakePoint(900,0),NO},visible,size,5);
 edge=PebblePetAdvanceSkip(edge,visible,size,.05);CHECK(!edge.active&&edge.bounces==0);
 for(NSValue *point in @[[NSValue valueWithPoint:NSMakePoint(-1920,30)],[NSValue valueWithPoint:NSMakePoint(-220,870)]]){
   NSRect bubble=PebblePetBubbleFrame((NSRect){point.pointValue,size},visible,NSMakeSize(240,100));
   CHECK(NSContainsRect(visible,bubble));
 }
 NSLog(@"Skipping: 3/5/7 diminishing hops, gesture gate, virtual waterline, edges, settling and bubble bounds verified.");
 NSLog(@"Pet gravity, bounded throws, rebound/settle, negative display coordinates, malformed placement, restore and 10000 random bounds verified.");
}return 0;}
'''
with TemporaryDirectory(prefix='pebble-pet-test-') as tmp:
    root=Path(tmp);(root/'test.m').write_text(source)
    subprocess.run(['clang','-fobjc-arc','-framework','AppKit','-I',str(work),str(work/'PebblePetPhysics.m'),str(root/'test.m'),'-o',str(root/'test')],check=True)
    subprocess.run([str(root/'test')],check=True)
