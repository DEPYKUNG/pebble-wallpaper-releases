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
    double vy=isfinite(body.velocity.y)?body.velocity.y:0;
    double floorY=NSMinY(visible);
    double speed=MAX(280,MIN(900,fabs(vx)));
    double lift=MAX(-220,MIN(210,vy));
    if (body.position.y-floorY<12) lift=MAX(lift,130+speed*.075);
    body.velocity=NSMakePoint(copysign(speed,vx),lift);
    body.resting=NO;
    return (PebblePetSkip){.body=body,.waterline=floorY,.limit=MAX(3,MIN(7,limit)),.active=YES};
}

PebblePetSkip PebblePetAdvanceSkip(PebblePetSkip skip, NSRect visible, NSSize size, double elapsed) {
    if (!skip.active) return skip;
    double dt=isfinite(elapsed)?MAX(0,MIN(.05,elapsed)):0;
    if (dt==0) return skip;
    const double gravity=1100;
    skip.waterline=NSMinY(visible);
    NSPoint position=skip.body.position, velocity=skip.body.velocity;
    if (skip.sliding) {
        const double drag=8;
        double decay=exp(-drag*dt);
        position.x+=velocity.x*(1-decay)/drag;
        position.y=skip.waterline;
        velocity.x*=decay;
    } else {
        double height=MAX(0,position.y-skip.waterline);
        double contact=(velocity.y+sqrt(velocity.y*velocity.y+2*gravity*height))/gravity;
        double flight=MIN(dt,contact);
        position.x+=velocity.x*flight;
        position.y+=velocity.y*flight-.5*gravity*flight*flight;
        velocity.y-=gravity*flight;
        if (contact<=dt && position.x>=NSMinX(visible) && position.x<=NSMaxX(visible)-size.width) {
            position.y=skip.waterline;
            skip.impactPosition=position;
            skip.bounces++;
            if (skip.bounces>=skip.limit || fabs(velocity.x)<150) {
                skip.sliding=YES;
                velocity=NSMakePoint(velocity.x*.6,0);
            } else {
                skip.hop=skip.bounces==1?MAX(150,MIN(230,-velocity.y*.48)):skip.hop*.79;
                velocity=NSMakePoint(velocity.x*.85,skip.hop);
            }
        }
    }
    NSRect bounded=PebblePetConstrainFrame((NSRect){position,size},visible);
    if (bounded.origin.x!=position.x) {
        skip.active=NO;
        velocity=NSZeroPoint;
    } else if (skip.sliding && fabs(velocity.x)<5) {
        skip.active=NO;
        velocity=NSZeroPoint;
    } else if (bounded.origin.y<position.y) {
        velocity.y=MIN(0,velocity.y);
    }
    skip.body=(PebblePetBody){bounded.origin,velocity,!skip.active && bounded.origin.y<=skip.waterline};
    return skip;
}
NSRect PebblePetBubbleFrame(NSRect anchor, NSRect visible, NSSize size) {
    size.width=MIN(size.width,MAX(1,NSWidth(visible)-12));
    size.height=MIN(size.height,MAX(1,NSHeight(visible)-12));
    NSRect frame=NSMakeRect(NSMidX(anchor)-size.width/2,NSMaxY(anchor)+2,size.width,size.height);
    if(NSMaxY(frame)>NSMaxY(visible))frame.origin.y=NSMinY(anchor)-size.height-2;
    return PebblePetConstrainFrame(frame,NSInsetRect(visible,4,4));
}
