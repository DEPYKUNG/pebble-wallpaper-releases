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
