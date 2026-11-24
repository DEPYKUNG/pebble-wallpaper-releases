#import "PebblePet.h"
#import "PebblePetPhysics.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static NSString *const PetPlacementKey=@"DesktopPetPlacement";
static const CGFloat PetSizes[]={112,156,204};
typedef NS_ENUM(NSInteger, PebblePetActivity) {
    PebblePetActivityNone, PebblePetActivityPodcast, PebblePetActivitySleep
};
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
@property PebblePetSkip skipState;
@property (nonatomic, readwrite) PebblePetEffects *effects;
@property NSColor *stoneColor;
@property (copy) NSArray<NSString *> *quotes;
@property NSUInteger lastQuoteIndex;
@property BOOL skipEnding;
@property NSUInteger finishedSkips;
@property NSTimeInterval nextSpeech,impactUntil;
- (void)startSkipping:(NSPoint)velocity;
- (void)cancelPlay;
- (NSRect)effectAnchor;
@property CGFloat angle,stretch;
@property PebblePetActivity activity;
@property NSTimeInterval activityStart,activityEnd;
@property BOOL automaticActivity,justWoke;
- (void)startActivity:(PebblePetActivity)activity automatic:(BOOL)automatic at:(NSTimeInterval)now;
- (void)endActivityAt:(NSTimeInterval)now;
- (void)recordPodcast:(id)sender;
- (void)takeNap:(id)sender;
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
// Light direction and fine matte grain match the rendered stone.
static NSImage *PebblePodcastMicrophone(void) {
    static NSImage *image;
    if (image) return image;
    image=[NSImage imageWithSize:NSMakeSize(38,53) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        NSColor *(^silver)(CGFloat)=^NSColor *(CGFloat light){
            return [NSColor colorWithSRGBRed:light*.96 green:light*.99 blue:light alpha:1];
        };
        void (^shade)(NSBezierPath *,CGFloat,CGFloat,CGFloat)=^(NSBezierPath *path,CGFloat start,CGFloat end,CGFloat angle){
            [[[NSGradient alloc] initWithStartingColor:silver(start) endingColor:silver(end)] drawInBezierPath:path angle:angle];
        };
        [[NSColor colorWithWhite:.17 alpha:.19] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(3,1,32,7)] fill];
        shade([NSBezierPath bezierPathWithOvalInRect:NSMakeRect(4,3,29,9)],.42,.79,90);
        shade([NSBezierPath bezierPathWithOvalInRect:NSMakeRect(4,5,29,8)],.61,.89,90);
        shade([NSBezierPath bezierPathWithRoundedRect:NSMakeRect(16,8,5,21) xRadius:2 yRadius:2],.87,.41,0);
        NSBezierPath *yoke=[NSBezierPath bezierPath];
        [yoke moveToPoint:NSMakePoint(7,34)];
        [yoke curveToPoint:NSMakePoint(30,34) controlPoint1:NSMakePoint(5,15) controlPoint2:NSMakePoint(32,15)];
        yoke.lineWidth=2.6;
        yoke.lineCapStyle=NSLineCapStyleRound;
        [silver(.56) setStroke];
        [yoke stroke];
        NSBezierPath *head=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(9,24,19,27) xRadius:8 yRadius:8];
        shade(head,.95,.46,-24);
        [NSGraphicsContext saveGraphicsState];
        [head addClip];
        uint32_t grain=713;
        for (NSUInteger i=0;i<460;i++) {
            grain=1664525u*grain+1013904223u;
            CGFloat x=9+19*(grain>>16)/65535.0;
            grain=1664525u*grain+1013904223u;
            CGFloat y=24+27*(grain>>16)/65535.0;
            [[NSColor colorWithWhite:(i%3==0?1:.18) alpha:.25] setFill];
            NSRectFillUsingOperation(NSMakeRect(x,y,.40,.55),NSCompositingOperationSourceOver);
        }
        for (NSInteger row=0;row<8;row++) {
            NSBezierPath *mesh=[NSBezierPath bezierPath];
            CGFloat y=29+row*2.2;
            [mesh moveToPoint:NSMakePoint(10,y)];
            [mesh curveToPoint:NSMakePoint(27,y+.8) controlPoint1:NSMakePoint(15,y-1.0) controlPoint2:NSMakePoint(24,y-.8)];
            [[NSColor colorWithWhite:.23 alpha:.37] setStroke];
            mesh.lineWidth=.52;
            [mesh stroke];
        }
        [NSGraphicsContext restoreGraphicsState];
        shade([NSBezierPath bezierPathWithRoundedRect:NSMakeRect(9,23,19,6) xRadius:2 yRadius:2],.93,.46,0);
        [[NSColor colorWithSRGBRed:.81 green:.30 blue:.25 alpha:1] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(17,24.5,2.7,2.7)] fill];
        return YES;
    }];
    return image;
}

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
    if (owner.activity==PebblePetActivityPodcast) {
        CGFloat scale=MAX(.92,MIN(1.30,NSWidth(self.bounds)/204.0));
        NSSize size=NSMakeSize(38*scale,53*scale);
        CGFloat right=MIN(NSMaxX(self.bounds)-4,NSMaxX(art)+22);
        NSRect mic=NSMakeRect(right-size.width,NSMinY(art)-4,size.width,size.height);
        [PebblePodcastMicrophone() drawInRect:mic fromRect:NSZeroRect
                                   operation:NSCompositingOperationSourceOver fraction:1];
    } else if (owner.activity==PebblePetActivitySleep) {
        CGFloat y=MIN(NSHeight(self.bounds)-24,NSMaxY(art)-4);
        [@"z Z" drawAtPoint:NSMakePoint(NSMaxX(art)-22,y) withAttributes:@{
            NSFontAttributeName:[NSFont systemFontOfSize:17 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName:NSColor.systemIndigoColor
        }];
    }
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
- (BOOL)interacting {return self.dragging || self.menuOpen || self.skipState.active || self.skipEnding;}
- (BOOL)skipping {return self.skipState.active;}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if (!(self=[super init])) return nil;
    _defaults=defaults;_roaming=![defaults boolForKey:@"DesktopPetQuiet"];
    _skippingEnabled=![defaults boolForKey:@"DesktopPetSkippingDisabled"];
    _speechEnabled=![defaults boolForKey:@"DesktopPetSpeechDisabled"];
    _casualSpeech=[defaults boolForKey:@"DesktopPetCasualSpeech"];
    NSInteger savedLimit=[defaults integerForKey:@"DesktopPetSkipLimit"];
    _skipLimit=(savedLimit==3 || savedLimit==7)?savedLimit:5;
    _lastQuoteIndex=NSNotFound;
    NSURL *quoteURL=[NSBundle.mainBundle URLForResource:@"pet-quotes" withExtension:@"json"];
    NSData *quoteData=quoteURL ? [NSData dataWithContentsOfURL:quoteURL] : nil;
    id records=quoteData ? [NSJSONSerialization JSONObjectWithData:quoteData options:0 error:NULL] : nil;
    NSMutableArray<NSString *> *quotes=[NSMutableArray array];
    if ([records isKindOfClass:NSArray.class]) {
        for (id record in records) {
            if ([record isKindOfClass:NSString.class] && [record length]) [quotes addObject:record];
        }
    }
    _quotes=[quotes copy];
    _effects=[PebblePetEffects new];_effects.speechEnabled=_speechEnabled;
    _nextSpeech=CACurrentMediaTime()+45;
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
    double red=0,green=0,blue=0,count=0;
    for(NSInteger y=0;y<self.bitmap.pixelsHigh;y+=MAX(1,self.bitmap.pixelsHigh/10))
        for(NSInteger x=0;x<self.bitmap.pixelsWide;x+=MAX(1,self.bitmap.pixelsWide/10)){
            NSColor *c=[[self.bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            if(c.alphaComponent>.8 && c.redComponent+c.greenComponent+c.blueComponent>.3 && c.redComponent+c.greenComponent+c.blueComponent<2.7){red+=c.redComponent;green+=c.greenComponent;blue+=c.blueComponent;count++;}
        }
    self.stoneColor=count?[NSColor colorWithSRGBRed:red/count green:green/count blue:blue/count alpha:1]:NSColor.secondaryLabelColor;
    self.petView.needsDisplay=YES;
    [self setSuspended:self.suspended];return YES;
}
- (void)setRoaming:(BOOL)roaming {
    _roaming=roaming;[self.defaults setBool:!roaming forKey:@"DesktopPetQuiet"];
    self.nextWander=CACurrentMediaTime()+8;
    if (!roaming && self.automaticActivity) {
        [self endActivityAt:CACurrentMediaTime()];
        [self.effects clear];
    }
    if(self.interactionEnded)self.interactionEnded();
}
- (void)setSkippingEnabled:(BOOL)enabled {
    _skippingEnabled=enabled;[self.defaults setBool:!enabled forKey:@"DesktopPetSkippingDisabled"];
    if(!enabled){[self cancelPlay];self.body=(PebblePetBody){self.panel.frame.origin,NSZeroPoint,NO};}
    if(self.interactionEnded)self.interactionEnded();
}
- (void)setSkipLimit:(NSInteger)limit {
    _skipLimit=(limit==3 || limit==7)?limit:5;
    [self.defaults setInteger:_skipLimit forKey:@"DesktopPetSkipLimit"];
    if(self.interactionEnded)self.interactionEnded();
}
- (void)setSpeechEnabled:(BOOL)enabled {
    _speechEnabled=enabled;self.effects.speechEnabled=enabled;
    [self.defaults setBool:!enabled forKey:@"DesktopPetSpeechDisabled"];
    if(self.interactionEnded)self.interactionEnded();
}
- (void)setCasualSpeech:(BOOL)enabled {
    _casualSpeech=enabled;self.nextSpeech=CACurrentMediaTime()+45;
    [self.defaults setBool:enabled forKey:@"DesktopPetCasualSpeech"];
    if(self.interactionEnded)self.interactionEnded();
}
- (NSRect)effectAnchor {return NSOffsetRect(self.artRect,NSMinX(self.panel.frame),NSMinY(self.panel.frame));}
- (void)endActivityAt:(NSTimeInterval)now {
    self.activity=PebblePetActivityNone;
    self.automaticActivity=NO;
    self.petView.accessibilityValue=nil;
    self.nextWander=now+20+arc4random_uniform(16);
    self.petView.needsDisplay=YES;
}
- (void)startActivity:(PebblePetActivity)activity automatic:(BOOL)automatic at:(NSTimeInterval)now {
    if (self.suspended || self.invalidated || !self.stoneImage || self.dragging) return;
    [self cancelPlay];
    self.celebrateUntil=0;
    self.activity=activity;
    self.automaticActivity=automatic;
    self.activityStart=now;
    self.activityEnd=now+(activity==PebblePetActivitySleep?18:15);
    self.body=(PebblePetBody){self.panel.frame.origin,NSZeroPoint,YES};
    self.petView.accessibilityValue=activity==PebblePetActivitySleep?@"睡觉中":@"录播客中";
    self.petView.needsDisplay=YES;
    if (activity==PebblePetActivityPodcast && (!automatic || self.casualSpeech)) [self say:nil];
}
- (void)recordPodcast:(id)sender {
    [self startActivity:PebblePetActivityPodcast automatic:NO at:CACurrentMediaTime()];
}
- (void)takeNap:(id)sender {
    [self startActivity:PebblePetActivitySleep automatic:NO at:CACurrentMediaTime()];
}
- (void)cancelPlay {
    if (self.activity!=PebblePetActivityNone) [self endActivityAt:CACurrentMediaTime()];
    PebblePetSkip state=self.skipState;state.active=NO;self.skipState=state;
    self.skipEnding=NO;self.finishedSkips=0;[self.effects clear];
}
- (BOOL)showMessage:(NSString *)message priority:(PebblePetMessagePriority)priority duration:(NSTimeInterval)duration {
    if(self.suspended || self.invalidated || !self.stoneImage)return NO;
    BOOL accepted=[self.effects showMessage:message priority:priority duration:duration];
    [self.effects updateAtTime:CACurrentMediaTime() anchor:self.effectAnchor visible:(self.panel.screen ?: NSScreen.screens.firstObject).visibleFrame];
    return accepted;
}
- (void)speakQuoteWithPriority:(PebblePetMessagePriority)priority {
    NSArray<NSString *> *words=self.quotes.count ? self.quotes :
        @[@"在呢。", @"慢一点，也没关系。", @"今天也稳稳当当。", @"先抛一颗石头，再往前走。"];
    BOOL excludePrevious=words.count>1 && self.lastQuoteIndex<words.count;
    NSUInteger index=arc4random_uniform((uint32_t)(words.count-excludePrevious));
    if (excludePrevious && index>=self.lastQuoteIndex) index++;
    NSString *quote=words[index];
    if ([self showMessage:quote priority:priority duration:MAX(5,MIN(15,quote.length/7.0))]) {
        self.lastQuoteIndex=index;
    }
}
- (void)say:(id)sender {
    [self speakQuoteWithPriority:PebblePetMessageInteraction];
}
- (void)startSkipping:(NSPoint)velocity {
    [self cancelPlay];
    NSRect visible=(self.panel.screen ?: NSScreen.screens.firstObject).visibleFrame;
    self.skipState=PebblePetBeginSkip((PebblePetBody){self.panel.frame.origin,velocity,NO},visible,self.panel.frame.size,self.skipLimit);
    self.body=self.skipState.body;self.nextWander=CACurrentMediaTime()+15;
}
- (void)skip:(id)sender {
    if(!self.skippingEnabled || self.suspended || !self.stoneImage)return;
    if(NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion){
        [self showMessage:@"减少动态效果已开启，先轻轻歇一会儿。" priority:PebblePetMessageInteraction duration:5];return;
    }
    NSRect visible=(self.panel.screen ?: NSScreen.screens.firstObject).visibleFrame;
    double direction=NSMidX(self.panel.frame)>NSMidX(visible)?-1:1;
    [self startSkipping:NSMakePoint(direction*780,0)];
}
- (void)setSizeIndex:(NSInteger)index {
    [self cancelPlay];
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
    if (suspended) {[self cancelPlay];self.dragging=NO;self.menuOpen=NO;self.body=(PebblePetBody){self.panel.frame.origin,NSZeroPoint,NO};}
    if (suspended || self.invalidated || !self.stoneImage) {[self.panel orderOut:nil];return;}
    self.lastTick=CACurrentMediaTime();self.nextWander=self.lastTick+8;
    __weak typeof(self) weakSelf=self;
    BOOL reduced=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion||NSProcessInfo.processInfo.lowPowerModeEnabled;
    if(NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion && (self.skipState.active || self.skipEnding)){
        [self cancelPlay];NSPoint point=self.panel.frame.origin;point.y=NSMinY((self.panel.screen ?: NSScreen.screens.firstObject).visibleFrame);
        [self.panel setFrameOrigin:point];self.body=(PebblePetBody){point,NSZeroPoint,YES};
    }
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
    if(!self.dragging && !self.menuOpen) {
        if (self.activity!=PebblePetActivityNone && now>=self.activityEnd) {
            [self endActivityAt:now];
            [self.effects clear];
            self.body=(PebblePetBody){self.panel.frame.origin,NSZeroPoint,NO};
        }
        BOOL wasResting=self.body.resting;
        PebblePetBody body=self.body;
        if (self.activity!=PebblePetActivityNone) {
            CGFloat elapsed=now-self.activityStart;
            CGFloat pose=self.activity==PebblePetActivitySleep?-20:sin(elapsed*5)*4;
            self.angle=reduced?0:self.angle+(pose-self.angle)*MIN(1,dt*6);
            self.stretch=reduced?1:1+sin(elapsed*2)*.014;
            self.petView.needsDisplay=YES;
        } else if(self.skipState.active) {
            NSUInteger previous=self.skipState.bounces;
            self.skipState=PebblePetAdvanceSkip(self.skipState,visible,self.panel.frame.size,dt);
            body=self.skipState.body;
            if(self.skipState.bounces>previous) {
                self.impactUntil=now+.11;
                [self.effects addRippleAt:NSMakePoint(body.position.x+NSWidth(self.panel.frame)/2,self.skipState.waterline+26) color:self.stoneColor];
            }
            if(!self.skipState.active){self.skipEnding=YES;self.finishedSkips=self.skipState.bounces;}
        } else {
            if(body.resting && self.roaming && !self.skipEnding && !reduced && now>self.nextWander) {
                NSUInteger choice=arc4random_uniform(3);
                if (choice!=0) {
                    [self startActivity:choice==1?PebblePetActivityPodcast:PebblePetActivitySleep automatic:YES at:now];
                    body=self.body;
                } else {
                    double direction=NSMidX(self.panel.frame)>NSMidX(visible)?-1:1;
                    body.velocity=NSMakePoint(direction*(45+arc4random_uniform(45)),150);
                    body.resting=NO;
                    self.nextWander=now+10+arc4random_uniform(10);
                }
            }
            if(!body.resting)body=PebblePetAdvance(body,visible,self.panel.frame.size,dt);
        }
        [self.panel setFrameOrigin:body.position];self.body=body;
        if(!wasResting && body.resting)[self savePlacement];
        if(body.resting && self.skipEnding) {
            NSUInteger count=self.finishedSkips;self.skipEnding=NO;[self savePlacement];
            [self showMessage:count?[NSString stringWithFormat:@"漂了 %lu 下，落稳啦。",(unsigned long)count]:@"换个方向，再漂一次。" priority:PebblePetMessageInteraction duration:5];
            if(self.interactionEnded)self.interactionEnded();
        }
        if(self.activity==PebblePetActivityNone && body.resting && self.casualSpeech && self.speechEnabled && now>self.nextSpeech && !NSProcessInfo.processInfo.lowPowerModeEnabled) {
            [self speakQuoteWithPriority:PebblePetMessageAmbient];self.nextSpeech=now+75;
        }
        CGFloat desiredAngle=self.skipState.active?MAX(-18,MIN(18,-body.velocity.x*.02)):
            (body.resting?(reduced?0:sin(now*1.3)*1.2):MAX(-12,MIN(12,-body.velocity.x*.05)));
        if (self.activity==PebblePetActivityNone) {
            self.angle+=(desiredAngle-self.angle)*MIN(1,dt*10);
            self.stretch=reduced?1:(now<self.impactUntil?.91:1+sin(now*2.1)*.009);
        }
    }
    self.panel.ignoresMouseEvents=!self.dragging && ![self containsStoneAtScreenPoint:NSEvent.mouseLocation];
    [self.effects updateAtTime:now anchor:self.effectAnchor visible:visible];
    if(!reduced || !self.body.resting || self.celebrateUntil>now)self.petView.needsDisplay=YES;
}
- (void)beginDrag {[self beginDragAtPoint:NSEvent.mouseLocation time:CACurrentMediaTime()];}
- (void)beginDragAtPoint:(NSPoint)point time:(NSTimeInterval)now {
    self.justWoke=self.activity==PebblePetActivitySleep;
    [self cancelPlay];
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
    if (!self.moved && self.justWoke) {
        self.nextWander=now+25;
    } else if(!self.moved)[self greet:nil];
    else {
        if(self.skippingEnabled && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion && PebblePetShouldSkip(velocity))[self startSkipping:velocity];
        if(self.syncStone)self.syncStone();
    }
    self.justWoke=NO;
    [self savePlacement];if (self.interactionEnded) self.interactionEnded();
}
- (void)greet:(id)sender {
    if (self.activity==PebblePetActivitySleep) {
        [self cancelPlay];
        self.body=(PebblePetBody){self.panel.frame.origin,NSZeroPoint,NO};
        return;
    }
    [self cancelPlay];[self say:nil];
    BOOL reduced=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    self.body=(PebblePetBody){self.panel.frame.origin,reduced?NSZeroPoint:NSMakePoint(0,360),reduced};
    self.celebrateUntil=CACurrentMediaTime()+.7;self.nextWander=CACurrentMediaTime()+12;self.petView.needsDisplay=YES;
}
- (void)summon:(id)sender {
    [self cancelPlay];
    NSScreen *screen=NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    NSRect frame=self.panel.frame,visible=screen.visibleFrame;
    frame.origin=NSMakePoint(NSMaxX(visible)-NSWidth(frame)-28,NSMinY(visible));
    frame=PebblePetConstrainFrame(frame,visible);[self.panel setFrame:frame display:YES];
    self.body=(PebblePetBody){frame.origin,NSZeroPoint,YES};[self savePlacement];
    if (!self.suspended && self.stoneImage) [self.panel orderFrontRegardless];
}
- (void)refreshScreens {
    [self cancelPlay];
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
    NSMenuItem *skip=[menu addItemWithTitle:@"打个水漂" action:@selector(skip:) keyEquivalent:@""];skip.target=self;skip.enabled=self.skippingEnabled;
    NSMenuItem *say=[menu addItemWithTitle:@"说句话" action:@selector(say:) keyEquivalent:@""];say.target=self;say.enabled=self.speechEnabled;
    NSMenuItem *activities=[menu addItemWithTitle:@"做点什么" action:nil keyEquivalent:@""];
    activities.submenu=[NSMenu new];
    NSMenuItem *podcast=[activities.submenu addItemWithTitle:@"录播客" action:@selector(recordPodcast:) keyEquivalent:@""];
    NSMenuItem *sleep=[activities.submenu addItemWithTitle:@"睡觉" action:@selector(takeNap:) keyEquivalent:@""];
    podcast.target=self;
    sleep.target=self;
    menu.autoenablesItems=NO;
    NSMenuItem *size=[menu addItemWithTitle:@"桌宠大小" action:nil keyEquivalent:@""];size.submenu=[NSMenu new];
    NSArray *sizes=@[@"小",@"中",@"大"];
    for (NSInteger i=0;i<3;i++){NSMenuItem *item=[size.submenu addItemWithTitle:sizes[i] action:@selector(selectSize:) keyEquivalent:@""];item.target=self;item.tag=i;item.state=i==self.sizeIndex;}
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *settings=[menu addItemWithTitle:@"桌宠设置…" action:@selector(showSettings:) keyEquivalent:@""];settings.target=self;
    NSMenuItem *hide=[menu addItemWithTitle:@"收起桌宠" action:@selector(dismiss:) keyEquivalent:@""];hide.target=self;
    return menu;
}
- (void)invalidate {
    [self savePlacement];[self cancelPlay];self.invalidated=YES;[self.timer invalidate];self.timer=nil;[self.panel close];
    self.syncStone=nil;self.dismissPet=nil;self.openSettings=nil;self.interactionEnded=nil;
}
- (void)dealloc {[self.effects clear];[self.timer invalidate];[self.panel orderOut:nil];}
@end
