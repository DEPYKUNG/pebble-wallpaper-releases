#import "PebblePet.h"
#import "PebblePetPhysics.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static NSString *const PetPlacementKey=@"DesktopPetPlacement";
static const CGFloat PetSizes[]={112,156,204};
@class PebblePetView;
@interface PebblePetPanel : NSPanel @end
@implementation PebblePetPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface PebblePetController ()
@property (nonatomic, readwrite) NSPanel *panel;
@property (nonatomic, readwrite) BOOL dragging;
@property (nonatomic, readwrite) NSImage *stoneImage;
@property NSUserDefaults *defaults;
@property PebblePetView *petView;
@property NSBitmapImageRep *bitmap;
@property NSTimer *timer;
@property (nonatomic) BOOL suspended,invalidated,moved,menuOpen;
@property NSPoint downMouse,downOrigin,lastMouse;
@property NSTimeInterval lastSample,lastTick,nextWander,celebrateUntil;
@property NSPoint throwVelocity;
@property PebblePetBody body;
@property CGFloat angle,stretch;
- (void)tick:(NSTimer *)timer;
- (void)beginDrag;
- (void)continueDrag;
- (void)endDrag;
- (NSMenu *)petMenu;

- (NSRect)artRect;
@end
@interface PebblePetView : NSView
@property (weak) PebblePetController *owner;
@end
@implementation PebblePetView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)dirty {
    PebblePetController *owner=self.owner;
    if (!owner.stoneImage) return;
    NSRect art=[owner artRect];
    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow=[NSShadow new];shadow.shadowColor=[NSColor colorWithWhite:0 alpha:.22];
    shadow.shadowBlurRadius=8;shadow.shadowOffset=NSMakeSize(0,-3);[shadow set];
    NSAffineTransform *transform=[NSAffineTransform transform];
    [transform translateXBy:NSMidX(art) yBy:NSMidY(art)];
    [transform rotateByDegrees:owner.angle];
    [transform scaleXBy:1/owner.stretch yBy:owner.stretch];
    [transform translateXBy:-NSMidX(art) yBy:-NSMidY(art)];[transform concat];
    [owner.stoneImage drawInRect:art fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    [NSGraphicsContext restoreGraphicsState];
    if (owner.celebrateUntil>CACurrentMediaTime()) {
        CGFloat progress=1-(owner.celebrateUntil-CACurrentMediaTime())/.7;
        [[NSColor.labelColor colorWithAlphaComponent:MAX(0,1-progress)*.65] setStroke];
        for (NSUInteger i=0;i<3;i++) {
            CGFloat a=(35+i*55)*M_PI/180;
            NSPoint center=NSMakePoint(NSMidX(art)+cos(a)*(NSWidth(art)*.43+progress*12),
                                      NSMidY(art)+sin(a)*(NSHeight(art)*.45+progress*12));
            NSBezierPath *ray=[NSBezierPath bezierPath];ray.lineWidth=1.8;
            [ray moveToPoint:center];[ray lineToPoint:NSMakePoint(center.x+cos(a)*6,center.y+sin(a)*6)];[ray stroke];
        }
    }
}
- (void)mouseDown:(NSEvent *)event { [self.owner beginDrag]; }
- (void)mouseDragged:(NSEvent *)event { [self.owner continueDrag]; }
- (void)mouseUp:(NSEvent *)event { [self.owner endDrag]; }
- (void)rightMouseDown:(NSEvent *)event {
    self.owner.menuOpen=YES;
    [NSMenu popUpContextMenu:self.owner.petMenu withEvent:event forView:self];
    self.owner.menuOpen=NO;self.owner.nextWander=CACurrentMediaTime()+10;
    if(self.owner.interactionEnded)self.owner.interactionEnded();
}
- (NSArray<NSAccessibilityActionName> *)accessibilityActionNames {return @[NSAccessibilityPressAction];}
- (BOOL)accessibilityPerformPress { [self.owner greet:nil];return YES; }
@end

@implementation PebblePetController
- (BOOL)interacting {return self.dragging || self.menuOpen;}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if (!(self=[super init])) return nil;
    _defaults=defaults;_roaming=![defaults boolForKey:@"DesktopPetQuiet"];
    _sizeIndex=[defaults objectForKey:@"DesktopPetSize"]?MAX(0,MIN(2,[defaults integerForKey:@"DesktopPetSize"])):1;
    CGFloat size=PetSizes[_sizeIndex];NSSize windowSize=NSMakeSize(size+48,size+52);
    NSRect frame=PebblePetRestoreFrame([defaults objectForKey:PetPlacementKey],NSScreen.screens,windowSize);
    _panel=[[PebblePetPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    _panel.title=@"鹅卵石桌宠";_panel.releasedWhenClosed=NO;
    _panel.opaque=NO;_panel.backgroundColor=NSColor.clearColor;_panel.hasShadow=NO;
    _panel.level=NSFloatingWindowLevel;_panel.hidesOnDeactivate=NO;
    _panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorIgnoresCycle;
    _petView=[[PebblePetView alloc] initWithFrame:(NSRect){NSZeroPoint,windowSize}];_petView.owner=self;
    _petView.toolTip=@"点一下打招呼 · 拖动后松手可轻抛 · 右键打开桌宠菜单";
    _petView.accessibilityElement=YES;_petView.accessibilityRole=NSAccessibilityButtonRole;
    _petView.accessibilityLabel=@"鹅卵石桌宠";_petView.accessibilityHelp=_petView.toolTip;
    _panel.contentView=_petView;_stretch=1;_body=(PebblePetBody){frame.origin,NSZeroPoint,YES};
    _nextWander=CACurrentMediaTime()+8;
    return self;
}
- (NSRect)artRect {
    NSRect frame=NSInsetRect(self.petView.bounds,24,26);
    NSSize image=self.stoneImage.size;
    if (image.width>0 && image.height>0) {
        CGFloat scale=MIN(NSWidth(frame)/image.width,NSHeight(frame)/image.height);
        frame=NSMakeRect(NSMidX(frame)-image.width*scale/2,NSMinY(frame),image.width*scale,image.height*scale);
    }
    return frame;
}
- (BOOL)setStonePNG:(NSData *)data {
    if (self.invalidated || data.length>4*1024*1024) return NO;
    NSBitmapImageRep *source=data?[NSBitmapImageRep imageRepWithData:data]:nil;
    if (!source || !source.hasAlpha || source.pixelsWide<32 || source.pixelsWide>1024 || source.pixelsHigh>1024) return NO;
    NSInteger minX=source.pixelsWide,minY=source.pixelsHigh,maxX=-1,maxY=-1;
    for (NSInteger y=0;y<source.pixelsHigh;y++) for (NSInteger x=0;x<source.pixelsWide;x++) {
        if ([source colorAtX:x y:y].alphaComponent>.08) {minX=MIN(minX,x);minY=MIN(minY,y);maxX=MAX(maxX,x);maxY=MAX(maxY,y);}
    }
    if (maxX<minX || maxY<minY) return NO;
    CGImageRef cropped=CGImageCreateWithImageInRect(source.CGImage,CGRectMake(minX,minY,maxX-minX+1,maxY-minY+1));
    if (!cropped) return NO;
    self.bitmap=[[NSBitmapImageRep alloc] initWithCGImage:cropped];
    self.stoneImage=[[NSImage alloc] initWithCGImage:cropped size:NSMakeSize(CGImageGetWidth(cropped)/2.0,CGImageGetHeight(cropped)/2.0)];
    CGImageRelease(cropped);
    self.petView.needsDisplay=YES;
    [self setSuspended:self.suspended];return YES;
}
- (void)setRoaming:(BOOL)roaming {
    _roaming=roaming;[self.defaults setBool:!roaming forKey:@"DesktopPetQuiet"];
    self.nextWander=CACurrentMediaTime()+8;
    if(self.interactionEnded)self.interactionEnded();
}
- (void)setSizeIndex:(NSInteger)index {
    _sizeIndex=MAX(0,MIN(2,index));[self.defaults setInteger:_sizeIndex forKey:@"DesktopPetSize"];
    NSRect frame=self.panel.frame;CGFloat center=NSMidX(frame);
    frame.size=NSMakeSize(PetSizes[_sizeIndex]+48,PetSizes[_sizeIndex]+52);frame.origin.x=center-frame.size.width/2;
    frame=PebblePetConstrainFrame(frame,(self.panel.screen ?: NSScreen.screens.firstObject).visibleFrame);
    [self.panel setFrame:frame display:YES];self.body=(PebblePetBody){frame.origin,NSZeroPoint,NO};
    [self savePlacement];self.petView.needsDisplay=YES;
    if(self.interactionEnded)self.interactionEnded();
}
- (void)setSuspended:(BOOL)suspended {
    _suspended=suspended;[self.timer invalidate];self.timer=nil;
    if (suspended) {self.dragging=NO;self.menuOpen=NO;self.body=(PebblePetBody){self.panel.frame.origin,NSZeroPoint,NO};}
    if (suspended || self.invalidated || !self.stoneImage) {[self.panel orderOut:nil];return;}
    self.lastTick=CACurrentMediaTime();self.nextWander=self.lastTick+8;
    __weak typeof(self) weakSelf=self;
    BOOL reduced=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion||NSProcessInfo.processInfo.lowPowerModeEnabled;
    self.timer=[NSTimer timerWithTimeInterval:reduced?.1:1.0/30 repeats:YES block:^(NSTimer *timer){[weakSelf tick:timer];}];
    self.timer.tolerance=.006;[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self.panel orderFrontRegardless];[self tick:nil];
}
- (BOOL)containsStoneAtScreenPoint:(NSPoint)point {
    if (!self.bitmap) return NO;
    NSPoint p=NSMakePoint(point.x-NSMinX(self.panel.frame),point.y-NSMinY(self.panel.frame));
    NSRect art=self.artRect;
    // Reverse the same transform used to draw, so transparent corners pass clicks through.
    double angle=-self.angle*M_PI/180,x=p.x-NSMidX(art),y=p.y-NSMidY(art);
    p=NSMakePoint((x*cos(angle)-y*sin(angle))*self.stretch+NSMidX(art),
                  (x*sin(angle)+y*cos(angle))/self.stretch+NSMidY(art));
    if (!NSPointInRect(p,art)) return NO;
    NSInteger px=MAX(0,MIN(self.bitmap.pixelsWide-1,(p.x-NSMinX(art))/NSWidth(art)*self.bitmap.pixelsWide));
    NSInteger py=MAX(0,MIN(self.bitmap.pixelsHigh-1,(1-(p.y-NSMinY(art))/NSHeight(art))*self.bitmap.pixelsHigh));
    return [self.bitmap colorAtX:px y:py].alphaComponent>.08;
}
- (void)tick:(NSTimer *)timer {
    double now=CACurrentMediaTime(),dt=MIN(.05,MAX(0,now-self.lastTick));self.lastTick=now;
    BOOL reduced=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion||NSProcessInfo.processInfo.lowPowerModeEnabled;
    NSRect visible=(self.panel.screen ?: NSScreen.screens.firstObject).visibleFrame;
    if (!self.interacting) {
        PebblePetBody body=self.body;
        if (body.resting && self.roaming && !reduced && now>self.nextWander) {
            double direction=NSMidX(self.panel.frame)>NSMidX(visible)?-1:1;
            body.velocity=NSMakePoint(direction*(45+arc4random_uniform(45)),150);body.resting=NO;
            self.nextWander=now+10+arc4random_uniform(10);
        }
        if (!body.resting) {
            BOOL wasResting=body.resting;body=PebblePetAdvance(body,visible,self.panel.frame.size,dt);
            [self.panel setFrameOrigin:body.position];self.body=body;
            if (!wasResting && body.resting) [self savePlacement];
        }
        CGFloat desiredAngle=body.resting?(reduced?0:sin(now*1.3)*1.2):MAX(-12,MIN(12,-body.velocity.x*.05));
        self.angle+=(desiredAngle-self.angle)*MIN(1,dt*10);
        self.stretch=reduced?1:1+sin(now*2.1)*.009;
    }
    self.panel.ignoresMouseEvents=!self.dragging && ![self containsStoneAtScreenPoint:NSEvent.mouseLocation];
    if (!reduced || !self.body.resting || self.celebrateUntil>now) self.petView.needsDisplay=YES;
}
- (void)beginDrag {[self beginDragAtPoint:NSEvent.mouseLocation time:CACurrentMediaTime()];}
- (void)beginDragAtPoint:(NSPoint)point time:(NSTimeInterval)now {
    self.dragging=YES;self.moved=NO;self.downMouse=self.lastMouse=point;
    self.downOrigin=self.panel.frame.origin;self.lastSample=now;self.throwVelocity=NSZeroPoint;
    self.body=(PebblePetBody){self.panel.frame.origin,NSZeroPoint,NO};self.stretch=1.035;
    self.panel.ignoresMouseEvents=NO;
}
- (void)continueDrag {[self dragToPoint:NSEvent.mouseLocation time:CACurrentMediaTime()];}
- (void)dragToPoint:(NSPoint)mouse time:(NSTimeInterval)now {
    if (hypot(mouse.x-self.downMouse.x,mouse.y-self.downMouse.y)>3) self.moved=YES;
    NSScreen *screen=self.panel.screen ?: NSScreen.screens.firstObject;
    for (NSScreen *candidate in NSScreen.screens) if (NSPointInRect(mouse,candidate.frame)) {screen=candidate;break;}
    NSRect frame=self.panel.frame;frame.origin=NSMakePoint(self.downOrigin.x+mouse.x-self.downMouse.x,self.downOrigin.y+mouse.y-self.downMouse.y);
    frame=PebblePetConstrainFrame(frame,screen.visibleFrame);[self.panel setFrameOrigin:frame.origin];
    double dt=MAX(.008,now-self.lastSample);
    self.throwVelocity=NSMakePoint(MAX(-900,MIN(900,(mouse.x-self.lastMouse.x)/dt)),MAX(-1100,MIN(1100,(mouse.y-self.lastMouse.y)/dt)));
    self.lastMouse=mouse;self.lastSample=now;self.angle=MAX(-10,MIN(10,-self.throwVelocity.x*.008));self.petView.needsDisplay=YES;
}
- (void)endDrag {[self endDragAtTime:CACurrentMediaTime()];}
- (void)endDragAtTime:(NSTimeInterval)now {
    self.dragging=NO;
    NSPoint velocity=now-self.lastSample>.12?NSZeroPoint:self.throwVelocity;
    self.body=(PebblePetBody){self.panel.frame.origin,velocity,NO};self.stretch=1;
    if (!self.moved) [self greet:nil];else if(self.syncStone) self.syncStone();
    [self savePlacement];if (self.interactionEnded) self.interactionEnded();
}
- (void)greet:(id)sender {
    BOOL reduced=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    self.body=(PebblePetBody){self.panel.frame.origin,reduced?NSZeroPoint:NSMakePoint(0,360),reduced};
    self.celebrateUntil=CACurrentMediaTime()+.7;self.nextWander=CACurrentMediaTime()+12;self.petView.needsDisplay=YES;
}
- (void)summon:(id)sender {
    NSScreen *screen=NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    NSRect frame=self.panel.frame,visible=screen.visibleFrame;
    frame.origin=NSMakePoint(NSMaxX(visible)-NSWidth(frame)-28,NSMinY(visible));
    frame=PebblePetConstrainFrame(frame,visible);[self.panel setFrame:frame display:YES];
    self.body=(PebblePetBody){frame.origin,NSZeroPoint,YES};[self savePlacement];
    if (!self.suspended && self.stoneImage) [self.panel orderFrontRegardless];
}
- (void)refreshScreens {
    if (!NSScreen.screens.count) {[self setSuspended:YES];return;}
    NSScreen *screen=self.panel.screen;
    if (!screen) {[self summon:nil];return;}
    NSRect frame=PebblePetConstrainFrame(self.panel.frame,screen.visibleFrame);
    [self.panel setFrame:frame display:YES];self.body=(PebblePetBody){frame.origin,NSZeroPoint,NO};
}
- (void)savePlacement {
    if (self.panel.screen) [self.defaults setObject:PebblePetPlacement(self.panel.frame,self.panel.screen) forKey:PetPlacementKey];
}
- (void)toggleQuiet:(id)sender {self.roaming=!self.roaming;}
- (void)selectSize:(NSMenuItem *)sender {self.sizeIndex=sender.tag;}
- (void)syncFromMenu:(id)sender {if(self.syncStone) self.syncStone();}
- (void)showSettings:(id)sender {if(self.openSettings)self.openSettings();}
- (void)dismiss:(id)sender {if(self.dismissPet) self.dismissPet();}
- (NSMenu *)petMenu {
    NSMenu *menu=[NSMenu new];
    NSArray *titles=@[@"打个招呼",@"同步当前石头",@"收回右下角",@"自由活动"];
    SEL actions[]={@selector(greet:),@selector(syncFromMenu:),@selector(summon:),@selector(toggleQuiet:)};
    for (NSUInteger i=0;i<titles.count;i++) {NSMenuItem *item=[menu addItemWithTitle:titles[i] action:actions[i] keyEquivalent:@""];item.target=self;if(i==3)item.state=self.roaming;}
    NSMenuItem *size=[menu addItemWithTitle:@"桌宠大小" action:nil keyEquivalent:@""];size.submenu=[NSMenu new];
    NSArray *sizes=@[@"小",@"中",@"大"];
    for (NSInteger i=0;i<3;i++){NSMenuItem *item=[size.submenu addItemWithTitle:sizes[i] action:@selector(selectSize:) keyEquivalent:@""];item.target=self;item.tag=i;item.state=i==self.sizeIndex;}
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *settings=[menu addItemWithTitle:@"桌宠设置…" action:@selector(showSettings:) keyEquivalent:@""];settings.target=self;
    NSMenuItem *hide=[menu addItemWithTitle:@"收起桌宠" action:@selector(dismiss:) keyEquivalent:@""];hide.target=self;
    return menu;
}
- (void)invalidate {
    [self savePlacement];self.invalidated=YES;[self.timer invalidate];self.timer=nil;[self.panel orderOut:nil];
    self.syncStone=nil;self.dismissPet=nil;self.openSettings=nil;self.interactionEnded=nil;
}
- (void)dealloc {[self.timer invalidate];[self.panel orderOut:nil];}
@end
