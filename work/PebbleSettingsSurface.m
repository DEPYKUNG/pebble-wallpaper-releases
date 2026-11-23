#import "PebbleSettingsSurface.h"
#if __has_include(<AppKit/NSGlassEffectView.h>)
#import <AppKit/NSGlassEffectView.h>
#endif

@interface PebbleOpaqueSettingsBackdrop : NSView
@end
@implementation PebbleOpaqueSettingsBackdrop
- (void)drawRect:(NSRect)rect {
    [NSColor.windowBackgroundColor setFill]; NSRectFill(self.bounds);
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES;
}
@end

@interface PebbleSettingsSurface ()
@property (nonatomic, strong, readwrite) NSView *contentView;
@property (nonatomic, strong, readwrite) NSView *effectView;
@property (nonatomic, strong) PebbleOpaqueSettingsBackdrop *opaqueBackdrop;
@property BOOL forceSolid;
@end

@implementation PebbleSettingsSurface
- (instancetype)initWithFrame:(NSRect)frame preferFrosted:(BOOL)preferFrosted forceSolid:(BOOL)forceSolid {
    if (!(self = [super initWithFrame:frame])) return nil;
    _forceSolid = forceSolid;
    _contentView = [[NSView alloc] initWithFrame:self.bounds];
    _contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _opaqueBackdrop = [[PebbleOpaqueSettingsBackdrop alloc] initWithFrame:self.bounds];
    _opaqueBackdrop.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_contentView addSubview:_opaqueBackdrop];
#if __has_include(<AppKit/NSGlassEffectView.h>)
    if (@available(macOS 26.0, *)) {
        if (!preferFrosted) {
            NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:self.bounds];
            glass.style = NSGlassEffectViewStyleRegular;
            glass.cornerRadius = 20;
            glass.contentView = _contentView;
            _effectView = glass;
        }
    }
#endif
    if (!_effectView) {
        NSVisualEffectView *frosted = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
        frosted.material = NSVisualEffectMaterialWindowBackground;
        frosted.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        frosted.state = NSVisualEffectStateActive;
        [frosted addSubview:_contentView];
        _effectView = frosted;
    }
    // Never fade the effect view itself: doing so weakens both blur and legibility.
    _effectView.alphaValue = 1;
    _effectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:_effectView];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(accessibilityChanged:)
        name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
    [self accessibilityChanged:nil];
    return self;
}
- (void)accessibilityChanged:(NSNotification *)notification {
    self.opaqueBackdrop.hidden = !(self.forceSolid || NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency);
    self.opaqueBackdrop.needsDisplay = YES;
}
- (void)dealloc {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
}
@end
