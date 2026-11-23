#import <AppKit/AppKit.h>

// One glass layer for the window; controls live in its contentView for native contrast treatment.
@interface PebbleSettingsSurface : NSView
@property (nonatomic, strong, readonly) NSView *contentView;
@property (nonatomic, strong, readonly) NSView *effectView;
- (instancetype)initWithFrame:(NSRect)frame preferFrosted:(BOOL)preferFrosted forceSolid:(BOOL)forceSolid;
@end
