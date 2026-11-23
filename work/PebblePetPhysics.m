#import "PebblePetPhysics.h"
#import <math.h>

NSRect PebblePetConstrainFrame(NSRect frame, NSRect visible) {
    if (!isfinite(frame.origin.x)) frame.origin.x=NSMinX(visible);
    if (!isfinite(frame.origin.y)) frame.origin.y=NSMinY(visible);
    frame.origin.x=MAX(NSMinX(visible),MIN(frame.origin.x,NSMaxX(visible)-NSWidth(frame)));
    frame.origin.y=MAX(NSMinY(visible),MIN(frame.origin.y,NSMaxY(visible)-NSHeight(frame)));
    return frame;
}

PebblePetBody PebblePetAdvance(PebblePetBody body, NSRect visible, NSSize size, double elapsed) {
    double dt=isfinite(elapsed)?MAX(0,MIN(.05,elapsed)):0;
    if (!isfinite(body.velocity.x)) body.velocity.x=0;
    if (!isfinite(body.velocity.y)) body.velocity.y=0;
    body.velocity.x=MAX(-900,MIN(900,body.velocity.x));
    body.velocity.y=MAX(-1100,MIN(1100,body.velocity.y));
    body.velocity.y-=1400*dt;
    NSPoint proposed=NSMakePoint(body.position.x+body.velocity.x*dt,body.position.y+body.velocity.y*dt);
    NSRect bounded=PebblePetConstrainFrame((NSRect){proposed,size},visible);
    if (proposed.x!=bounded.origin.x) body.velocity.x*=-.45;
    if (proposed.y<NSMinY(visible)) {
        body.velocity.y=fabs(body.velocity.y)>95 ? fabs(body.velocity.y)*.36 : 0;
        body.velocity.x*=exp(-8*dt);
    } else if (proposed.y!=bounded.origin.y) body.velocity.y=-fabs(body.velocity.y)*.35;
    body.position=bounded.origin;
    body.resting=body.position.y<=NSMinY(visible)+.1 && fabs(body.velocity.y)<1 && fabs(body.velocity.x)<5;
    if (body.resting) body.velocity=NSZeroPoint;
    return body;
}

NSDictionary *PebblePetPlacement(NSRect frame, NSScreen *screen) {
    NSRect visible=screen.visibleFrame;
    double span=MAX(1,NSWidth(visible)-NSWidth(frame));
    double x=MAX(0,MIN(1,(NSMinX(frame)-NSMinX(visible))/span));
    return @{@"display":screen.deviceDescription[@"NSScreenNumber"] ?: @0,@"x":@(x)};
}

NSRect PebblePetRestoreFrame(id placement, NSArray<NSScreen *> *screens, NSSize size) {
    NSScreen *screen=screens.firstObject;
    if (!screen) return (NSRect){NSZeroPoint,size};
    double x=.84;
    if ([placement isKindOfClass:NSDictionary.class]) {
        for (NSScreen *candidate in screens) {
            if ([candidate.deviceDescription[@"NSScreenNumber"] isEqual:placement[@"display"]]) {screen=candidate;break;}
        }
        id saved=placement[@"x"];
        if ([saved isKindOfClass:NSNumber.class] && isfinite([saved doubleValue])) x=MAX(0,MIN(1,[saved doubleValue]));
    }
    NSRect visible=screen.visibleFrame;
    return PebblePetConstrainFrame(NSMakeRect(NSMinX(visible)+MAX(0,NSWidth(visible)-size.width)*x,
        NSMinY(visible),size.width,size.height),visible);
}

BOOL PebblePetShouldSkip(NSPoint velocity) {
    return isfinite(velocity.x) && isfinite(velocity.y) && fabs(velocity.x)>=280 &&
           fabs(velocity.y)<=MAX(180,fabs(velocity.x)*.5);
}
PebblePetSkip PebblePetBeginSkip(PebblePetBody body, NSRect visible, NSSize size, NSUInteger limit) {
    body.position=PebblePetConstrainFrame((NSRect){body.position,size},visible).origin;
    double vx=isfinite(body.velocity.x)?body.velocity.x:0;
    double direction=vx<0?-1:1;
    body.velocity=NSMakePoint(direction*MAX(320,MIN(900,fabs(vx))),190);
    body.resting=NO;
    return (PebblePetSkip){body,body.position.y,190,0,MAX(3,MIN(7,limit)),YES};
}
PebblePetSkip PebblePetAdvanceSkip(PebblePetSkip skip, NSRect visible, NSSize size, double elapsed) {
    if(!skip.active)return skip;
    double dt=isfinite(elapsed)?MAX(0,MIN(.05,elapsed)):0;
    skip.waterline=MAX(NSMinY(visible),MIN(NSMaxY(visible)-size.height,skip.waterline));
    skip.body.velocity.y-=1100*dt;
    NSPoint proposed=NSMakePoint(skip.body.position.x+skip.body.velocity.x*dt,
                                skip.body.position.y+skip.body.velocity.y*dt);
    NSRect bounded=PebblePetConstrainFrame((NSRect){proposed,size},visible);
    if(proposed.x!=bounded.origin.x){
        skip.active=NO;skip.body.velocity.x*=-.25;
    } else if(proposed.y<=skip.waterline && skip.body.velocity.y<0) {
        bounded.origin.y=skip.waterline;skip.bounces++;
        if(skip.bounces>=skip.limit || fabs(skip.body.velocity.x)<180) {
            skip.active=NO;skip.body.velocity=NSMakePoint(skip.body.velocity.x*.3,55);
        } else {
            skip.hop*=.8;skip.body.velocity.x*=.84;
            skip.body.velocity.y=MAX(65,skip.hop);
        }
    } else if(proposed.y>NSMaxY(visible)-size.height) skip.body.velocity.y=-fabs(skip.body.velocity.y)*.3;
    skip.body.position=bounded.origin;skip.body.resting=NO;
    return skip;
}
NSRect PebblePetBubbleFrame(NSRect anchor, NSRect visible, NSSize size) {
    size.width=MIN(size.width,MAX(1,NSWidth(visible)-12));
    size.height=MIN(size.height,MAX(1,NSHeight(visible)-12));
    NSRect frame=NSMakeRect(NSMidX(anchor)-size.width/2,NSMaxY(anchor)+2,size.width,size.height);
    if(NSMaxY(frame)>NSMaxY(visible))frame.origin.y=NSMinY(anchor)-size.height-2;
    return PebblePetConstrainFrame(frame,NSInsetRect(visible,4,4));
}
