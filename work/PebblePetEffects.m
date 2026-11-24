#import "PebblePetEffects.h"
#import "PebblePetPhysics.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#if __has_include(<AppKit/NSGlassEffectView.h>)
#import <AppKit/NSGlassEffectView.h>
#endif

static const CGFloat BubbleInset = 18;
static const CGFloat EpisodeColumnWidth = 81;
static const CGFloat EpisodeColumnGap = 8;

@interface PebblePetEffectPanel : NSPanel @end
@implementation PebblePetEffectPanel
- (BOOL)canBecomeKeyWindow{return NO;}
- (BOOL)canBecomeMainWindow{return NO;}
@end
@interface PebblePetBubbleView : NSView
@property NSTextField *label;
@property NSTextView *linkedText;
@property NSButton *episodeButton;
@property NSURL *episodeURL;
@property NSAttributedString *episodeTitle;
@property (copy) void (^updateAction)(void);
@property NSButton *restartButton, *restButton;
@property (copy) void (^restartFocus)(void);
@property (copy) void (^beginBreak)(void);
- (void)openEpisode:(id)sender;
@property BOOL tailAbove;
@property NSView *glassBacking;
- (void)updateGlassFrame;
@end
@implementation PebblePetBubbleView
- (void)openEpisode:(id)sender {
    if (self.updateAction) {
        void (^action)(void) = self.updateAction;
        self.updateAction = nil;
        self.episodeButton.enabled = NO;
        action();
    } else if (self.episodeURL) {
        [NSWorkspace.sharedWorkspace openURL:self.episodeURL];
    }
}
- (void)chooseFocus:(NSButton *)sender {
    void (^action)(void) = sender == self.restartButton ? self.restartFocus : self.beginBreak;
    self.restartFocus = nil;
    self.beginBreak = nil;
    self.restartButton.enabled = self.restButton.enabled = NO;
    if (action) action();
}
- (BOOL)isOpaque{return NO;}
- (void)updateGlassFrame {
    NSRect box=NSInsetRect(self.bounds,6,6);
    if (!self.tailAbove) box.origin.y+=6;
    box.size.height-=6;
    self.glassBacking.frame=box;
}
- (void)drawRect:(NSRect)dirty {
    if (self.glassBacking) return;
    NSRect box=NSInsetRect(self.bounds,6,6);if(!self.tailAbove)box.origin.y+=6;box.size.height-=6;
    NSBezierPath *path=[NSBezierPath bezierPathWithRoundedRect:box xRadius:13 yRadius:13];
    NSBezierPath *tail=[NSBezierPath bezierPath];
    CGFloat base=self.tailAbove?NSMaxY(box)-1:NSMinY(box)+1;
    CGFloat tip=self.tailAbove?NSMaxY(box)+7:NSMinY(box)-7;
    [tail moveToPoint:NSMakePoint(NSMidX(box)-7,base)];
    [tail lineToPoint:NSMakePoint(NSMidX(box),tip)];
    [tail lineToPoint:NSMakePoint(NSMidX(box)+7,base)];[tail closePath];[path appendBezierPath:tail];
    [NSGraphicsContext saveGraphicsState];NSShadow *shadow=[NSShadow new];
    shadow.shadowBlurRadius=5;shadow.shadowOffset=NSMakeSize(0,-1);shadow.shadowColor=[NSColor colorWithWhite:0 alpha:.12];[shadow set];
    [[NSColor.windowBackgroundColor colorWithAlphaComponent:.97] setFill];[path fill];
    [NSGraphicsContext restoreGraphicsState];
}
@end
@interface PebblePetRippleView : NSView
@property CGFloat progress;
@property NSColor *color;
@end
@implementation PebblePetRippleView
- (BOOL)isOpaque{return NO;}
- (void)drawRect:(NSRect)dirty {
    [[self.color colorWithAlphaComponent:(1-self.progress)*.55] setStroke];
    for(NSUInteger i=0;i<2;i++){
        CGFloat phase=MAX(0,MIN(1,self.progress-i*.17));
        if(phase<=0)continue;
        CGFloat width=18+80*phase,height=4+22*phase;
        NSBezierPath *ring=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(self.bounds)-width/2,NSMidY(self.bounds)-height/2,width,height)];
        ring.lineWidth=1.4;[ring stroke];
    }
}
@end
@interface PebblePetEffects ()
@property (nonatomic, readwrite) NSPanel *bubblePanel;
@property (nonatomic, readwrite) NSString *message;
@property PebblePetMessagePriority priority;
@property NSTimeInterval expiry;
@property NSMutableArray<NSDictionary *> *ripples;
@end
@implementation PebblePetEffects
- (instancetype)init {if((self=[super init])){_speechEnabled=YES;_ripples=[NSMutableArray array];}return self;}
- (NSPanel *)newPanel:(NSRect)frame title:(NSString *)title {
    NSPanel *panel=[[PebblePetEffectPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    panel.title=title;panel.releasedWhenClosed=NO;panel.opaque=NO;panel.hasShadow=NO;
    panel.backgroundColor=NSColor.clearColor;panel.hidesOnDeactivate=NO;panel.ignoresMouseEvents=YES;
    panel.level=NSFloatingWindowLevel+1;
    panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorIgnoresCycle;
    return panel;
}
- (void)setSpeechEnabled:(BOOL)enabled {
    _speechEnabled=enabled;if(!enabled){self.message=nil;self.expiry=0;[self.bubblePanel close];self.bubblePanel=nil;}
}
- (BOOL)showMessage:(NSString *)text priority:(PebblePetMessagePriority)priority duration:(NSTimeInterval)duration {
    return [self showMessage:text episodeURL:nil priority:priority duration:duration];
}
- (BOOL)showMessage:(NSString *)text episodeURL:(NSURL *)url priority:(PebblePetMessagePriority)priority duration:(NSTimeInterval)duration {
    if(!self.speechEnabled || ![text isKindOfClass:NSString.class])return NO;
    text=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!text.length)return NO;
    if(text.length>100)text=[[text substringWithRange:[text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,99)]] stringByAppendingString:@"…"];
    double now=CACurrentMediaTime();
    if(self.message && self.expiry>now && self.priority>priority)return NO;
    self.message=text;self.priority=priority;
    self.expiry=now+(isfinite(duration)?MAX(2,MIN(30,duration)):5);
    if(!self.bubblePanel) {
        self.bubblePanel=[self newPanel:NSMakeRect(0,0,240,72) title:@"鹅卵石说话气泡"];
        PebblePetBubbleView *view=[[PebblePetBubbleView alloc] initWithFrame:NSMakeRect(0,0,240,72)];
#if __has_include(<AppKit/NSGlassEffectView.h>)
        if (@available(macOS 26.0, *)) {
            NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:NSZeroRect];
            glass.style = NSGlassEffectViewStyleClear;
            glass.cornerRadius = 18;
            view.glassBacking = glass;
            [view addSubview:glass];
        }
#endif
        view.label=[NSTextField wrappingLabelWithString:@""];view.label.font=[NSFont systemFontOfSize:13];view.label.textColor=NSColor.labelColor;
        view.label.alignment=NSTextAlignmentCenter;view.label.frame=NSMakeRect(18,22,204,38);
        view.label.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
        [view addSubview:view.label];
        view.linkedText = [[NSTextView alloc] initWithFrame:NSMakeRect(18,22,204,68)];
        view.linkedText.drawsBackground = NO;
        view.linkedText.editable = NO;
        view.linkedText.selectable = NO;
        view.linkedText.textContainerInset = NSZeroSize;
        view.linkedText.textContainer.lineFragmentPadding = 0;
        [view addSubview:view.linkedText];
        view.episodeButton = [NSButton buttonWithTitle:@"去小宇宙听" target:view action:@selector(openEpisode:)];
        view.episodeButton.bordered = NO;
        view.episodeButton.toolTip = @"打开小宇宙单集";
        view.episodeButton.accessibilityLabel = @"去小宇宙听";
        NSURL *asset = [NSBundle.mainBundle URLForResource:@"pet-episode-planet" withExtension:@"png"];
        NSImage *planet = asset ? [[NSImage alloc] initWithContentsOfURL:asset] : nil;
        planet.size = NSMakeSize(9.5, 9.5 * planet.size.height / MAX(1, planet.size.width));
        NSAttributedString *style = [[NSAttributedString alloc] initWithString:@"去" attributes:@{
            NSFontAttributeName:[NSFont systemFontOfSize:10], NSForegroundColorAttributeName:NSColor.secondaryLabelColor}];
        NSMutableAttributedString *title = [style mutableCopy];
        if (planet) {
            [title addAttribute:NSKernAttributeName value:@3 range:NSMakeRange(0,1)];
            NSTextAttachment *attachment = [NSTextAttachment new];
            attachment.attachmentCell = [[NSTextAttachmentCell alloc] initImageCell:planet];
            [title appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
        }
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:@"小宇宙听"
                                                                      attributes:[style attributesAtIndex:0 effectiveRange:nil]]];
        view.episodeTitle = title;
        [view addSubview:view.episodeButton];
        self.bubblePanel.contentView=view;
    }
    PebblePetBubbleView *view=(PebblePetBubbleView *)self.bubblePanel.contentView;
    CGFloat height=ceil([text boundingRectWithSize:NSMakeSize(204,1000) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:view.label.font}].size.height);
    BOOL validLink = [url.scheme.lowercaseString isEqualToString:@"https"] &&
        [url.host.lowercaseString isEqualToString:@"www.xiaoyuzhoufm.com"] &&
        [url.path rangeOfString:@"^/episode/[0-9a-fA-F]{24}$" options:NSRegularExpressionSearch].location != NSNotFound;
    view.updateAction = nil;
    view.restartFocus = nil;
    view.beginBreak = nil;
    view.restartButton.hidden = view.restButton.hidden = YES;
    view.episodeButton.enabled = YES;
    view.episodeButton.attributedTitle = view.episodeTitle;
    view.episodeButton.accessibilityLabel = @"去小宇宙听";
    view.episodeButton.toolTip = @"打开小宇宙单集";
    view.episodeURL = validLink ? url : nil;
    view.label.hidden = validLink;
    view.linkedText.hidden = view.episodeButton.hidden = !validLink;
    self.bubblePanel.ignoresMouseEvents = YES;
    CGFloat bodyWidth = 204;
    CGFloat panelWidth = 240;
    if (validLink) {
        NSTextView *body = view.linkedText;
        NSDictionary *attributes = @{NSFontAttributeName:view.label.font,
                                     NSForegroundColorAttributeName:NSColor.labelColor};
        NSRect natural = [text boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                             options:NSStringDrawingUsesLineFragmentOrigin
                                          attributes:attributes];
        bodyWidth = MAX(24, MIN(218, ceil(natural.size.width)+1));
        panelWidth = bodyWidth + 2*BubbleInset + EpisodeColumnGap + EpisodeColumnWidth;
        body.textContainer.widthTracksTextView = NO;
        body.textContainer.heightTracksTextView = NO;
        body.textContainer.containerSize = NSMakeSize(bodyWidth, CGFLOAT_MAX);
        [body.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attributes]];
        [body.layoutManager ensureLayoutForTextContainer:body.textContainer];
        height = MAX(18, ceil(NSMaxY([body.layoutManager usedRectForTextContainer:body.textContainer])));
    } else {
        height = MAX(18, MIN(68, height));
    }
    [self.bubblePanel setContentSize:NSMakeSize(panelWidth,height+34)];
    view.label.frame=NSMakeRect(BubbleInset,22,bodyWidth,height);view.label.maximumNumberOfLines=4;
    [view updateGlassFrame];
    view.label.stringValue=text;
    if (validLink) view.linkedText.frame = view.label.frame;
    self.bubblePanel.contentView.accessibilityLabel=text;
    self.bubblePanel.contentView.needsDisplay=YES;
    self.bubblePanel.alphaValue=1;
    // Position and show only in updateAtTime, after the caller provides an anchor.
    return YES;
}
- (BOOL)showUpdateWithAction:(void (^)(void))action {
    if (![self showMessage:@"更新到最新版" priority:PebblePetMessageReminder duration:30]) return NO;
    PebblePetBubbleView *view = (PebblePetBubbleView *)self.bubblePanel.contentView;
    view.updateAction = action;
    view.label.hidden = YES;
    view.episodeButton.title = self.message;
    view.episodeButton.font = view.label.font;
    view.episodeButton.accessibilityLabel = self.message;
    view.episodeButton.toolTip = self.message;
    view.episodeButton.hidden = NO;
    [self.bubblePanel setContentSize:NSMakeSize(160,self.bubblePanel.frame.size.height)];
    return YES;
}

- (BOOL)showFocusChoice:(NSString *)message restart:(void (^)(void))restart rest:(void (^)(void))rest {
    if (![self showMessage:message priority:PebblePetMessageInteraction duration:25]) return NO;
    PebblePetBubbleView *view = (PebblePetBubbleView *)self.bubblePanel.contentView;
    if (!view.restartButton) {
        view.restartButton = [NSButton buttonWithTitle:@"再来一轮" target:view action:@selector(chooseFocus:)];
        view.restButton = [NSButton buttonWithTitle:@"休息 5 分钟" target:view action:@selector(chooseFocus:)];
        [view addSubview:view.restartButton];
        [view addSubview:view.restButton];
    }
    view.restartFocus = restart;
    view.beginBreak = rest;
    view.restartButton.enabled = view.restButton.enabled = YES;
    view.restartButton.hidden = NO;
    view.restButton.hidden = rest == nil;
    NSSize size = self.bubblePanel.frame.size;
    size.height += 32;
    [self.bubblePanel setContentSize:size];
    view.label.frame = NSMakeRect(18,54,204,size.height-66);
    return YES;
}

- (void)addRippleAt:(NSPoint)point color:(NSColor *)color {
    if(NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion)return;
    while(self.ripples.count>=6){[self.ripples.firstObject[@"panel"] close];[self.ripples removeObjectAtIndex:0];}
    NSPanel *panel=[self newPanel:NSMakeRect(point.x-56,point.y-18,112,36) title:@"水漂涟漪"];
    panel.level=NSFloatingWindowLevel;
    PebblePetRippleView *view=[[PebblePetRippleView alloc] initWithFrame:NSMakeRect(0,0,112,36)];view.color=color ?: NSColor.secondaryLabelColor;
    panel.contentView=view;[panel orderFrontRegardless];
    [self.ripples addObject:@{@"panel":panel,@"time":@(CACurrentMediaTime())}];
}
- (NSUInteger)rippleCount{return self.ripples.count;}
- (void)updateAtTime:(NSTimeInterval)time anchor:(NSRect)anchor visible:(NSRect)visible {
    for(NSDictionary *entry in self.ripples.copy){
        NSPanel *panel=entry[@"panel"];double age=time-[entry[@"time"] doubleValue];
        if(age>=.72){[panel close];[self.ripples removeObject:entry];}
        else {PebblePetRippleView *view=(PebblePetRippleView *)panel.contentView;view.progress=MAX(0,age/.72);view.needsDisplay=YES;}
    }
    if(self.message && self.expiry>time && self.speechEnabled) {
        NSRect frame=PebblePetBubbleFrame(anchor,visible,self.bubblePanel.frame.size);
        [self.bubblePanel setFrame:frame display:YES];
        PebblePetBubbleView *view=(PebblePetBubbleView *)self.bubblePanel.contentView;
        view.tailAbove=NSMidY(frame)<NSMidY(anchor);
        [view updateGlassFrame];
        NSRect label=view.label.frame;label.origin.y=view.tailAbove?14:22;view.label.frame=label;view.needsDisplay=YES;
        if (view.restartFocus) {
            CGFloat base = label.origin.y;
            label.origin.y += 32;
            view.label.frame = label;
            view.restartButton.frame = NSMakeRect(view.beginBreak ? 18 : 68,base,100,25);
            view.restButton.frame = NSMakeRect(122,base,100,25);
            NSPoint mouse = [self.bubblePanel convertPointFromScreen:NSEvent.mouseLocation];
            BOOL overButton = NSPointInRect(mouse,view.restartButton.frame) ||
                (view.beginBreak && NSPointInRect(mouse,view.restButton.frame));
            self.bubblePanel.ignoresMouseEvents = !overButton;
            if (NSPointInRect(mouse,view.bounds)) self.expiry = MAX(self.expiry,time+.5);
        }
        if (view.episodeURL) {
            view.linkedText.frame = label;
            view.episodeButton.frame = NSMakeRect(NSMaxX(label)+EpisodeColumnGap, NSMaxY(label)-17, EpisodeColumnWidth, 19);
            NSPoint mouse = [self.bubblePanel convertPointFromScreen:NSEvent.mouseLocation];
            BOOL overLink = NSPointInRect(mouse, view.episodeButton.frame);
            self.bubblePanel.ignoresMouseEvents = !overLink;
            if (NSPointInRect(mouse, view.bounds)) self.expiry = MAX(self.expiry, time + .5);
        }
        if (view.updateAction) {
            view.episodeButton.frame = NSInsetRect(view.bounds,6,9);
            NSPoint mouse = [self.bubblePanel convertPointFromScreen:NSEvent.mouseLocation];
            BOOL overButton = NSPointInRect(mouse,view.episodeButton.frame);
            self.bubblePanel.ignoresMouseEvents = !overButton;
            if (overButton) self.expiry = MAX(self.expiry,time+.5);
        }
        self.bubblePanel.alphaValue=MAX(0,MIN(1,(self.expiry-time)/.18));
        if(!self.bubblePanel.isVisible){
            [self.bubblePanel orderFrontRegardless];
            if(!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion){
                self.bubblePanel.contentView.wantsLayer=YES;
                CABasicAnimation *pop=[CABasicAnimation animationWithKeyPath:@"transform.scale"];
                pop.fromValue=@.96;pop.toValue=@1;pop.duration=.18;
                pop.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                [self.bubblePanel.contentView.layer addAnimation:pop forKey:@"speech-entry"];
            }
        }
    } else {[self.bubblePanel orderOut:nil];self.message=nil;self.expiry=0;}
}
- (void)clear {
    self.message=nil;self.expiry=0;[self.bubblePanel close];self.bubblePanel=nil;
    for(NSDictionary *entry in self.ripples)[entry[@"panel"] close];
    [self.ripples removeAllObjects];
}
- (void)dealloc {[self clear];}
@end
